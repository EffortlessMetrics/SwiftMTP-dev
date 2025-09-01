import OSLog
public enum MTPLog {
  public static let subsystem = "com.effortlessmetrics.swiftmtp"
  public static let transport = Logger(subsystem: subsystem, category: "transport")
  public static let proto     = Logger(subsystem: subsystem, category: "protocol")
  public static let index     = Logger(subsystem: subsystem, category: "index")
  public static let sync      = Logger(subsystem: subsystem, category: "sync")
}
