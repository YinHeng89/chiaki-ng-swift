/// The controls the guest's card shows in each phase.
///
/// This is the one list the card renders from and controller navigation moves through. Back to the library is
/// the stream chrome's own button, outside the card, so it is never one of these controls.
public enum KakusanGuestControls {
    /// The card's controls for a phase.
    ///
    /// - Parameters:
    ///   - phase: Where the join is.
    ///   - canRemember: Whether the verified host can be remembered.
    /// - Returns: The rows, and the control selection starts on.
    public static func grid(for phase: KakusanGuestPhase, canRemember: Bool) -> KakusanControlGrid {
        let remember: [[KakusanControl]] = canRemember
            ? [[.remember]]
            : []
        switch phase {
        case .idle, .previewing, .leaving, .streaming:
            return KakusanControlGrid()
        case .entering:
            return KakusanControlGrid([[.text], [.paste, .connect]], preferred: .paste)
        case .previewed, .disclosureAccepted:
            return KakusanControlGrid([[.accept], [.back, .create]])
        case .preparingReply, .connecting:
            return KakusanControlGrid([[.leave]])
        case .waitingForHost:
            return KakusanControlGrid([[.copy], [.leave]])
        case .verifying:
            return KakusanControlGrid([[.code], [.leave, .verify]])
        case .admitting, .readying:
            return KakusanControlGrid(remember + [[.leave]])
        case .ended:
            return KakusanControlGrid(remember + [[.create]])
        }
    }

    /// Whether leaving in a phase asks first, because it would end a session the host already knows about.
    ///
    /// - Parameter phase: Where the join is.
    /// - Returns: `true` when leaving needs confirming.
    public static func confirmsLeave(_ phase: KakusanGuestPhase) -> Bool {
        switch phase {
        case .preparingReply, .waitingForHost, .connecting, .verifying, .admitting, .readying:
            true
        case .idle, .entering, .previewing, .previewed, .disclosureAccepted, .streaming, .leaving, .ended:
            false
        }
    }
}
