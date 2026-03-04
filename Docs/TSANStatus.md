# Thread Sanitizer (TSAN) Status

> Last validated: 2025-07-25

## Current Status

| Environment | TSAN Status | Notes |
|---|---|---|
| macOS 15 + Xcode 16.2 (CI) | ✅ Works | Runs via direct binary execution to bypass DTX conflict |
| macOS 26 + Xcode 26.3 (local) | ❌ Blocked | Platform security policy rejects sanitizer runtime |

## macOS 26 Failure

TSAN **cannot run** on macOS 26 (Tahoe). The OS enforces a platform security
policy that rejects the Thread Sanitizer runtime library at load time:

```
Library not loaded: @rpath/libclang_rt.tsan_osx_dynamic.dylib
Reason: …/libclang_rt.tsan_osx_dynamic.dylib
  (code signature in <…> not valid for use in process:
   Sanitizer load violates platform policy)
```

The dylib exists on disk at:
```
/Applications/Xcode.app/Contents/Developer/Toolchains/
  XcodeDefault.xctoolchain/usr/lib/clang/17/lib/darwin/
  libclang_rt.tsan_osx_dynamic.dylib
```

### Workarounds Attempted (All Failed)

| Workaround | Result |
|---|---|
| `TSAN_OPTIONS="halt_on_error=0"` | Same error — runtime never loads |
| `DYLD_INSERT_LIBRARIES=…/libclang_rt.tsan_osx_dynamic.dylib` | Same error — policy blocks the dylib regardless of load method |
| Direct binary execution (CI approach) | Not attempted — build succeeds but binary cannot load sanitizer runtime |

This is a **platform-level restriction** in macOS 26 that cannot be bypassed
without disabling System Integrity Protection (SIP), which is not recommended.

### Root Cause

macOS 26 introduced stricter code-signature validation for sanitizer runtimes.
The `libclang_rt.tsan_osx_dynamic.dylib` shipped with Xcode 26.3 is present
but its code signature is rejected by the new platform policy. This affects all
sanitizers (`tsan`, `asan`, `ubsan`) loaded via `@rpath`.

Apple will likely resolve this in a future Xcode update that ships properly
signed sanitizer runtimes for macOS 26.

## CI Configuration

TSAN runs in CI via `.github/workflows/tsan-and-compat.yml` on **macOS 15**
runners:

- **Runner**: `macos-15`
- **Xcode**: 16.2
- **Swift**: 6.2
- **Test targets**: CoreTests, IndexTests, ScenarioTests
- **Method**: Direct binary execution (bypasses `swiftpm-xctest-helper` to
  avoid DTXConnectionServices conflict)
- **Policy**: `continue-on-error: true` (non-blocking, warns on DTX conflict)

### Why Direct Execution?

`swift test` spawns `swiftpm-xctest-helper` from Xcode's SIP-protected
toolchain directory. That helper loads `DTXConnectionServices`, which conflicts
with TSAN's interceptors and causes:

```
Interceptors are not working. This may be because
ThreadSanitizer is loaded too late (e.g. via dlopen).
```

The CI workflow builds with `swift build --build-tests -Xswiftc -sanitize=thread`,
then runs the compiled `.xctest` binary directly to ensure TSAN installs its
interceptors at load time.

## TSAN Test Targets

| Target | TSAN Scope | Rationale |
|---|---|---|
| CoreTests | ✅ Included | Actor isolation, protocol codec, device operations |
| IndexTests | ✅ Included | SQLite concurrency, live index |
| ScenarioTests | ✅ Included | End-to-end flows with async/await |
| TransportTests | ❌ Excluded | USB I/O is single-threaded at libusb level |
| All others | ❌ Not scoped | Not in TSAN CI matrix; may be added later |

## How to Run TSAN

### On macOS 15 (Recommended)

```bash
cd SwiftMTPKit

# Via swift test (may hit DTX conflict on some Xcode versions)
swift test -Xswiftc -sanitize=thread \
  --filter CoreTests --filter IndexTests --filter ScenarioTests

# Via direct execution (mirrors CI, avoids DTX conflict)
swift build --build-tests -Xswiftc -sanitize=thread
TEST_BIN=$(find .build -maxdepth 3 -name '*.xctest' -type d | head -1)
"$TEST_BIN/Contents/MacOS/$(basename "$TEST_BIN" .xctest)"
```

### On macOS 26

TSAN is **not available** on macOS 26 as of Xcode 26.3 (July 2025).
Compile-time concurrency checking (`-strict-concurrency=complete`) is the
recommended alternative for local development:

```bash
cd SwiftMTPKit
swift build -Xswiftc -strict-concurrency=complete
```

Swift 6's compile-time data isolation catches many of the same races TSAN
would find at runtime, particularly with the actor-based architecture used
throughout SwiftMTP.

## Known Limitations

1. **macOS 26 blocks all sanitizer runtimes** — not specific to TSAN; ASAN and
   UBSAN are also affected.
2. **DTXConnectionServices conflict** — on macOS 15, `swift test` may fail with
   TSAN even though the binary is correctly instrumented. Use direct execution.
3. **TransportTests excluded** — USB transport uses libusb's synchronous API
   which is inherently single-threaded; TSAN adds overhead without value.
4. **CI is non-blocking** — TSAN job uses `continue-on-error: true` to avoid
   blocking PRs on environment-specific runner issues.
