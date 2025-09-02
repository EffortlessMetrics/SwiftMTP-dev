import OSLog

public enum MTPLog {
  public static let subsystem = "com.effortlessmetrics.swiftmtp"
  public static let transport = Logger(subsystem: subsystem, category: "transport")
  public static let proto     = Logger(subsystem: subsystem, category: "protocol")
  public static let index     = Logger(subsystem: subsystem, category: "index")
  public static let sync      = Logger(subsystem: subsystem, category: "sync")
  public static let perf      = Logger(subsystem: subsystem, category: "performance")

  // Signpost loggers for performance measurement
  public enum Signpost {
    public static let enumerate = Logger(subsystem: subsystem, category: "enumerate")
    public static let transfer = Logger(subsystem: subsystem, category: "transfer")
    public static let resume = Logger(subsystem: subsystem, category: "resume")
    public static let chunk = Logger(subsystem: subsystem, category: "chunk")
  }
}
