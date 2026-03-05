# Canon EOS & Nikon PTP Camera Quirks Research

> **Status**: Research only — no real cameras tested with SwiftMTP  
> **Date**: 2025-07-24  
> **Sources**: libgphoto2/camlibs/ptp2, libmtp/src, PTP/MTP specifications (ISO 15740)

---

## 1. PTP vs MTP: Key Differences for Cameras

PTP (Picture Transfer Protocol, ISO 15740) predates MTP and is the native protocol for digital cameras. MTP is Microsoft's extension of PTP for media devices. Cameras primarily speak PTP but may advertise MTP compatibility.

### USB Interface Class

All PTP/MTP cameras and devices use:
- **Class**: `0x06` (Still Image / Imaging)  
- **Subclass**: `0x01`  
- **Protocol**: `0x01`  

This is identical to the MTP interface class used by Android phones — SwiftMTP's existing interface probe logic already matches cameras.

### Vendor Extension IDs (from PTP DeviceInfo)

| Vendor | Extension ID | Extension String |
|--------|-------------|------------------|
| Canon  | `0x0000000B` | `"microsoft.com/MTP: 1.0; canon.com: 1.0"` |
| Nikon  | `0x0000000A` | `"microsoft.com/MTP: 1.0; nikon.com: 1.0"` |
| Microsoft (MTP) | `0x00000006` | `"microsoft.com/MTP: 1.0"` |

**Important**: Newer Canon and Nikon cameras may report `VendorExtensionID = 0x00000006` (Microsoft/MTP) even though they support vendor-specific PTP extensions. libgphoto2 handles this by checking the manufacturer string and overriding the extension ID. SwiftMTP should do the same.

---

## 2. Canon EOS PTP Extensions

### Vendor Extension Operations (from libgphoto2 ptp.h)

Canon EOS cameras use two sets of vendor operations:

#### Classic Canon Operations (`0x9001`–`0x903F`)
| Code | Name | Purpose |
|------|------|---------|
| `0x9001` | `GetPartialObjectInfo` | Get partial object metadata |
| `0x9002` | `SetObjectArchive` | Set archive flag |
| `0x9003` | `KeepDeviceOn` | Prevent camera auto-sleep |
| `0x9004` | `LockDeviceUI` | Lock camera UI for remote control |
| `0x9005` | `UnlockDeviceUI` | Unlock camera UI |
| `0x9008` | `InitiateReleaseControl` | Begin remote shooting mode |
| `0x9009` | `TerminateReleaseControl` | End remote shooting mode |
| `0x900B` | `ViewfinderOn` | Start optical viewfinder streaming |
| `0x900C` | `ViewfinderOff` | Stop optical viewfinder streaming |
| `0x900D` | `DoAeAfAwb` | Trigger AE/AF/AWB cycle |
| `0x9013` | `CheckEvent` | Poll for pending events |
| `0x9014` | `FocusLock` | Lock focus |
| `0x9015` | `FocusUnlock` | Unlock focus |

