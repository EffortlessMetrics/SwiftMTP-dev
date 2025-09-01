import SwiftMTPCore
@main struct CLI {
  static func main() async {
    try? await MTPDeviceManager.shared.startDiscovery()
    print("SwiftMTP CLI (stub)")
  }
}
