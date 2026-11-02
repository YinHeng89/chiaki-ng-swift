import Dependencies
import ChiakiModels
import ChiakiDiagnostics
import PlatformUI
import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
#if os(macOS)
    import IOKit.pwr_mgt
#endif

/// Keeps the display from sleeping while a stream is playing.
enum DisplayAwakeAssertion {
    #if os(macOS)
        /// Takes an IOKit power assertion that prevents idle display sleep, logging a warning if it cannot be
        /// created.
        /// - Returns: A closure that releases the assertion; it does nothing when the assertion failed.
        @MainActor static func hold() -> @MainActor @Sendable () -> Void {
            var assertion = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "chiaki-ng is streaming" as CFString,
                &assertion
            )
            guard result == kIOReturnSuccess else {
                report(
                    "The display could not be kept awake during the stream (IOKit \(result))",
                    level: .warning
                )
                return {
                }
            }
            let held = assertion
            return {
                IOPMAssertionRelease(held)
            }
        }

        private static func report(_ message: String, level: LogLevel) {
            @Dependency(\.logger) var logger
            logger.enqueue(.diagnostic(.playback, level, message))
        }
    #else
        @MainActor private static var holders = 0

        /// Disables the idle timer, counting overlapping holders so the timer is re-enabled only when the
        /// last one releases.
        /// - Returns: A closure that releases this holder.
        @MainActor static func hold() -> @MainActor @Sendable () -> Void {
            holders += 1
            UIApplication.shared.isIdleTimerDisabled = true
            return {
                holders -= 1
                UIApplication.shared.isIdleTimerDisabled = holders > 0
            }
        }
    #endif
}