#### EOS-Specific Operations (`0x9101`–`0x91FF`)
| Code | Name | Purpose |
|------|------|---------|
| `0x9101` | `EOS_GetStorageIDs` | Get storage IDs (EOS variant) |
| `0x9102` | `EOS_GetStorageInfo` | Get storage info (EOS variant) |
| `0x9103` | `EOS_GetObjectInfo` | Get object info (EOS variant) |
| `0x9104` | `EOS_GetObject` | Download object (EOS variant) |
| `0x9105` | `EOS_DeleteObject` | Delete object |
| `0x9107` | `EOS_GetPartialObject` | Download partial object |
| `0x9108` | `EOS_GetDeviceInfoEx` | Get extended device info |
| `0x910F` | `EOS_RemoteRelease` | Trigger shutter |
| `0x9110` | `EOS_SetDevicePropValueEx` | Set device property |
| `0x9116` | `EOS_GetEvent` | Poll events (critical for capture workflow) |
| `0x9117` | `EOS_TransferComplete` | Acknowledge transfer completion |
| `0x911D` | `EOS_KeepDeviceOn` | EOS keep-alive (prevents auto-off) |
| `0x9125` | `EOS_BulbStart` | Start bulb exposure |
| `0x9126` | `EOS_BulbEnd` | End bulb exposure |
| `0x9128` | `EOS_RemoteReleaseOn` | Shutter half/full press |
| `0x9129` | `EOS_RemoteReleaseOff` | Shutter release |
| `0x9151` | `EOS_InitiateViewfinder` | Start LiveView |
| `0x9152` | `EOS_TerminateViewfinder` | Stop LiveView |
| `0x9153` | `EOS_GetViewFinderData` | Get LiveView frame |
| `0x9154` | `EOS_DoAf` | Trigger autofocus |
| `0x9155` | `EOS_DriveLens` | Manual focus drive |
| `0x9158` | `EOS_Zoom` | Digital zoom |
| `0x9170` | `EOS_GetObjectInfo64` | 64-bit object info |
| `0x9171` | `EOS_GetObject64` | 64-bit object download |
| `0x9172` | `EOS_GetPartialObject64` | 64-bit partial download |

#### Canon EOS Events
| Code | Name |
|------|------|
| `0xC101` | `EOS_RequestGetEvent` |
| `0xC181` | `EOS_ObjectAddedEx` |
| `0xC182` | `EOS_ObjectRemoved` |
| `0xC189` | `EOS_PropValueChanged` |
| `0xC18B` | `EOS_CameraStatusChanged` |
| `0xC18D` | `EOS_WillSoonShutdown` |
| `0xC18E` | `EOS_ShutdownTimerUpdated` |
| `0xC1A7` | `EOS_ObjectAddedEx64` |

#### Canon Object Formats
| Code | Format |
|------|--------|
| `0xB101` | CRW (Canon Raw v1) |
| `0xB103` | CRW3 (Canon Raw v3) |
| `0xB104` | Canon MOV |
| `0xB108` | CR3 (Canon Raw v3, current) |

### Canon USB PIDs (VID `0x04A9`)

Key Canon EOS camera PIDs from libgphoto2:

| PID | Model | Notes |
|-----|-------|-------|
| `0x3099` | EOS 300D / Digital Rebel / Kiss Digital | First consumer EOS DSLR |
| `0x30EA` | EOS 1D Mark II | Pro body |
| `0x30EC` | EOS 20D | |
| `0x3110` | EOS 400D / Rebel XTi / Kiss Digital X | PTP_CAP |
| `0x3113` | EOS 30D | PTP_CAP |
| `0x3139` | PowerShot A640 | Note: same PID as SwiftMTP's "canon-eos-rebel-3139" — this is actually a PowerShot, not a Rebel |
| `0x3145` | EOS 450D / Rebel XSi / Kiss X2 | PTP_CAP, DELETE_SENDS_EVENT |
| `0x3146` | EOS 40D | PTP_CAP, DELETE_SENDS_EVENT |
| `0x317B` | EOS 1000D / Rebel XS | PTP_CAP, DELETE_SENDS_EVENT |
| `0x3215` | EOS 5D Mark II | PTP_CAP |
| `0x3217` | EOS 7D | PTP_CAP |
| `0x3218` | EOS 500D / Rebel T1i | PTP_CAP |
| `0x3259` | EOS 550D / Rebel T2i | PTP_CAP |
| `0x327F` | EOS 600D / Rebel T3i | PTP_CAP |
| `0x3281` | EOS 1100D / Rebel T3 | PTP_CAP |
| `0x32AF` | EOS Rebel T4i/650D | PTP_CAP |
| `0x32BB` | EOS Rebel T5i/700D | PTP_CAP |
| `0x346F` | EOS Rebel T6/1300D | PTP_CAP |
| `0x3471` | EOS Rebel T7i/800D | PTP_CAP |

### Canon-Specific Quirks

