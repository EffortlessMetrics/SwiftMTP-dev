class Swiftmtp < Formula
  desc "Media Transfer Protocol CLI with device quirks + JSON tooling"
  homepage "https://github.com/your-org/SwiftMTP"
  version "1.0.0"

  if Hardware::CPU.arm?
    url "https://github.com/your-org/SwiftMTP/releases/download/v1.0.0/swiftmtp-macos-arm64.tar.gz"
    sha256 "c55cc13e56aa3330838f5588c9957cbf9c69e6645c49b3035e6e0ff0b81d1d1e"
  else
    odie "Intel macOS build not provided for v1.0.0"
  end

  def install
    bin.install "swiftmtp"
    # Optional: completions etc.
  end

  test do
    system "#{bin}/swiftmtp", "quirks", "--explain", "--json"
  end
end
