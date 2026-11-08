import Foundation

/// A notice a PS5 cloud console shows over its game, such as a saved screenshot or an earned trophy, shown
/// here as a toast.
public struct CloudSystemNotice: Equatable, Sendable {
    /// The grade of an earned trophy.
    public enum TrophyGrade: Equatable, Sendable {
        /// A bronze trophy.
        case bronze

        /// A silver trophy.
        case silver

        /// A gold trophy.
        case gold

        /// The platinum trophy.
        case platinum

        /// The grade's name.
        public var name: LocalizedStringResource {
            switch self {
            case .bronze:
                .trophiesGradeBronze
            case .silver:
                .trophiesGradeSilver
            case .gold:
                .trophiesGradeGold
            case .platinum:
                .trophiesGradePlatinum
            }
        }

        /// The toast's sentence for earning a trophy of the grade.
        var earnedSummary: LocalizedStringResource {
            switch self {
            case .bronze:
                .cloudNoticeTrophyBronze
            case .silver:
                .cloudNoticeTrophySilver
            case .gold:
                .cloudNoticeTrophyGold
            case .platinum:
                .cloudNoticeTrophyPlatinum
            }
        }
    }

    /// What the console reported.
    public enum Kind: Equatable, Sendable {
        /// A screenshot was taken.
        case screenshotSaved

        /// The game does not allow a screenshot here.
        case screenshotRefused

        /// A video clip was saved.
        case recordingSaved

        /// The game does not allow recording here.
        case recordingRefused

        /// Recording paused during a scene the game protects.
        case recordingPaused

        /// Recording resumed.
        case recordingResumed

        /// The clip reached its longest length.
        case recordingLimitReached

        /// Captures are still uploading.
        case capturesUploading

        /// A trophy of the grade was earned.
        case trophyEarned(TrophyGrade)

        /// A game trial is running out; the notice's title is the service's text saying how long is left.
        case trialTimeLeft

        /// A friend invited the player to a game; the notice's title names them and its detail the game.
        case invitation

        /// A friend sent the player a message; the notice's title names them.
        case message
        /// The invitation the stream was started to accept could not be joined; the notice's detail says why.
        case invitationJoinFailed
    }

    /// What the console reported.
    public let kind: Kind

    /// The console's title for the notice, such as a trophy's name, without private-use symbols.
    public let title: String

    /// The console's detail line, without private-use symbols.
    public let detail: String

    /// Describes a notice; the console's private-use symbols are dropped from its text.
    ///
    /// - Parameters:
    ///   - kind: What the console reported.
    ///   - title: The console's title.
    ///   - detail: The console's detail line.
    public init(kind: Kind, title: String = "", detail: String = "") {
        self.kind = kind
        self.title = Self.displayable(title)
        self.detail = Self.displayable(detail)
    }

    /// Whether the notice is an earned trophy.
    public var isTrophy: Bool {
        if case .trophyEarned = kind {
            return true
        }
        return false
    }

    /// How long the toast stays: longest for a trial running out, then a trophy, an invitation or a message,
    /// then anything else.
    public var shownFor: Duration {
        if kind == .trialTimeLeft {
            return .seconds(8)
        }
        return isTrophy || kind == .invitation || kind == .message || kind == .invitationJoinFailed
            ? .seconds(6)
            : .seconds(4)
    }

    /// The toast's first line: a trophy's name or a trial's time left as the service words it, else what happened.
    public var headline: String {
        if isTrophy || kind == .trialTimeLeft, !title.isEmpty {
            return title
        }
        return String(localized: summary)
    }

    /// The toast's further lines.
    public var lines: [String] {
        if isTrophy {
            return title.isEmpty
                ? []
                : [String(localized: summary)]
        }
        if kind == .trialTimeLeft {
            return []
        }
        return [title, detail].filter {
            !$0.isEmpty
        }
    }

    /// The toast's text for VoiceOver, one line per line shown.
    public var announcement: String {
        ([headline] + lines).joined(separator: "\n")
    }

    private var summary: LocalizedStringResource {
        switch kind {
        case .screenshotSaved:
            .cloudNoticeScreenshotSaved
        case .screenshotRefused:
            .cloudNoticeScreenshotRefused
        case .recordingSaved:
            .cloudNoticeRecordingSaved
        case .recordingRefused:
            .cloudNoticeRecordingRefused
        case .recordingPaused:
            .cloudNoticeRecordingPaused
        case .recordingResumed:
            .cloudNoticeRecordingResumed
        case .recordingLimitReached:
            .cloudNoticeRecordingLimitReached
        case .capturesUploading:
            .cloudNoticeCapturesUploading
        case .trophyEarned(let grade):
            grade.earnedSummary
        case .trialTimeLeft:
            .cloudNoticeTrialTimeLeft
        case .invitation:
            .cloudNoticeInvitation
        case .message:
            .cloudNoticeMessage
        case .invitationJoinFailed:
            .cloudNoticeInvitationJoinFailed
        }
    }

    private static func displayable(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter {
            $0.properties.generalCategory != .privateUse
        })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
