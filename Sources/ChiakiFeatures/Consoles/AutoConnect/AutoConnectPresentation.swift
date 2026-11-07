import Foundation
import MenuFocus

/// The card shown while an automatic connection runs or after it failed.
public enum AutoConnectPresentation {
    /// The card for where the automatic connection is.
    ///
    /// - Parameter autoConnect: The automatic connection.
    /// - Returns: A progress or failure card, or `nil` while nothing needs showing.
    public static func confirmation(for autoConnect: AutoConnect) -> AppConfirmation? {
        switch autoConnect {
        case .idle, .awaitingLibrary(_, .launchSetting), .checkingLaunchSetting:
            return nil
        case .awaitingLibrary(_, .console):
            return progress(.consolesAutoConnectLoadingTitle, message: .consolesAutoConnectLoadingMessage)
        case .discovering(_, let plan):
            return progress(title(for: plan), message: .consolesAutoConnectDiscovering(console: plan.name))
        case .waking(_, let plan):
            return progress(title(for: plan), message: .consolesAutoConnectWaking(console: plan.name))
        case .awaitingWake(_, let plan):
            return progress(title(for: plan), message: .consolesAutoConnectAwaitingWake(console: plan.name))
        case let .failed(name, failure):
            return AppConfirmation(
                title: failureTitle(failure, name: name),
                message: failureMessage(failure),
                systemImage: "exclamationmark.triangle",
                cancelTitle: .commonOk
            )
        }
    }

    private static func title(for plan: AutoConnect.Plan) -> LocalizedStringResource {
        switch plan.mode {
        case .stream:
            .consolesAutoConnectConnectingTo(console: plan.name)
        case .wake:
            .consolesAutoConnectWakingTitle(console: plan.name)
        }
    }

    private static func progress(
        _ title: LocalizedStringResource,
        message: LocalizedStringResource
    ) -> AppConfirmation {
        AppConfirmation(
            title: title,
            message: message,
            systemImage: "play.tv",
            cancelTitle: .commonCancel,
            progress: true
        )
    }

    private static func failureTitle(
        _ failure: AutoConnect.Failure,
        name: String?
    ) -> LocalizedStringResource {
        switch failure {
        case .notRegistered, .storage, .busy, .remoteUnavailable:
            name.map { .consolesAutoConnectConnectFailedNamed(console: $0) }
                ?? .consolesAutoConnectConnectFailed
        case .wakeFailed, .wakeTimedOut, .notFound:
            name.map { .consolesAutoConnectWakeFailedNamed(console: $0) }
                ?? .consolesAutoConnectWakeFailedTitle
        }
    }

    private static func failureMessage(_ failure: AutoConnect.Failure) -> LocalizedStringResource {
        switch failure {
        case .notRegistered:
            .consolesAutoConnectNotRegistered
        case .remoteUnavailable:
            .consolesAutoConnectRemoteUnavailable
        case .busy:
            .consolesAutoConnectBusy
        case .storage:
            .consolesAutoConnectStorage
        case .wakeFailed:
            .consolesAutoConnectWakeFailed
        case .wakeTimedOut:
            .consolesAutoConnectWakeTimedOut
        case .notFound:
            .consolesAutoConnectNotFound
        }
    }
}
