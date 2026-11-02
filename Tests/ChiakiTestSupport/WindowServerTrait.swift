import Foundation
import Testing

/// Facts about the environment tests run in.
public enum TestEnvironment {
    /// Whether tests run without a window server, set by `CHIAKI_HEADLESS_TESTS=1`.
    public static var isHeadless: Bool {
        ProcessInfo.processInfo.environment["CHIAKI_HEADLESS_TESTS"] == "1"
    }
}

extension Trait where Self == ConditionTrait {
    /// Skips a test or suite that opens real windows when tests run headless.
    public static var requiresWindowServer: Self {
        .enabled(if: !TestEnvironment.isHeadless, "Opens windows; skipped by make test HEADLESS=1")
    }
}
