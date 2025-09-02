# Notarization & Distribution

## Sandboxed macOS App Setup

For a sandboxed demo app:

1. **Enable App Sandbox** in Xcode project settings
2. **Add USB entitlement**: `com.apple.security.device.usb = true`
3. **Sign with Developer ID** certificate
4. **Archive + Notarize** via Organizer

## Library Distribution

The SwiftMTP library needs no special entitlements; the app's sandbox governs USB access.

## Release Process

1. Build XCFramework: `./scripts/build-libusb-xcframework.sh`
2. Prepare release: `./scripts/prepare-release.sh`
3. Tag and push: `git tag v1.0.0 && git push --tags`
4. CI generates SBOM and creates GitHub release
