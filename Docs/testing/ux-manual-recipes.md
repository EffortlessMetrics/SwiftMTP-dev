# UX Manual Recipes

Use these recipes for interactions that are tracked in the map but not hard-gated in PR automation.

## Files Empty Phase

1. Launch the app in deterministic UI test mode with a profile that returns an empty root listing.
2. Select the first discovered device.
3. Trigger `Refresh Files`.
4. Verify the empty-state copy appears and `swiftmtp.files.empty` is present.

## Discovery State Marker

1. Launch the app in deterministic UI test mode with `empty-state`, `mock-default`, and `error-discovery`.
2. For each scenario, inspect the accessibility tree for `swiftmtp.discovery.state`.
3. Verify the marker state resolves respectively to `empty`, `ready`, and `error`.

## Files Error Phase

1. Launch the app in deterministic UI test mode with a profile that returns a file-listing error.
2. Select the first discovered device.
3. Trigger `Refresh Files`.
4. Verify the error copy appears and `swiftmtp.files.error` is present.
5. Verify `ux-events.jsonl` contains `ux.files.refresh` with `result=failed`.

## File Row Render

1. Launch the app in deterministic UI test mode with a profile that returns at least one root file.
2. Select the first discovered device.
3. Trigger `Refresh Files` if needed.
4. Verify at least one element whose identifier begins with `swiftmtp.file.row.` is present.