1. **DONT_CLOSE_SESSION** (from libgphoto2 device-flags.h):
   > "On 2016 EOS cameras, do not close the session on exiting, as the device will only report PTP errors afterwards."
   
   This affects newer EOS models and means `CloseSession` should be skipped on disconnect.

2. **DELETE_SENDS_EVENT**: Many Canon cameras send an `ObjectRemoved` event when a delete operation completes. The event pump must be active during delete operations.

3. **Start timeout**: libgphoto2 uses `USB_CANON_START_TIMEOUT = 1500ms` for Canon cameras (shorter than the general 8000ms), suggesting Canon cameras respond quickly to initial connection.

4. **KeepDeviceOn**: Canon cameras auto-sleep aggressively. The `KeepDeviceOn` command (`0x9003` for classic Canon, `0x911D` for EOS) must be sent periodically (every 30–60 seconds) to prevent auto-off during long transfers.

5. **Event polling**: Canon EOS cameras require active event polling via `EOS_GetEvent` (`0x9116`). Unlike MTP devices that push events on the interrupt endpoint, Canon cameras expect the host to poll.

6. **MTP GetObjectPropList broken**: libgphoto2 notes that MTP property lists on Canon cameras are often "2 times slower than regular data retrieval" or completely broken (return 0 entries). SwiftMTP should use standard PTP `GetObjectInfo` rather than MTP `GetObjectPropList` for Canon cameras.

7. **CR3 RAW files**: Modern Canon mirrorless cameras (EOS R series) use CR3 format (`0xB108`), which can be 20–50 MB. The `ioTimeoutMs` should be extended for large RAW transfers.

8. **Vendor extension override**: Newer Canons report `VendorExtensionID = 0x00000006` (MTP) but are actually Canon PTP devices. Check manufacturer string for "Canon" and override to `0x0000000B`.

---

## 3. Nikon PTP Extensions

### Vendor Extension Operations (from libgphoto2 ptp.h)

#### Core Nikon Operations (`0x90C0`–`0x90CF`)
| Code | Name | Purpose |
|------|------|---------|
| `0x90C0` | `InitiateCaptureRecInSdram` | Capture to camera RAM |
| `0x90C1` | `AfDrive` | Trigger autofocus |
| `0x90C2` | `ChangeCameraMode` | Switch camera mode |
| `0x90C3` | `DelImageSDRAM` | Delete image from RAM |
| `0x90C4` | `GetLargeThumb` | Get large thumbnail |
| `0x90C7` | `GetEvent` | Poll for events |
| `0x90C8` | `DeviceReady` | Check if camera is ready |
| `0x90CA` | `GetVendorPropCodes` | Get vendor property codes |
| `0x90CB` | `AfCaptureSDRAM` | AF + capture to RAM |

#### Nikon LiveView (`0x9200`–`0x9207`)
| Code | Name | Purpose |
|------|------|---------|
| `0x9200` | `GetPreviewImg` | Get preview image |
| `0x9201` | `StartLiveView` | Start LiveView |
| `0x9202` | `EndLiveView` | Stop LiveView |
| `0x9203` | `GetLiveViewImg` | Get LiveView frame |
| `0x9204` | `MfDrive` | Manual focus drive |
| `0x9205` | `ChangeAfArea` | Change AF area |
| `0x9206` | `AfDriveCancel` | Cancel AF drive |
| `0x9207` | `InitiateCaptureRecInMedia` | Capture to card |

#### Nikon Advanced Operations (`0x9400`–`0x9436`)
| Code | Name | Purpose |
|------|------|---------|
| `0x9400` | `GetPartialObjectHiSpeed` | High-speed partial download |
| `0x9414` | `GetSBHandles` | Speedlight handles |
| `0x941C` | `GetEventEx` | Extended event query |
| `0x9421` | `GetObjectSize` | 64-bit object size |
| `0x9428` | `GetLiveViewImageEx` | Extended LiveView |
| `0x9431` | `GetPartialObjectEx` | 64-bit partial download |
| `0x9434` | `GetObjectsMetaData` | Batch metadata retrieval |

