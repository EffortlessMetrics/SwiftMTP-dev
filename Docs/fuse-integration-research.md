# FUSE-T Integration Research for MTP Filesystem Mount

> **Wave 38 Research Document** — feasibility study only, no implementation yet.
> Date: 2025-07-18

## Executive Summary

This document evaluates FUSE-T as an alternative (or complement) to the existing FileProvider integration for mounting MTP devices as macOS filesystems. FUSE-T is a kext-free, userspace FUSE implementation that uses an NFS v4 loopback server to expose FUSE filesystems as standard macOS volumes — no kernel extension required.

**Recommendation**: FUSE-T is a viable secondary mount strategy for power users and CLI workflows. It should complement FileProvider (not replace it) due to App Store restrictions and NFS permission requirements. A phased approach is recommended: implement a read-only FUSE mount first, then add write support behind a feature flag.

---

## 1. Technology Comparison

| Feature | FileProvider | FUSE-T | macFUSE |
|---|---|---|---|
| **Kernel extension required** | No | No | Yes (kext) |
| **macOS 26 compatible** | ✅ Yes | ✅ Yes (NFS-based) | ✅ Claimed, but kext loading increasingly restricted |
| **App Store eligible** | ✅ Yes | ❌ No (NFS server, system-level install) | ❌ No (kext) |
| **SIP compatible** | ✅ Yes | ✅ Yes | ⚠️ Requires reduced SIP on some configs |
| **Finder integration** | Native (domain-based) | NFS volume in Finder sidebar | Custom volume in Finder |
| **Installation** | Built into app bundle | Homebrew cask or pkg installer | Pkg installer + kext approval |
| **Sandboxing** | ✅ Fully sandboxed | ❌ Requires unsandboxed helper | ❌ Unsandboxed |
| **On-demand hydration** | ✅ Native support | ❌ Must implement manually | ❌ Must implement manually |
| **Write support** | ✅ Via item upload | ✅ Full POSIX write semantics | ✅ Full POSIX write semantics |
| **Rename across dirs** | Translatable to MTP move | POSIX rename → must emulate | POSIX rename → must emulate |
| **Performance overhead** | Low (XPC + direct I/O) | Medium (NFS loopback + userspace) | Low (kernel bridge) |
| **Stars / activity** | Apple first-party | ~1,350 GitHub stars, active | ~2,500 stars, closed-source kext |
| **License** | Apple (proprietary API) | fuse-t: custom/unclear; libfuse: GPL-2.0 | Closed-source kext; libfuse: BSD-ish |

### Verdict

- **FileProvider** remains the primary integration for App Store distribution, sandboxed apps, and native Finder experience.
- **FUSE-T** is the best option for power-user / CLI / Homebrew distribution where full POSIX semantics are needed.
- **macFUSE** is not recommended: closed-source kext, increasingly restricted by Apple, and unstable under load.

---

## 2. FUSE-T Architecture

### How FUSE-T Works

```
┌─────────────────────────────────────────────────────────────┐
│  macOS Finder / Terminal / Any App                          │
│  (reads/writes to /Volumes/MTPDevice)                       │
└──────────────────────┬──────────────────────────────────────┘
                       │  NFS v4 client (built into macOS)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  FUSE-T NFS v4 Server (userspace, localhost TCP)            │
│  Converts NFS RPCs → FUSE protocol requests                 │
└──────────────────────┬──────────────────────────────────────┘
                       │  FUSE protocol (in-process callbacks)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  libfuse-t (C library, links into our process)              │
│  FUSE high-level or low-level API callbacks                 │
└──────────────────────┬──────────────────────────────────────┘
                       │  Swift ↔ C bridge
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  SwiftMTPFUSE (new module)                                  │
│  Translates FUSE ops → MTPDevice protocol calls             │
│  - readdir  → GetObjectHandles + GetObjectInfo              │
│  - read     → GetPartialObject / GetObject                  │
│  - write    → SendObjectInfo + SendObject                   │
│  - mkdir    → SendObjectInfo (OFC_Association)              │
│  - unlink   → DeleteObject                                  │
│  - rename   → SetObjectPropValue (same dir only) or         │
│               copy+delete (cross-directory)                  │
│  - statfs   → GetStorageInfo                                │
└──────────────────────┬──────────────────────────────────────┘
                       │  async/await via MTPDeviceActor
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  SwiftMTPCore → MTPDeviceActor → USB Transport              │
└─────────────────────────────────────────────────────────────┘
```

