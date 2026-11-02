import ChiakiBridge
import ChiakiModels
import CxxStdlib

/// Reads the notices a cloud server shows during a stream into `CloudSystemNotice` and
/// `CloudClosingNotice`.
public enum CloudNoticeReader {
    /// The model notice of a core notice.
    ///
    /// - Parameter notice: What the server reported.
    /// - Returns: The notice.
    public static func notice(of notice: libchiaking.play.CloudNotice) -> CloudSystemNotice {
        CloudSystemNotice(
            kind: kind(of: notice.kind, grade: notice.grade),
            title: String(notice.title),
            detail: String(notice.detail)
        )
    }

    /// The closing notice for the time a server says is left.
    ///
    /// - Parameters:
    ///   - minutes: The minutes left.
    ///   - limit: Why the game closes.
    /// - Returns: The notice.
    public static func closing(minutes: Int, limit: libchiaking.play.PlayTimeLimit) -> CloudClosingNotice {
        CloudClosingNotice(minutes: minutes, reason: reason(of: limit))
    }

    private static func reason(of limit: libchiaking.play.PlayTimeLimit) -> CloudClosingNotice.Reason {
        switch limit {
        case .session_limit:
            .timeLimit
        case .maintenance:
            .maintenance
        case .other:
            .unexplained
        }
    }

    private static func kind(
        of kind: libchiaking.play.CloudNoticeKind,
        grade: libchiaking.play.TrophyGrade
    ) -> CloudSystemNotice.Kind {
        switch kind {
        case .screenshot_saved:
            .screenshotSaved
        case .screenshot_refused:
            .screenshotRefused
        case .recording_saved:
            .recordingSaved
        case .recording_refused:
            .recordingRefused
        case .recording_paused:
            .recordingPaused
        case .recording_resumed:
            .recordingResumed
        case .recording_limit_reached:
            .recordingLimitReached
        case .captures_uploading:
            .capturesUploading
        case .trophy_earned:
            .trophyEarned(trophy(of: grade))
        case .trial_time_left:
            .trialTimeLeft
        }
    }

    private static func trophy(of grade: libchiaking.play.TrophyGrade) -> CloudSystemNotice.TrophyGrade {
        switch grade {
        case .bronze:
            .bronze
        case .silver:
            .silver
        case .gold:
            .gold
        case .platinum:
            .platinum
        }
    }
}
