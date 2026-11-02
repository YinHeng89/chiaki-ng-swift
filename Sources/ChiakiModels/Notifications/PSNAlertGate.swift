import Foundation

/// Decides whether a PSN alert is shown or only listed, so a flood of invitations or messages cannot turn
/// into a flood of alerts.
///
/// An alert is listed quietly when its kind is switched off, its sender is muted, the same sender raised an
/// alert of the same kind within ``invitationWindow`` for an invitation or ``messageWindow`` for a message,
/// or ``globalLimit`` alerts were already shown within ``globalWindow``. A sender's repeats inside the window
/// are counted, so the list can say how many times they asked.
public struct PSNAlertGate: Equatable, Sendable {
    /// What happens to one alert.
    public enum Decision: Equatable, Sendable {
        /// The alert is shown.
        case show

        /// The alert is listed without being shown, for this reason.
        case quiet(Reason)
    }

    /// Why an alert was listed without being shown.
    public enum Reason: Equatable, Sendable {
        /// Alerts of its kind are switched off.
        case kindOff

        /// Its sender is muted.
        case muted

        /// Its sender raised an alert a moment ago; this is their repeat number `count`, counting the first
        /// alert as one.
        case repeated(count: Int)

        /// Too many alerts were shown just now.
        case busy
    }

    /// How long one sender's further invitations are listed quietly after an invitation of theirs is shown.
    public static let invitationWindow: Duration = .seconds(120)

    /// How long one sender's further messages are listed quietly after a message of theirs is shown, so a
    /// burst of messages raises one alert while a slower conversation still raises one each time.
    public static let messageWindow: Duration = .seconds(30)

    /// The span over which shown alerts are counted for ``globalLimit``.
    public static let globalWindow: Duration = .seconds(60)

    /// The most alerts shown within ``globalWindow``.
    public static let globalLimit = 4

    private struct Recent: Equatable, Sendable {
        var shownAt: Date
        var count: Int
    }

    private struct SenderKey: Hashable, Sendable {
        var sender: String
        var isInvitation: Bool
    }

    private var bySender: [SenderKey: Recent] = [:]
    private var shown: [Date] = []

    /// Creates a gate that has shown nothing.
    public init() {}

    /// Decides one alert and remembers it.
    ///
    /// - Parameters:
    ///   - sender: The sender's online id.
    ///   - isInvitation: Whether the alert is a game invitation rather than a message.
    ///   - settings: The alert settings.
    ///   - now: When the alert arrived.
    /// - Returns: Whether to show it.
    public mutating func admit(
        sender: String,
        isInvitation: Bool,
        settings: PSNAlertSettings,
        now: Date
    ) -> Decision {
        let enabled = isInvitation
            ? settings.invitations
            : settings.messages
        guard enabled else {
            return .quiet(.kindOff)
        }
        guard !settings.isMuted(sender) else {
            return .quiet(.muted)
        }
        shown.removeAll {
            now.timeIntervalSince($0) >= Self.seconds(Self.globalWindow)
        }
        let key = SenderKey(sender: sender, isInvitation: isInvitation)
        let window = isInvitation
            ? Self.invitationWindow
            : Self.messageWindow
        if var recent = bySender[key], now.timeIntervalSince(recent.shownAt) < Self.seconds(window) {
            recent.count += 1
            bySender[key] = recent
            return .quiet(.repeated(count: recent.count))
        }
        guard shown.count < Self.globalLimit else {
            return .quiet(.busy)
        }
        bySender[key] = Recent(shownAt: now, count: 1)
        shown.append(now)
        return .show
    }

    /// Decides the alert that sums up the messages a sender's window held back, once the window ended, and
    /// opens a new window for the sender.
    ///
    /// The alert still needs messages switched on, the sender unmuted and room under ``globalLimit``.
    ///
    /// - Parameters:
    ///   - sender: The sender's online id.
    ///   - settings: The alert settings.
    ///   - now: When the window ended.
    /// - Returns: Whether to show the summary.
    public mutating func admitSummary(sender: String, settings: PSNAlertSettings, now: Date) -> Decision {
        guard settings.messages else {
            return .quiet(.kindOff)
        }
        guard !settings.isMuted(sender) else {
            return .quiet(.muted)
        }
        shown.removeAll {
            now.timeIntervalSince($0) >= Self.seconds(Self.globalWindow)
        }
        guard shown.count < Self.globalLimit else {
            return .quiet(.busy)
        }
        bySender[SenderKey(sender: sender, isInvitation: false)] = Recent(shownAt: now, count: 1)
        shown.append(now)
        return .show
    }

    /// How long is left of a sender's window, during which their further alerts of a kind are listed quietly.
    ///
    /// - Parameters:
    ///   - sender: The sender's online id.
    ///   - isInvitation: Whether the window is for invitations rather than messages.
    ///   - now: The time now.
    /// - Returns: The time left, or `nil` when no window is open.
    public func remaining(sender: String, isInvitation: Bool, now: Date) -> Duration? {
        guard let recent = bySender[SenderKey(sender: sender, isInvitation: isInvitation)] else {
            return nil
        }
        let window = isInvitation
            ? Self.invitationWindow
            : Self.messageWindow
        let left = Self.seconds(window) - now.timeIntervalSince(recent.shownAt)
        guard left > 0 else {
            return nil
        }
        return .milliseconds(Int64((left * 1000).rounded(.up)))
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        TimeInterval(duration.components.seconds)
    }
}