### Proposed SwiftMTP Integration Architecture

```
SwiftMTPKit/
├── Sources/
│   ├── SwiftMTPFUSE/              # NEW: FUSE filesystem module
│   │   ├── MTPFUSEFileSystem.swift    # FUSE ops → MTP translation
│   │   ├── MTPFUSEBridge.swift        # C ↔ Swift callback bridge
│   │   ├── FUSENodeCache.swift        # In-memory inode cache
│   │   ├── FUSEWriteBuffer.swift      # Write buffering for MTP
│   │   └── FUSEMountManager.swift     # Mount/unmount lifecycle
│   └── Tools/
│       └── swiftmtp-cli/
│           └── MountCommand.swift     # `swiftmtp mount` subcommand
```

---

## 3. go-mtpfs Architecture Analysis

[go-mtpfs](https://github.com/hanwen/go-mtpfs) is the most mature open-source MTP-over-FUSE implementation. Key architectural decisions:

### MTP → FUSE Operation Mapping

| FUSE Operation | MTP Operation | go-mtpfs Approach |
|---|---|---|
| `readdir` | `GetObjectHandles` + `GetObjectInfo` | Lazy fetch on first access, cached in `folderNode.fetched` flag |
| `lookup` | Cached from `readdir` | Triggers `fetch()` if not yet loaded |
| `read` | `GetObject` / `GetPartialObject` | Backing file on disk; Android mode uses edit-in-place |
| `write` / `create` | `SendObjectInfo` + `SendObject` | Android: create empty object then edit; Classic: buffer to backing dir |
| `mkdir` | `SendObjectInfo` (OFC_Association) | Direct MTP call |
| `unlink` / `rmdir` | `DeleteObject` | Direct MTP call; rmdir checks for empty |
| `rename` | `SetObjectPropValue` (OPC_ObjectFileName) | **Same directory only**; cross-directory returns `ENOSYS` |
| `statfs` | `GetStorageInfo` | Aggregates across all storages |
| `getattr` | Cached `ObjectInfo` | Returns cached size, timestamps, mode (0644/0755) |
| `setattr` | N/A (MTP limitation) | Modification time stored in memory only, not persisted |

### Key Design Decisions in go-mtpfs

1. **Single-threaded requirement**: go-mtpfs must be mounted as `SingleThread` because MTP devices are inherently single-channel — only one USB transaction at a time. This is critical for SwiftMTP where `MTPDeviceActor` already serializes access.

2. **Lazy directory loading**: Directories are fetched from the device on first access and cached. The `fetched` flag prevents re-fetching. This maps well to SwiftMTP's `SQLiteLiveIndex`.

3. **No cross-directory rename**: MTP has no "move object" operation. go-mtpfs returns `ENOSYS` for cross-directory renames. Applications (and Finder) must fall back to copy+delete.

4. **Android vs. Classic modes**: Android devices support `SendObject` followed by in-place edits via `GetPartialObject`/`SendPartialObject`. Classic PTP/MTP devices require buffering the entire file to a backing directory before sending.

5. **VFAT filename sanitization**: Removable storage on Android uses VFAT, which forbids characters like `:*?"<>|`. go-mtpfs sanitizes these to underscores.

6. **Large file handling**: Files with `CompressedSize == 0xFFFFFFFF` require a separate `GetObjectPropValue(OPC_ObjectSize)` call to get the 64-bit size. SwiftMTP already handles this.

### Applicability to SwiftMTP

- SwiftMTP's actor-based design already provides the single-threaded serialization that go-mtpfs achieves via `SingleThread` mount.
- The `SQLiteLiveIndex` can serve as the directory cache, replacing go-mtpfs's in-memory `fetched` flag pattern.
- SwiftMTP's quirks system can inform whether to use Android-style or classic-style write paths per device.
- SwiftMTP's `TransferJournal` provides resume capability that go-mtpfs lacks entirely.

---

## 4. Swift FUSE Bindings

### Current State of Swift + FUSE

There is no widely-adopted, maintained Swift package for FUSE. Options:

| Approach | Effort | Maintenance Risk |
|---|---|---|
| **C interop with libfuse-t** | Medium — write Swift wrappers around `fuse_operations` struct callbacks | Low — libfuse-t is a stable C API |
| **Use fuse-t.framework** | Low — experimental framework for embedding in apps | Medium — marked experimental by FUSE-T project |
| **Write NFS v4 server directly** | Very High — bypass FUSE entirely, implement NFSv4 | High — complex protocol, poor ROI |
| **SwiftNIO-based approach** | High — custom NFS server on SwiftNIO | Medium — proven framework but significant work |

### Recommended Approach: C Interop with libfuse-t

```swift
// Conceptual bridge pattern — NOT production code
import CFUSEt  // C module map for libfuse-t headers

final class MTPFUSEBridge {
    /// Registered FUSE operations pointing to C callback trampolines
    static var operations: fuse_operations = {
        var ops = fuse_operations()
        ops.readdir  = mtp_fuse_readdir   // C function
        ops.getattr  = mtp_fuse_getattr
        ops.open     = mtp_fuse_open
        ops.read     = mtp_fuse_read
        ops.write    = mtp_fuse_write
        ops.mkdir    = mtp_fuse_mkdir
        ops.unlink   = mtp_fuse_unlink
        ops.rename   = mtp_fuse_rename
        ops.statfs   = mtp_fuse_statfs
        ops.release  = mtp_fuse_release
        return ops
    }()
}

// C trampoline calls back into Swift actor
func mtp_fuse_readdir(
    path: UnsafePointer<CChar>?,
    buf: UnsafeMutableRawPointer?,
    filler: fuse_fill_dir_t?,
    offset: off_t,
    fi: UnsafeMutablePointer<fuse_file_info>?
) -> Int32 {
    // Bridge to Swift async context via blocking semaphore
    // (FUSE callbacks are synchronous)
    let result = blockingAwait {
        await MTPFUSEFileSystem.shared.readdir(path: String(cString: path!))
    }
    // Fill buffer with results...
    return 0
}
```

**Key challenge**: FUSE callbacks are synchronous C functions, but SwiftMTP uses async/await. The bridge must use a blocking mechanism (e.g., semaphore or `DispatchSemaphore`) to wait for actor-isolated async calls. This is acceptable because FUSE-T is single-threaded per mount and the bridge runs on FUSE-T's dedicated thread pool.

---

## 5. Licensing Analysis

### SwiftMTP License
- **AGPL-3.0** (GNU Affero General Public License v3.0)

### FUSE-T Licensing

| Component | License | Compatibility with AGPL-3.0 |
|---|---|---|
| **fuse-t** (NFS server runtime) | Custom / unclear (GitHub reports "NOASSERTION") | ⚠️ **Risk** — license terms unclear; runtime is a separate process (NFS server) so likely not a derivative work |
| **libfuse-t** (C library we'd link against) | **GPL-2.0** (inherited from osxfuse/fuse fork) | ✅ **Compatible** — GPL-2.0 code can be combined with AGPL-3.0; combined work distributed under AGPL-3.0 |
| **macFUSE kext** | Closed-source / proprietary | ❌ **Incompatible** — cannot distribute combined work |
| **go-mtpfs** (reference, not used) | BSD-style | ✅ **Compatible** |

### Licensing Verdict

- Linking against `libfuse-t.dylib` (GPL-2.0) is compatible with SwiftMTP's AGPL-3.0.
- The FUSE-T NFS server runs as a **separate process** launched by libfuse-t at mount time. It communicates over TCP localhost. This is generally not considered "linking" under GPL/AGPL, so its unclear license is lower risk. However, we should:
  1. Request explicit license clarification from the FUSE-T maintainer.
  2. Document FUSE-T as an **optional runtime dependency** (not bundled).
  3. Users install FUSE-T separately via Homebrew (`brew install macos-fuse-t/homebrew-cask/fuse-t`).
- **Do not bundle** the FUSE-T runtime or NFS server binary in SwiftMTP distributions until licensing is clarified.

---

## 6. Performance Expectations

### FUSE-T Overhead Model

```
App I/O → macOS NFS client → TCP localhost → FUSE-T NFS server
       → libfuse-t → SwiftMTPFUSE → MTPDeviceActor → USB

Extra hops vs. direct I/O:
  - NFS client/server: ~50–200µs per operation (localhost TCP)
  - FUSE protocol translation: ~10–50µs per operation
  - Context switches: 2–4 additional per I/O operation
```

### Estimated Throughput Comparison

| Scenario | Direct SwiftMTP | FileProvider | FUSE-T |
|---|---|---|---|
| Small file read (4KB) | ~2ms | ~5ms (XPC overhead) | ~5–8ms (NFS + FUSE overhead) |
| Large file read (100MB) | ~8s (USB-limited) | ~8.5s | ~8.5–9s |
| Directory listing (1000 items) | ~200ms | ~250ms | ~300–400ms |
| Small file write (4KB) | ~5ms | ~10ms | ~10–15ms |
| Large file write (100MB) | ~12s (USB-limited) | ~12.5s | ~13–14s |

### Analysis

1. **Large transfers are USB-bound**: For files >1MB, the USB transfer dominates. FUSE-T's NFS overhead is negligible (<5%). This is the primary use case for MTP.

2. **Small file / metadata operations are costlier**: Each NFS RPC adds ~100–200µs of latency. For workloads with many small files (e.g., photo import of thousands of thumbnails), this compounds. Mitigation: aggressive attribute caching (FUSE-T defers to macOS NFS client caching, which is effective).

3. **Read/write buffer size matters**: FUSE-T supports configurable `rwsize` (default 32KB, max 64KB). For MTP transfers, we'd want to buffer internally and use SwiftMTP's auto-tuning chunk sizes (512KB–8MB) rather than relying on NFS-level buffering.

4. **FUSE-T claims better performance than macFUSE**: The FUSE-T README states "FUSE-T offers much better performance" due to macOS's optimized NFSv4 client implementation. NFS client-side caching of attributes and read-ahead is handled by the kernel.

### FileProvider vs FUSE-T Performance Trade-offs

| Aspect | FileProvider | FUSE-T |
|---|---|---|
| First access latency | Higher (domain enumeration) | Lower (lazy per-directory) |
| Sustained throughput | Good (direct XPC) | Good (NFS buffering) |
| Metadata caching | Framework-managed | macOS NFS client cache |
| Write buffering | Upload-based (staged) | POSIX write semantics |
| Concurrent access | Supported | Single-threaded (MTP limit) |

---

## 7. MTP-Specific Challenges for FUSE

### Challenge 1: No Random Write Access
MTP `SendObject` requires sending the entire file. POSIX `write()` at arbitrary offsets is not directly supported.

**Mitigation**: Buffer writes to a temporary file. On `release()` (file close), send the complete file to the device. This is how go-mtpfs handles it (backing directory).

### Challenge 2: No Cross-Directory Rename
MTP has no "move object to different parent" operation.

**Mitigation options**:
1. Return `ENOSYS` for cross-directory rename (go-mtpfs approach). Finder falls back to copy+delete.
2. Implement as copy+delete in SwiftMTPFUSE (transparent to user, but slower and non-atomic).
3. Use MTP's `MoveObject` operation where supported (Android extension, not universal).

**Recommendation**: Option 2 with quirks-based opt-in for `MoveObject` where available.

### Challenge 3: Object Handle Stability
MTP object handles may change after device operations. FUSE inodes must remain stable.

**Mitigation**: Use SwiftMTP's `SQLiteLiveIndex` as the authoritative inode-to-handle mapping. Refresh on cache miss.

### Challenge 4: Concurrent Access Serialization
FUSE may dispatch multiple operations concurrently, but MTP is single-channel.

**Mitigation**: `MTPDeviceActor` already serializes all device access. FUSE operations queue through the actor. Mount with FUSE-T's single-thread option for safety.

### Challenge 5: Async/Sync Bridge
FUSE callbacks are synchronous C functions. SwiftMTP is async/await.

**Mitigation**: Use `DispatchSemaphore` to block the FUSE thread while awaiting the actor. This is safe because FUSE-T uses its own thread pool, not the Swift cooperative pool.

---

## 8. Implementation Roadmap (If Approved)

### Phase 1: Read-Only Mount (2–3 weeks)
- Create `SwiftMTPFUSE` module with C interop bridge
- Implement: `readdir`, `getattr`, `lookup`, `open`, `read`, `statfs`
- Add `swiftmtp mount <path>` CLI command
- Test with VirtualMTPDevice
- Gate behind `--experimental-fuse` flag

### Phase 2: Write Support (2–3 weeks)
- Implement: `create`, `write`, `release`, `mkdir`, `unlink`, `rmdir`
- Write buffering via temporary files
- Same-directory rename via `SetObjectPropValue`
- Cross-directory rename via copy+delete

### Phase 3: Polish and Quirks Integration (1–2 weeks)
- Per-device FUSE mount options from quirks database
- VFAT filename sanitization for removable storage
- Graceful handling of device disconnect during mount
- Integration with `TransferJournal` for write reliability
- Documentation and user guide

### Phase 4: Testing and Hardening (1–2 weeks)
- Fuzz testing of FUSE callbacks
- Stress testing with concurrent Finder access
- Real device validation (Xiaomi Mi Note 2, OnePlus 3T)
- Performance benchmarking vs FileProvider

**Total estimated effort**: 6–10 weeks

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| FUSE-T license unclear for runtime | Medium | Treat as optional external dependency; users install separately |
| FUSE-T project abandoned | Low | Low coupling; could swap to macFUSE or direct NFS later |
| NFS permission issues on macOS | Medium | Requires "Network Volumes" privacy approval; document in setup |
| Async/sync bridge deadlocks | Medium | Dedicated thread pool; never block Swift cooperative pool |
| Finder misbehavior with NFS volume | Medium | Test extensively; provide `nobrowse` option for headless use |
| App Store rejection | N/A | FUSE-T path is CLI/Homebrew only; FileProvider for App Store |
| MTP device disconnect during mount | High | Implement FUSE `destroy` callback; clean unmount on disconnect |

---

## 10. Recommendation

**Pursue FUSE-T integration as a secondary, opt-in mount strategy.**

### Rationale

1. **Complementary, not competing**: FileProvider serves App Store and sandboxed GUI users. FUSE-T serves power users, CLI workflows, and automation scripts that need POSIX filesystem semantics.

2. **Low risk**: FUSE-T is an optional dependency. Users install it separately. SwiftMTP's core architecture is unaffected.

3. **Proven pattern**: go-mtpfs demonstrates that MTP-over-FUSE works well in practice, with known limitations that are acceptable for the use case.

4. **Reuse existing infrastructure**: SwiftMTP's `MTPDeviceActor`, `SQLiteLiveIndex`, `TransferJournal`, and quirks system provide all the building blocks. The FUSE module is primarily a thin translation layer.

5. **CLI user experience**: `swiftmtp mount /Volumes/MyPhone` is a compelling UX for terminal users. Combined with `swiftmtp events` for hot-plug, this enables scripted workflows.

### What NOT to do
- Do not replace FileProvider with FUSE-T.
- Do not bundle FUSE-T runtime in SwiftMTP.
- Do not require FUSE-T for any core functionality.
- Do not implement FUSE support before FileProvider is validated on real devices.

---

## References

- [FUSE-T project](https://github.com/macos-fuse-t/fuse-t) — kext-less FUSE for macOS
- [FUSE-T libfuse](https://github.com/macos-fuse-t/libfuse) — GPL-2.0 C library
- [FUSE-T wiki](https://github.com/macos-fuse-t/fuse-t/wiki) — developer guide
- [macFUSE](https://github.com/osxfuse/osxfuse) — kext-based FUSE (not recommended)
- [go-mtpfs](https://github.com/hanwen/go-mtpfs) — reference MTP-over-FUSE implementation
- [Apple FileProvider](https://developer.apple.com/documentation/fileprovider) — native macOS file system integration
- [SwiftMTP FileProvider Tech Preview](FileProvider-TechPreview.md) — existing FileProvider integration