#### Nikon Events
| Code | Name |
|------|------|
| `0xC101` | `ObjectAddedInSDRAM` |
| `0xC102` | `CaptureCompleteRecInSdram` |
| `0xC104` | `PreviewImageAdded` |
| `0xC105` | `MovieRecordInterrupted` |
| `0xC108` | `MovieRecordComplete` |
| `0xC10A` | `MovieRecordStarted` |
| `0xC10C` | `LiveViewStateChanged` |

#### Nikon-Specific Response Codes
| Code | Name |
|------|------|
| `0xA001` | `HardwareError` |
| `0xA002` | `OutOfFocus` |
| `0xA004` | `InvalidStatus` |
| `0xA00B` | `NotLiveView` |
| `0xA200` | `Bulb_Release_Busy` |
| `0xA201` | `Silent_Release_Busy` |

### Nikon USB PIDs (VID `0x04B0`)

Key Nikon DSLR/mirrorless PIDs from libgphoto2:

| PID | Model | Flags |
|-----|-------|-------|
| `0x0402` | D100 | — |
| `0x0406` | D70 | PTP_CAP |
| `0x0410` | D200 | PTP_CAP |
| `0x0412` | D80 | PTP_CAP |
| `0x041A` | D300 | PTP_CAP |
| `0x0421` | D90 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0428` | D7000 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x042A` | D800 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0430` | D7100 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0436` | D810 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0439` | D7200 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x043C` | D500 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0440` | D7500 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0441` | D850 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0442` | Z7 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0443` | Z6 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0444` | Z50 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0448` | Z5 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x044B` | Z7 II | PTP_CAP, PTP_CAP_PREVIEW |
| `0x044C` | Z6 II | PTP_CAP, PTP_CAP_PREVIEW |
| `0x044F` | Zfc | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0450` | Z9 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0451` | Z8 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0452` | Z30 | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0453` | Zf | PTP_CAP, PTP_CAP_PREVIEW |
| `0x0454` | Z6 III | PTP_CAP, PTP_CAP_PREVIEW |

### Nikon-Specific Quirks

1. **DeviceReady polling** (`0x90C8`): Nikon cameras require polling `DeviceReady` before operations. The camera returns `DeviceBusy` (`0x2019`) or `Bulb_Release_Busy` (`0xA200`) while processing. libgphoto2 implements a `nikon_wait_busy()` loop with 50ms increments up to 200ms max sleep.

2. **Hidden vendor operations**: Many Nikon DSLRs (especially D3000-series, D5000-series) hide their vendor operation codes. libgphoto2 manually injects known-good operation codes based on model detection. The `GetVendorPropCodes` (`0x90CA`) command can crash some Nikon 1 series cameras (V1, J1, J2).

3. **NIKON_BROKEN_CAPTURE**: Coolpix cameras have broken capture support that doesn't properly fire `ObjectAdded` events. This flag is used extensively for Coolpix models but not for DSLR/Z-series.

4. **64-bit object sizes**: Nikon `GetObjectSize` (`0x9421`) returns 64-bit file sizes, needed for large video files (4K video can exceed 4 GB). `GetPartialObjectEx` (`0x9431`) also uses 64-bit offsets.

5. **Nikon 1 series**: Mirrorless Nikon 1 (V1, J1-J5, S1-S2) cameras have the `PTP_NIKON_1` flag and behave differently from DSLRs. Some operations crash the protocol flow on older models.

6. **Camera mode switching**: Nikon cameras may need `ChangeCameraMode` (`0x90C2`) called to switch from playback to capture mode before remote shooting works.

7. **PTP/IP support**: Nikon cameras support PTP over IP (WiFi) via `GetDevicePTPIPInfo` (`0x90E0`). This is relevant for future wireless transfer support.

8. **GetEventEx**: Newer Nikons support `GetEventEx` (`0x941C`) which can return multi-parameter events, compared to the basic `GetEvent` (`0x90C7`).

---

## 4. Common Camera Quirks (Both Canon & Nikon)

### Session Handling

1. **Single session**: PTP cameras typically support only one active session. Opening a second session will fail with `SessionAlreadyOpened` (`0x201E`).

2. **Kernel driver detach**: On macOS, the built-in `ImageCaptureCore` framework may claim the USB interface. `requiresKernelDetach: true` is essential for cameras.

3. **No writes**: Most cameras are read-only from the MTP/PTP perspective. `SendObject` operations are not supported (or limited to specific folders). `disableWriteResume: true` should be set.

4. **No MTP property lists**: Both Canon and Nikon cameras have unreliable or slow `GetObjectPropList` (`0x9805`) implementations. Use standard PTP `GetObjectInfo` (`0x1008`) instead.

### Timeout Requirements

| Parameter | Recommended Value | Reason |
|-----------|------------------|--------|
| `handshakeTimeoutMs` | 8000 | Cameras may take several seconds to respond after USB attach |
| `ioTimeoutMs` | 30000 | Large RAW files (20-50 MB) need extended transfer time |
| `inactivityTimeoutMs` | 15000 | Camera processing (e.g., after capture) can stall I/O |
| `overallDeadlineMs` | 180000 | Full card download can take minutes |
| `stabilizeMs` | 200-300 | Post-session-open delay for camera initialization |
| `eventPumpDelayMs` | 50-100 | Event polling interval (Canon: 50ms, Nikon: 100ms) |

### Keep-Alive

Cameras auto-sleep aggressively (typically 30-120 seconds). SwiftMTP must:
- Send Canon `KeepDeviceOn` (`0x9003`/`0x911D`) periodically
- Poll Nikon `DeviceReady` (`0x90C8`) which also serves as a keep-alive
- Consider adding a `keepAliveIntervalMs` tuning parameter

### Storage Layout

Cameras use DCF (Design rule for Camera File system) storage:
```
DCIM/
  100CANON/   (or 100NIKON, 100EOS__, etc.)
    IMG_0001.JPG
    IMG_0001.CR3  (RAW sidecar)
  101CANON/
    ...
