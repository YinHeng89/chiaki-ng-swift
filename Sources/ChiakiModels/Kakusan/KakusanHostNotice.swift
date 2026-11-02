/// Something the host tells the couch about a remote player, shown as a short notice.
public enum KakusanHostNotice: Equatable, Sendable {
    /// An invitation ended before anyone connected.
    case invitationEnded(KakusanAttemptOutcome)

    /// A connected player's attempt ended.
    case ended(name: String?, KakusanAttemptOutcome)

    /// No seat was free for another local player.
    case noFreeSeat

    /// A command to the shared session was refused.
    case commandFailed(KakusanError)
}
