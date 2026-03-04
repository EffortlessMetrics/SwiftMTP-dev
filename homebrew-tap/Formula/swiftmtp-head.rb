class SwiftmtpHead < Formula
  desc "Swift-native MTP (Media Transfer Protocol) tool for macOS (HEAD)"
  homepage "https://github.com/EffortlessMetrics/SwiftMTP-dev"
  url "https://github.com/EffortlessMetrics/SwiftMTP-dev.git", branch: "main"
  version "0.0.0-head"
  license "AGPL-3.0"

  depends_on "libusb"
  depends_on xcode: ["16.0", :build]
  depends_on :macos

  def install
    cd "SwiftMTPKit" do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/swiftmtp"
    end

    bash_completion.install "completions/swiftmtp.bash" => "swiftmtp"
    zsh_completion.install "completions/_swiftmtp"
    fish_completion.install "completions/swiftmtp.fish"
  end

  test do
    assert_match "SwiftMTP", shell_output("#{bin}/swiftmtp --help")
  end
end
