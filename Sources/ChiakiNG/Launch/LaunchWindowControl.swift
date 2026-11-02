import ChiakiClients
import ChiakiClientsLive
import ChiakiModels
import Dependencies
import Foundation
import PlatformUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Moves the main window into full screen for a launched stream and back out afterwards, driving a
/// `WindowFullScreenMachine` from window notifications and timeouts.
@MainActor final class LaunchWindowControl {
    /// Creates a control that has not touched the window.
    init() {}

    /// How long to wait for a full screen transition before treating it as failed.
    static let transitionTimeout = DispatchTimeInterval.seconds(3)
    /// The full screen state machine that decides which window commands to run.
    private(set) var machine = WindowFullScreenMachine()
    #if os(macOS)
        private var window: PlatformWindow?
        private var observers = [NSObjectProtocol]()

        /// Enters full screen on the main window when the launch asks for it.
        /// - Parameter display: How the launch wants the stream shown.
        func present(_ display: LaunchDisplay) {
            guard case .fullscreen = display else {
                return
            }
            if machine.phase == .untouched {
                window = Self.mainWindow
            }
            guard let window else {
                return
            }
            send(.present(windowIsFullScreen: window.styleMask.contains(.fullScreen)))
        }

        /// Returns the window to the state it had before the launch.
        func restore() {
            guard let window else {
                return
            }
            send(.restore(windowIsFullScreen: window.styleMask.contains(.fullScreen)))
        }

        private func send(_ event: WindowFullScreenMachine.Event) {
            for command in machine.handle(event) {
                perform(command)
            }
            if machine.phase == .untouched {
                window = nil
            }
        }

        private func perform(_ command: WindowFullScreenMachine.Command) {
            switch command {
            case .toggle:
                window?.toggleFullScreen(nil)
            case .observe:
                observe()
            case .stopObserving:
                for observer in observers {
                    NotificationCenter.default.removeObserver(observer)
                }
                observers = []
            case .scheduleTimeout(let attempt):
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionTimeout) { [weak self] in
                    MainActor.assumeIsolated {
                        self?.transitionTimedOut(attempt)
                    }
                }
            }
        }

        private func transitionTimedOut(_ attempt: Int) {
            guard let window else {
                return
            }
            send(.timedOut(attempt: attempt, windowIsFullScreen: window.styleMask.contains(.fullScreen)))
        }

        private func observe() {
            guard let window, observers.isEmpty else {
                return
            }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: PlatformWindow.didEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.send(.entered)
                    }
                },
                center
                    .addObserver(forName: PlatformWindow.didExitFullScreenNotification, object: window,
                                 queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.send(.exited)
                        }
                    }
            ]
        }

        private static var mainWindow: PlatformWindow? {
            NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first {
                $0.isVisible && $0.canBecomeMain
            }
        }
    #else
        /// Does nothing on this platform.
        func present(_ display: LaunchDisplay) {
        }

        /// Does nothing on this platform.
        func restore() {
        }
    #endif
}

extension PlatformClient {
    /// Returns this client with the window and launch operations driving the app's window control on the main
    /// actor: a stream reads the picture settings to enter full screen, and a command-line launch applies its
    /// video fit, enters full screen when asked and restores the window afterwards.
    ///
    /// - Parameter window: The composition root's one window control.
    /// - Returns: A copy whose window and launch operations go through the window control.
    func presenting(through window: LaunchWindowControl) -> Self {
        var client = self
        client.enterFullScreen = {
            @Dependency(\.accountService) var accountService
            guard let settings = try? await accountService.storage().settings
                .value(SettingKeys.picture),
                settings.fullScreenStreams else {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }
                window.present(.fullscreen(settings.videoFit.mode))
            }
        }
        client.restoreWindow = {
            await MainActor.run {
                window.restore()
            }
        }
        client.prepareLaunch = { display in
            @Dependency(\.launchPresentation) var presentation
            await MainActor.run {
                presentation.videoFit = display.videoFit
            }
        }
        client.presentLaunch = { display in
            await MainActor.run {
                window.present(display)
            }
        }
        client.restoreLaunch = {
            @Dependency(\.launchPresentation) var presentation
            await MainActor.run {
                presentation.videoFit = nil
                window.restore()
            }
        }
        return client
    }
}
