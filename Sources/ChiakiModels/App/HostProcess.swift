import Foundation

/// What kind of process the code is running in.
///
/// A test harness, a SwiftUI preview or a headless test run must never touch the user's real data, so every
/// path to live data first asks ``isHarness``.
public struct HostProcess: Equatable, Sendable {
    /// Whether the process is a test runner, a preview host or a headless test run.
    public let isHarness: Bool

    /// Classifies a process from what it can observe about itself.
    ///
    /// Any one harness signal is enough to mark the process as a harness.
    ///
    /// - Parameters:
    ///   - environment: The process environment.
    ///   - name: The process name.
    ///   - bundles: The paths of every loaded bundle.
    ///   - hasTestRuntime: Whether the XCTest runtime is loaded.
    public init(environment: [String: String], name: String, bundles: [String], hasTestRuntime: Bool) {
        let markers = [
            "XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier",
            "SWIFT_TESTING_ENABLED"
        ]
        let hosts = ["xctest", "swiftpm-testing-helper", "swiftpm-xctest-helper"]
        isHarness = hasTestRuntime
            || markers.contains { environment[$0] != nil }
            || environment["CHIAKI_HEADLESS_TESTS"] == "1"
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || hosts.contains(name)
            || bundles.contains { $0.hasSuffix(".xctest") }
    }

    /// The running process.
    public static var current: Self {
        Self(
            environment: ProcessInfo.processInfo.environment,
            name: ProcessInfo.processInfo.processName,
            bundles: Bundle.allBundles.map(\.bundlePath),
            hasTestRuntime: NSClassFromString("XCTestCase") != nil
        )
    }
}
