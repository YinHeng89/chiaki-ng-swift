import Dependencies
import ChiakiDiagnostics
import PlatformUI
import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
#if os(macOS)
    import IOKit
    import IOKit.pwr_mgt
#endif

/// Tells the app when the system is about to sleep and when it wakes, and holds sleep for up to a set time so
/// streams can stop cleanly first. On iOS a stream keeps running in the background, so the app only hears that
/// it woke when it returns to the foreground.
@MainActor final class SystemPowerObserver {
    /// The IOKit power messages the observer acts on.
    enum Message: UInt32 {
        /// The system asks whether it may sleep; the observer always agrees.
        case canSystemSleep = 0xE000_0270
        /// The system is going to sleep; the observer holds it until streams stop or the hold expires.
        case systemWillSleep = 0xE000_0280
    }

    #if os(macOS)
        private var rootPort: io_connect_t = 0
        private var notifyPort: IONotificationPortRef?
        private var notifier: io_object_t = 0
    #endif
    private var pending: [Int: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []
    private let willSleep: @MainActor (Int) -> Void
    private let didWake: @MainActor () -> Void
    private let longestHold: Duration

    /// Creates an observer that is idle until it is started.
    /// - Parameters:
    ///   - longestHold: How long sleep is held before it is allowed anyway.
    ///   - willSleep: Called with the notification to release through ``SystemPowerObserver/allowSleep(_:)``,
    ///     or `-1` when there is nothing to release.
    ///   - didWake: Called when the system wakes or the app returns to the foreground.
    init(
        longestHold: Duration = .seconds(10),
        willSleep: @escaping @MainActor (Int) -> Void,
        didWake: @escaping @MainActor () -> Void = {}
    ) {
        self.longestHold = longestHold
        self.willSleep = willSleep
        self.didWake = didWake
    }

    /// The sleep notifications currently held while streams stop.
    var heldNotifications: Set<Int> {
        Set(pending.keys)
    }

    #if os(macOS)
        /// Registers for system power notifications and wake notifications, falling back to the workspace
        /// sleep notification when power registration fails.
        func start() {
            guard rootPort == 0, observers.isEmpty else {
                return
            }
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.didWake()
                }
            })
            let context = Unmanaged.passUnretained(self).toOpaque()
            rootPort = IORegisterForSystemPower(context, &notifyPort, systemPowerCallback, &notifier)
            guard rootPort != 0, let notifyPort else {
                rootPort = 0
                report(
                    "System sleep notifications are unavailable; streams stop without waiting for the console"
                )
                observers.append(center.addObserver(
                    forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.willSleep(-1)
                    }
                })
                return
            }
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
                .commonModes
            )
        }

        /// Releases every held notification and unregisters from power and wake notifications.
        func stop() {
            for task in pending.values {
                task.cancel()
            }
            for notification in pending.keys {
                allow(notification)
            }
            pending = [:]
            for observer in observers {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            observers = []
            guard rootPort != 0 else {
                return
            }
            IODeregisterForSystemPower(&notifier)
            if let notifyPort {
                CFRunLoopRemoveSource(
                    CFRunLoopGetMain(),
                    IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
                    .commonModes
                )
                IONotificationPortDestroy(notifyPort)
            }
            IOServiceClose(rootPort)
            notifyPort = nil
            rootPort = 0
        }

        private func allow(_ notification: Int) {
            IOAllowPowerChange(rootPort, notification)
        }
    #else
        /// Starts watching the app return to the foreground.
        func start() {
            guard observers.isEmpty else {
                return
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.didWake()
                }
            })
        }

        /// Stops watching the app return to the foreground.
        func stop() {
            for task in pending.values {
                task.cancel()
            }
            pending = [:]
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
        }

        private func allow(_ notification: Int) {
        }
    #endif

    /// Lets the system sleep for a held notification and cancels its deadline; does nothing when the
    /// notification is not held.
    /// - Parameter notification: The notification passed to the will-sleep handler.
    func allowSleep(_ notification: Int) {
        guard let deadline = pending.removeValue(forKey: notification) else {
            return
        }
        deadline.cancel()
        allow(notification)
    }

    /// Handles a power message: agrees to sleep requests, and for a coming sleep holds it, starts the
    /// deadline and calls the will-sleep handler.
    /// - Parameters:
    ///   - message: The raw power message.
    ///   - argument: The notification identifier to release later.
    func receive(_ message: UInt32, argument: Int) {
        switch Message(rawValue: message) {
        case .canSystemSleep:
            allow(argument)
        case .systemWillSleep:
            guard pending[argument] == nil else {
                return
            }
            pending[argument] = Task { @MainActor [weak self] in
                guard let hold = self?.longestHold else {
                    return
                }
                try? await Task.sleep(for: hold)
                guard !Task.isCancelled, let self, self.pending[argument] != nil else {
                    return
                }
                self.report("Streams took too long to stop; allowing system sleep anyway")
                self.allowSleep(argument)
            }
            willSleep(argument)
        case nil:
            break
        }
    }

    private func report(_ message: String) {
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.app, .warning, message))
    }
}

#if os(macOS)
    private func systemPowerCallback(
        context: UnsafeMutableRawPointer?,
        service: io_service_t,
        message: UInt32,
        argument: UnsafeMutableRawPointer?
    ) {
        guard let context else {
            return
        }
        let observer = Unmanaged<SystemPowerObserver>.fromOpaque(context).takeUnretainedValue()
        let notification = Int(bitPattern: argument)
        MainActor.assumeIsolated {
            observer.receive(message, argument: notification)
        }
    }
#endif
