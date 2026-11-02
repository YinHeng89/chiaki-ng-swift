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
            return progress("Connecting to your console", message: "Loading your saved consoles.")
        case .discovering(_, let plan):
            return progress(title(for: plan), message: "Looking for \(plan.name) on your network.")
        case .waking(_, let plan):
            return progress(
                title(for: plan),
                message: "\(plan.name) is in rest mode. Sending a wake request."
            )
        case .awaitingWake(_, let plan):
            return progress(
                title(for: plan),
                message: "Waiting up to 25 seconds for \(plan.name) to wake up."
            )
        case let .failed(name, failure):
            return AppConfirmation(
                title: failureTitle(failure, name: name),
                message: failureMessage(failure),
                systemImage: "exclamationmark.triangle",
                cancelTitle: "OK"
            )
        }
    }

    private static func title(for plan: AutoConnect.Plan) -> String {
        switch plan.mode {
        case .stream:
            "Connecting to \(plan.name)"
        case .wake:
            "Waking \(plan.name)"
        }
    }

    private static func progress(_ title: String, message: String) -> AppConfirmation {
        AppConfirmation(
            title: title,
            message: message,
            systemImage: "play.tv",
            cancelTitle: "Cancel",
            progress: true
        )
    }

    private static func failureTitle(_ failure: AutoConnect.Failure, name: String?) -> String {
        let console = name ?? "the console"
        switch failure {
        case .notRegistered, .storage, .busy, .remoteUnavailable:
            return "Couldn’t connect to \(console)"
        case .wakeFailed, .wakeTimedOut, .notFound:
            return "Couldn’t wake \(console)"
        }
    }

    private static func failureMessage(_ failure: AutoConnect.Failure) -> String {
        switch failure {
        case .notRegistered:
            "This console isn’t registered on this device. Register it again to play."
        case .remoteUnavailable:
            "This console hasn’t been set up for remote play."
        case .busy:
            "Another stream or task is in progress. Finish it and try again."
        case .storage:
            "Your saved consoles couldn’t be read. Please try again."
        case .wakeFailed:
            "The wake request couldn’t be sent. Check the network and try again."
        case .wakeTimedOut:
            "The console didn’t wake up within 25 seconds. Check it’s connected to the network."
        case .notFound:
            "The console wasn’t found on your network."
        }
    }
}
