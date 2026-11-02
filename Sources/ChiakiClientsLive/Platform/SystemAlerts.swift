import ChiakiClients
import ChiakiDiagnostics
import Dependencies
import UserNotifications

/// The system's notification centre, asking for permission to show alerts before the first one and logging the
/// permission and the outcome of each alert.
enum SystemAlerts {
    /// Reads whether the system shows the app's alerts, asking the person first when they have not been asked,
    /// and logs the permission and alert style.
    ///
    /// - Returns: The permission after any question.
    static func permission() async -> PlatformClient.NotificationPermission {
        @Dependency(\.logger) var logger
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        await logger.log(.diagnostic(
            .app,
            .info,
            "Alerts: system notification permission \(describe(settings.authorizationStatus)), "
                + "alert style \(describe(settings.alertStyle))"
        ))
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .notDetermined:
            return .notAsked
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    /// Asks the system to show an alert, asking the person for permission the first time, and logs the
    /// outcome.
    ///
    /// - Parameters:
    ///   - id: Identifies the alert, so a newer alert with the same id replaces it.
    ///   - title: The alert's first line.
    ///   - body: The alert's further text.
    static func post(id: String, title: String, body: String) async {
        @Dependency(\.logger) var logger
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                await logger.log(.diagnostic(
                    .app,
                    .warning,
                    "Alerts: permission request failed: \(error)"
                ))
            }
            settings = await center.notificationSettings()
        }
        await logger.log(.diagnostic(
            .app,
            .info,
            "Alerts: posting a system notification; permission \(describe(settings.authorizationStatus)), "
                + "alert style \(describe(settings.alertStyle))"
        ))
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        } catch {
            await logger.log(.diagnostic(
                .app,
                .warning,
                "Alerts: the system refused the notification: \(error)"
            ))
        }
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            "not asked"
        case .denied:
            "denied"
        case .authorized:
            "allowed"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        @unknown default:
            "unknown"
        }
    }

    private static func describe(_ style: UNAlertStyle) -> String {
        switch style {
        case .none:
            "none"
        case .banner:
            "banners"
        case .alert:
            "alerts"
        @unknown default:
            "unknown"
        }
    }
}
