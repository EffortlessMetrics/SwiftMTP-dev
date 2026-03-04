# Mock Device Profiles

SwiftMTP supports mock device profiles for development without physical hardware.

## Available Profiles

| Profile | Description | VID:PID |
|---------|-------------|---------|
| pixel7 | Google Pixel 7 | 18d1:4ee1 |
| galaxy | Samsung Galaxy | 04e8:6860 |
| iphone | iPhone (PTP) | 05ac:12a8 |
| canon | Canon EOS | 04a9:3139 |

## Usage

```bash
export SWIFTMTP_DEMO_MODE=1
export SWIFTMTP_MOCK_PROFILE=pixel7
swift run swiftmtp probe
```

## Failure Scenarios

| Scenario | Env Var |
|----------|---------|
| Timeout | SWIFTMTP_MOCK_FAILURE=timeout |
| Busy | SWIFTMTP_MOCK_FAILURE=busy |
| Disconnected | SWIFTMTP_MOCK_FAILURE=disconnected |
