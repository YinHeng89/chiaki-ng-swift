import ChiakiModels
import ComposableArchitecture
import Foundation

/// Reaches the platform the app runs on: what the app does when it quits, when the Mac sleeps and when it wakes,
/// the window around a stream and a command-line launch, the system pasteboard, files offered for sharing or
/// saved as error reports, and alerts in the system's notification centre.
///
/// The live value is provided by the app's composition root, which owns the native playback lifetime, the power
/// observer and the window. The system shows the app's alerts only while the app is not in front; while it is,
/// the app's own toasts and badge carry the alert instead.
public struct PlatformClient: Sendable {
    /// Whether the system shows the app's alerts.
    public enum NotificationPermission: Equatable, Sendable {
        /// The person has not been asked yet.
        case notAsked

        /// The system shows the app's alerts.
        case allowed

        /// The person turned the app's alerts off.
        case denied
    }

    /// Stops every native session before the app quits.
    public var shutdown: @Sendable () async -> Void

    /// Stops streaming for sleep, resting the console when asked; returns whether a stream was stopped.
    public var sleep: @Sendable (_ restConsole: Bool) async -> Bool

    /// Whether a console stream should rest its console when the Mac sleeps.
    public var restsConsoleOnSleep: @Sendable () async -> Bool

    /// Lets the Mac sleep after the sleep notification with this number.
    public var allowSleep: @Sendable (_ notification: Int) async -> Void

    /// Recovers network state after the Mac woke.
    public var woke: @Sendable () async -> Void

    /// Recovers network state after the network the Mac uses changed, such as a switch to another Wi-Fi network.
    public var networkChanged: @Sendable () async -> Void

    /// Asks the platform to quit the app, which then runs the shutdown.
    public var quit: @Sendable () async -> Void

    /// Reads the time since the system started, the clock input events are stamped with.
    public var uptime: @Sendable () -> TimeInterval

    /// Presents the window full screen with the saved video fit when the picture settings ask for full screen
    /// streams.
    public var enterFullScreen: @Sendable () async -> Void

    /// Restores the window to its presentation from before the stream.
    public var restoreWindow: @Sendable () async -> Void

    /// Applies a command-line launch's display preferences before the stream connects.
    public var prepareLaunch: @Sendable (LaunchDisplay) async -> Void

    /// Shows a command-line launch's stream as it asked, such as entering full screen.
    public var presentLaunch: @Sendable (LaunchDisplay) async -> Void

    /// Undoes what ``presentLaunch`` did once the launched stream ends or fails.
    public var restoreLaunch: @Sendable () async -> Void

    /// Replaces the pasteboard contents with text.
    public var copy: @Sendable (_ text: String) async -> Void

    /// Reads the text on the pasteboard, or `nil` when the pasteboard holds none.
    public var paste: @Sendable () async -> String?

    /// Writes text to a temporary file, hands its location over and keeps it until the calling task is
    /// cancelled, then removes it.
    ///
    /// - Parameters: the file's contents, the file name with its extension, and a closure that receives the
    ///   file's location once it is written and is not called when writing fails.
    public var offerFile: @Sendable (
        _ text: String,
        _ name: String,
        _ ready: @escaping @Sendable (URL) async -> Void
    ) async -> Void

    /// Asks the user where to save an error report; `nil` when they cancel.
    public var chooseReportDestination: @Sendable (_ suggestedName: String) async -> URL?

    /// Writes an error report's text to a file, replacing it.
    public var writeReport: @Sendable (_ text: String, _ url: URL) async throws -> Void

    /// Reads whether the system shows the app's alerts, asking the person first when they have not been asked.
    public var notificationPermission: @Sendable () async -> NotificationPermission

    /// Asks the system to show an alert, asking the person for permission the first time.
    ///
    /// - Parameters: the id that lets a newer alert with the same id replace it, the alert's first line and its
    ///   further text.
    public var postNotification: @Sendable (_ id: String, _ title: String, _ body: String) async -> Void