```

Storage type is typically `RemovableRAM` (`0x0004`) for SD/CF cards.

---

## 5. Recommended QuirkFlags for Camera Support

### Existing Flags (already in SwiftMTP)
- `requiresKernelDetach: true` — Essential for cameras
- `resetOnOpen: false` — Don't reset cameras on connect
- `cameraClass: true` — Mark as PTP camera (not MTP device)
- `supportsGetObjectPropList: false` — Canon/Nikon MTP proplists are broken
- `supportsGetPartialObject: true` — PTP GetPartialObject works on cameras

### Proposed New Flags for Camera Support
- `ptpVendor: "canon"` or `"nikon"` — Enable vendor-specific operation dispatch
- `dontCloseSession: true` — For 2016+ Canon EOS cameras
- `deleteSendsEvent: true` — For Canon cameras that fire events on delete
- `requiresDeviceReadyPoll: true` — For Nikon cameras needing busy-wait
- `keepAliveIntervalMs: 30000` — Auto keep-alive interval
- `vendorExtensionOverride: 0x0B` — Override MTP vendor ID to Canon

---

## 6. Current quirks.json Entry Issues

### canon-eos-rebel-3139

The existing entry uses PID `0x3139`, which in libgphoto2 maps to the **Canon PowerShot A640**, not an EOS Rebel camera. This PID was likely chosen as a placeholder. Real EOS Rebel PIDs include:
- `0x3145` — EOS 450D / Rebel XSi
- `0x317B` — EOS 1000D / Rebel XS
- `0x3218` — EOS 500D / Rebel T1i

The entry should be updated with a note that it's a generic Canon EOS profile, not specific to any single PID.

### nikon-dslr-0410

The existing entry uses PID `0x0410`, which correctly maps to the **Nikon D200** in libgphoto2. However, this PID is only for one specific model. The Nikon Z-series uses different PIDs (`0x0442`–`0x0454`).

---

## 7. libmtp Device Flags Reference

Key libmtp device flags relevant to cameras (from `device-flags.h`):

| Flag | Value | Description |
|------|-------|-------------|
| `DEVICE_FLAG_NONE` | `0x00000000` | No special handling |
| `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL` | `0x00000001` | GetObjectPropList broken for all objects |
| `DEVICE_FLAG_UNLOAD_DRIVER` | `0x00000002` | Need to detach kernel driver |
| `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST` | `0x00000004` | GetObjectPropList broken |
| `DEVICE_FLAG_LONG_TIMEOUT` | `0x08000000` | Needs extended timeouts |
| `DEVICE_FLAG_DONT_CLOSE_SESSION` | `0x20000000` | Don't close session (2016+ Canon EOS) |
| `DEVICE_FLAG_DELETE_SENDS_EVENT` | `0x00020000` | Object delete sends event |
| `DEVICE_FLAG_CAPTURE` | `0x00040000` | Camera can capture |
| `DEVICE_FLAG_CAPTURE_PREVIEW` | `0x00080000` | Camera can capture preview/LiveView |
| `DEVICE_FLAG_NIKON_BROKEN_CAPTURE` | `0x00100000` | Nikon broken capture (no ObjectAdded events) |
| `DEVICE_FLAG_NIKON_1` | `0x00200000` | Nikon 1 series (different behavior) |
| `DEVICE_FLAG_NO_CAPTURE_COMPLETE` | `0x00400000` | No CaptureComplete event |

---

## 8. libgphoto2 Timeout Constants

From `library.c`:
```c
#define USB_START_TIMEOUT       8000     // General start timeout
#define USB_CANON_START_TIMEOUT 1500     // Canon-specific (faster)
#define USB_NORMAL_TIMEOUT      20000    // Normal I/O timeout
#define USB_TIMEOUT_CAPTURE     100000   // Capture operation timeout
```

---

## 9. PTP/IP (WiFi) Considerations

Both Canon and Nikon support PTP over IP for wireless transfers:

- **Canon**: Uses proprietary discovery + PTP/IP. Canon's WiFi implementation includes pairing (`SetPairingInfo` `0x9030`), MAC address retrieval (`GetMACAddress` `0x9033`), and web service operations (`0x9068`–`0x906F`).

- **Nikon**: Uses `GetDevicePTPIPInfo` (`0x90E0`) for PTP/IP configuration. Standard PTP/IP packet types (init command request/ack, data packets) apply.

PTP/IP uses TCP with a specific packet structure:
- Init Command Request (type 1)
- Init Command Ack (type 2)  
- Init Event Request (type 3)
- Init Event Ack (type 4)
- Command Request (type 6)
- Command Response (type 7)
- Event (type 8)
- Start Data Packet (type 9)
- Data Packet (type 10)
- End Data Packet (type 12)

---

## 10. Recommendations for SwiftMTP Implementation

### Phase 1: Read-Only Camera Support
1. Detect PTP cameras by interface class `06/01/01` and manufacturer string
2. Override vendor extension ID when manufacturer is "Canon" or "Nikon"
3. Use standard PTP operations (`GetObjectInfo`, `GetObject`, `GetPartialObject`) — avoid MTP property lists
4. Implement keep-alive timer (Canon `KeepDeviceOn`, Nikon `DeviceReady`)
5. Handle `DeviceBusy` responses with exponential backoff

### Phase 2: LiveView/Capture
1. Implement Canon EOS event polling loop (`EOS_GetEvent`)
2. Implement Nikon `DeviceReady` polling
3. Add LiveView support (Canon: `0x9151`/`0x9153`, Nikon: `0x9201`/`0x9203`)
4. Add remote capture (Canon: `0x910F`, Nikon: `0x90C0`/`0x9207`)

### Phase 3: Wireless Transfer
1. Implement PTP/IP transport layer
2. Add Canon WiFi pairing
3. Add Nikon PTP/IP discovery
