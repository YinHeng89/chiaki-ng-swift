import ChiakiModels
import Foundation
#if canImport(OSLog)
    import OSLog
#endif

/// Mirrors kept log lines to the unified system log so Console.app shows them.
public struct SystemLogSink: Sendable {
    /// Receives each kept line with its level and source location.
    public var record: @Sendable (LogLevel, String, LogSource) -> Void

    /// Creates a sink from its write function.
    ///
    /// - Parameter record: Receives each kept line.
    public init(record: @escaping @Sendable (LogLevel, String, LogSource) -> Void) {
        self.record = record
    }

    /// A sink that drops everything.
    public static let disabled = Self { _, _, _ in
    }

    /// A sink that writes to the unified system log under the app's bundle identifier.
    public static var live: Self {
        #if canImport(OSLog)
            let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "application")
            return Self { severity, message, source in
                let level: OSLogType
                switch severity {
                case .off:
                    return
                case .error:
                    level = .error
                case .warning:
                    level = .default
                case .info:
                    level = .info
                case .debug:
                    level = .debug
                }
                logger.log(
                    level: level,
                    """
                    [\(source.file, privacy: .public):\(source.line) \
                    \(source.function, privacy: .public)] \(message, privacy: .public)
                    """
                )
            }
        #else
            return .disabled
        #endif
    }
}
