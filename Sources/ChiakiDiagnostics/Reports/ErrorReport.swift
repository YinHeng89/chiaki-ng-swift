import ChiakiModels
import Darwin
import Foundation

/// The plain-text error report a user saves and attaches to a bug: the environment, the logging settings and
/// every log file, oldest first.
public enum ErrorReport {
    /// One log file's contribution to a report.
    public struct File: Equatable, Sendable {
        /// The file name.
        public let name: String

        /// The file's text, or `nil` when it does not exist or cannot be read.
        public let text: String?

        /// Creates a file entry.
        ///
        /// - Parameters:
        ///   - name: The file name.
        ///   - text: The file's text, or `nil` when it is missing.
        public init(name: String, text: String?) {
            self.name = name
            self.text = text
        }
    }

    /// The log files included, oldest generation first.
    public static let fileNames = ["chiaki.3.log", "chiaki.2.log", "chiaki.1.log", "chiaki.log"]

    /// The default name offered when saving a report.
    ///
    /// - Parameter now: The timestamp in the name.
    /// - Returns: A file name with no colons.
    public static func suggestedFileName(now: Date = Date()) -> String {
        let stamp = now.ISO8601Format().replacingOccurrences(of: ":", with: "-")
        return "\(AppIdentity.name)-error-report-\(stamp).txt"
    }

    /// Renders a report.
    ///
    /// - Parameters:
    ///   - environment: The app and machine description.
    ///   - settings: The logging settings in force.
    ///   - directory: The log folder as it should appear, already redacted when redaction is on.
    ///   - generated: The report timestamp.
    ///   - files: The log files, in the order they are shown.
    /// - Returns: The report text, ending in a newline.
    public static func render(
        environment: ErrorReportEnvironment, settings: LogSettings, directory: String, generated: Date,
        files: [File]
    ) -> String {
        var lines = [
            "\(AppIdentity.name) error report",
            "Generated: \(generated.ISO8601Format())",
            "App: \(environment.appVersion) (build \(environment.build))",
            "macOS: \(environment.system)",
            "Mac: \(environment.model) \(environment.architecture)",
            "Log level: \(settings.level.rawValue)",
            "Identifiers redacted: \(LogFormat.yesNo(settings.redactIdentifiers))",
            "API capture: \(LogFormat.yesNo(settings.captureAPI))",
            "Log folder: \(directory)",
            ""
        ]
        for file in files {
            lines.append("===== \(file.name) =====")
            if let text = file.text {
                lines.append(text.hasSuffix("\n")
                    ? String(text.dropLast())
                    : text)
            } else {
                lines.append("(no file)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// The app version and machine an error report was generated on.
public struct ErrorReportEnvironment: Equatable, Sendable {
    /// The marketing version.
    public var appVersion: String

    /// The build number.
    public var build: String

    /// The operating system version text.
    public var system: String

    /// The hardware model identifier.
    public var model: String

    /// The CPU architecture.
    public var architecture: String

    /// Creates an environment from its parts.
    ///
    /// - Parameters:
    ///   - appVersion: The marketing version.
    ///   - build: The build number.
    ///   - system: The operating system version text.
    ///   - model: The hardware model identifier.
    ///   - architecture: The CPU architecture.
    public init(appVersion: String, build: String, system: String, model: String, architecture: String) {
        self.appVersion = appVersion
        self.build = build
        self.system = system
        self.model = model
        self.architecture = architecture
    }

    /// Describes the running process and machine.
    ///
    /// - Parameters:
    ///   - appVersion: The marketing version to report.
    ///   - bundle: The bundle the build number is read from.
    /// - Returns: The environment, with `unknown` for anything that cannot be read.
    public static func current(appVersion: String, bundle: Bundle = .main) -> Self {
        .init(
            appVersion: appVersion,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            model: sysctlString("hw.model"),
            architecture: sysctlString("hw.machine")
        )
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        return buffer.withUnsafeBufferPointer {
            String(cString: $0.baseAddress!)
        }
    }
}
