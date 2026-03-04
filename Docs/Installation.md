# Installation

## Homebrew (recommended)

```bash
brew tap EffortlessMetrics/swiftmtp https://github.com/EffortlessMetrics/SwiftMTP-dev.git
brew install swiftmtp
```

To install the latest development version from `main`:

```bash
brew install swiftmtp-head
```

### Prerequisites (installed automatically by Homebrew)

- **macOS** (Apple Silicon or Intel)
- **Xcode 16.0+** with Swift 6
- **libusb**

## From Source

```bash
git clone https://github.com/EffortlessMetrics/SwiftMTP-dev.git
cd SwiftMTP-dev/SwiftMTPKit
swift build -c release
# Binary at .build/release/swiftmtp
```

To install system-wide:

```bash
sudo cp .build/release/swiftmtp /usr/local/bin/
```

## Shell Completions

Homebrew installs completions automatically. For source builds, copy from the `completions/` directory:

```bash
# Bash
cp completions/swiftmtp.bash $(brew --prefix)/etc/bash_completion.d/swiftmtp

# Zsh
cp completions/_swiftmtp $(brew --prefix)/share/zsh/site-functions/

# Fish
cp completions/swiftmtp.fish ~/.config/fish/completions/
```

## Verify Installation

```bash
swiftmtp --help
swiftmtp probe    # Discover connected MTP devices
```

## Uninstall

```bash
brew uninstall swiftmtp
brew untap EffortlessMetrics/swiftmtp
```
