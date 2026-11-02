import ChiakiBridge
import CxxStdlib
import Foundation

/// Reads the open core's own diagnostic lines while no stream is following them.
///
/// The catalog, the launch checks and the HTTP trace write into the core's log queue; a running stream
/// collects them with its own lines, and between streams this bridge does.
public struct CoreLogBridge: Sendable {
    /// One diagnostic line the core wrote.
    public struct Line: Equatable, Sendable {
        /// The core's severity level.
        public let severity: Int
        /// The formatted line, starting with its origin, attempt, sequence and elapsed time.
        public let message: String
    }

    /// The most lines one ``read()`` takes.
    public static let readLimit = 288

    /// Creates a bridge over the process's open core.
    public init() {}

    /// Takes the lines written since the last read.
    ///
    /// - Returns: Up to ``readLimit`` lines, oldest first; empty while a stream follows the core's log or the
    ///   core is closed.
    public func read() -> [Line] {
        chiaki_bridge.CoreLogBridge.read(Self.readLimit).map { line in
            Line(severity: Int(line.severity.rawValue), message: String(line.message))
        }
    }
}