    /// Creates a client from its operations; only the shutdown is required.
    ///
    /// - Parameters:
    ///   - shutdown: Stops every native session.
    ///   - sleep: Stops streaming for sleep; by default it stops nothing.
    ///   - restsConsoleOnSleep: Reads whether the console rests when the Mac sleeps; by default it does not.
    ///   - allowSleep: Lets the Mac sleep; by default nothing.
    ///   - woke: Recovers after wake; by default nothing.
    ///   - networkChanged: Recovers after the network changed; by default nothing.
    ///   - quit: Asks the platform to quit the app; by default nothing.
    ///   - uptime: Reads the time since the system started; by default zero.
    ///   - enterFullScreen: Presents the window full screen for a stream; by default nothing.
    ///   - restoreWindow: Restores the window after a stream; by default nothing.
    ///   - prepareLaunch: Applies a launch's display preferences; by default nothing.
    ///   - presentLaunch: Shows a launch's stream as it asked; by default nothing.
    ///   - restoreLaunch: Undoes a launch's presentation; by default nothing.
    ///   - copy: Replaces the pasteboard contents; by default it reports an issue.
    ///   - paste: Reads the pasteboard; by default it reports an issue and reads nothing.
    ///   - offerFile: Offers text as a temporary file; by default it reports an issue.
    ///   - chooseReportDestination: Asks where to save a report; by default it reports an issue and chooses
    ///     nothing.
    ///   - writeReport: Writes a report to a file; by default it reports an issue.
    ///   - notificationPermission: Reads whether alerts are shown; by default it reports an issue and answers
    ///     denied.
    ///   - postNotification: Posts an alert; by default it reports an issue.
    public init(
        shutdown: @escaping @Sendable () async -> Void,
        sleep: @escaping @Sendable (_ restConsole: Bool) async -> Bool = { _ in
            false
        },
        restsConsoleOnSleep: @escaping @Sendable () async -> Bool = {
            false
        },
        allowSleep: @escaping @Sendable (_ notification: Int) async -> Void = { _ in
        },
        woke: @escaping @Sendable () async -> Void = {
        },
        networkChanged: @escaping @Sendable () async -> Void = {
        },
        quit: @escaping @Sendable () async -> Void = {
        },
        uptime: @escaping @Sendable () -> TimeInterval = {
            0
        },
        enterFullScreen: @escaping @Sendable () async -> Void = {
        },
        restoreWindow: @escaping @Sendable () async -> Void = {
        },
        prepareLaunch: @escaping @Sendable (LaunchDisplay) async -> Void = { _ in
        },
        presentLaunch: @escaping @Sendable (LaunchDisplay) async -> Void = { _ in
        },
        restoreLaunch: @escaping @Sendable () async -> Void = {
        },
        copy: @escaping @Sendable (_ text: String) async -> Void = { _ in
            reportIssue("PlatformClient.copy is unimplemented")
        },
        paste: @escaping @Sendable () async -> String? = {
            reportIssue("PlatformClient.paste is unimplemented")
            return nil
        },
        offerFile: @escaping @Sendable (
            _ text: String,
            _ name: String,
            _ ready: @escaping @Sendable (URL) async -> Void
        ) async -> Void = { _, _, _ in
            reportIssue("PlatformClient.offerFile is unimplemented")
        },
        chooseReportDestination: @escaping @Sendable (_ suggestedName: String) async -> URL? = { _ in
            reportIssue("PlatformClient.chooseReportDestination is unimplemented")
            return nil
        },
        writeReport: @escaping @Sendable (_ text: String, _ url: URL) async throws -> Void = { _, _ in
            reportIssue("PlatformClient.writeReport is unimplemented")
        },
        notificationPermission: @escaping @Sendable () async -> NotificationPermission = {
            reportIssue("PlatformClient.notificationPermission is unimplemented")
            return .denied
        },
        postNotification: @escaping @Sendable (
            _ id: String,
            _ title: String,
            _ body: String
        ) async -> Void = { _, _, _ in
            reportIssue("PlatformClient.postNotification is unimplemented")
        }
    ) {
        self.shutdown = shutdown
        self.sleep = sleep
        self.restsConsoleOnSleep = restsConsoleOnSleep
        self.allowSleep = allowSleep
        self.woke = woke
        self.networkChanged = networkChanged
        self.quit = quit
        self.uptime = uptime
        self.enterFullScreen = enterFullScreen
        self.restoreWindow = restoreWindow
        self.prepareLaunch = prepareLaunch
        self.presentLaunch = presentLaunch
        self.restoreLaunch = restoreLaunch
        self.copy = copy
        self.paste = paste
        self.offerFile = offerFile
        self.chooseReportDestination = chooseReportDestination
        self.writeReport = writeReport
        self.notificationPermission = notificationPermission
        self.postNotification = postNotification
    }
}

extension PlatformClient: TestDependencyKey {
    /// Reports an issue when a test quits, uses the pasteboard, offers or saves a file or reads or posts an
    /// alert without overriding the operation; sleeping stops nothing and the window and launch operations do
    /// nothing, so tests never touch a real window.
    public static let testValue = PlatformClient(
        shutdown: {
            reportIssue("PlatformClient.shutdown is unimplemented")
        }
    )
}

extension DependencyValues {
    /// The platform the app runs on: its lifecycle, window, pasteboard, files and system alerts.
    public var platform: PlatformClient {
        get {
            self[PlatformClient.self]
        }
        set {
            self[PlatformClient.self] = newValue
        }
    }
}
