/// The controls the host's invitation card shows for one guest's attempt.
///
/// This is the one list the card renders from and controller navigation moves through.
public enum KakusanInviteControls {
    /// Whether the card is shown for a phase; once a guest is admitted the card gives way to the couch.
    ///
    /// - Parameter phase: Where the attempt is.
    /// - Returns: `true` while the card has something to show.
    public static func shows(_ phase: KakusanHostPhase) -> Bool {
        switch phase {
        case .preparing, .invitation, .connecting, .verifying, .closing, .ended:
            true
        case .admitting, .readying, .active:
            false
        }
    }

    /// The card's controls for a phase.
    ///
    /// - Parameters:
    ///   - phase: Where the attempt is.
    ///   - expectations: The names the host can say the invitation is for; `nil` stands for a new device.
    /// - Returns: The rows, and the control selection starts on.
    public static func grid(for phase: KakusanHostPhase,
                            expectations: [String?]) -> KakusanControlGrid {
        switch phase {
        case .preparing, .connecting:
            KakusanControlGrid([[.close], [.cancel]], preferred: .cancel)
        case .invitation:
            KakusanControlGrid(
                [
                    [.close],
                    [.copy],
                    expectations.map(KakusanControl.expect),
                    [.paste],
                    [.text],
                    [.cancel, .connect]
                ],
                preferred: .copy
            )
        case .verifying:
            KakusanControlGrid([[.code], [.cancel, .verify]])
        case .closing:
            KakusanControlGrid([[.close]])
        case .admitting, .readying, .active, .ended:
            KakusanControlGrid([[.close], [.create]], preferred: .create)
        }
    }
}
