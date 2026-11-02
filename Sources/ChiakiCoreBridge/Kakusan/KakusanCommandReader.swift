import ChiakiBridge
import ChiakiModels
import Foundation

/// Reads the core's answers to Kakusan commands sent to a running stream.
public enum KakusanCommandReader {
    /// The outcome of a command.
    ///
    /// - Parameter outcome: The core's answer.
    /// - Returns: Accepted, or the error the command was refused with.
    public static func outcome(of outcome: chiaki_bridge
        .KakusanCommandOutcome) -> KakusanCommandOutcome {
        guard let error = error(of: outcome) else {
            return .accepted
        }
        return .rejected(error)
    }

    /// The guest a command that names one answered with.
    ///
    /// - Parameter outcome: The core's answer.
    /// - Returns: The guest, or the failure; an accepted answer without a valid id is
    ///   `ChiakiModels/KakusanError/internal`.
    public static func guest(of outcome: chiaki_bridge.KakusanCommandOutcome)
        -> Result<KakusanGuestID, KakusanError> {
        if let error = error(of: outcome) {
            return .failure(error)
        }
        guard let guest = KakusanGuestID(Data(outcome.guest())) else {
            return .failure(.internal)
        }
        return .success(guest)
    }

    /// The result of remembering or renaming a device in a running stream.
    ///
    /// - Parameter outcome: The core's answer.
    /// - Returns: The saved device or the device already holding the nickname, or the failure.
    public static func remembered(of outcome: chiaki_bridge.RememberOutcome)
        -> Result<KakusanRememberResult, KakusanError> {
        Result { () throws(KakusanError) in
            try KakusanDevicesBridge.rememberResult(of: outcome)
        }
    }

    /// The model error a core refusal stands for when a stream reports it.
    ///
    /// - Parameter refused: The core's refusal.
    /// - Returns: The error; an argument the bridge rejected is `ChiakiModels/KakusanError/internal`.
    public static func error(of refused: libchiaking.kakusan.Refusal.Kind) -> KakusanError {
        refused == .invalid_argument
            ? .internal
            : KakusanDevicesBridge.error(refused)
    }

    /// The model error a bridge refusal stands for.
    ///
    /// - Parameter refusal: Why the bridge refused.
    /// - Returns: The error.
    public static func error(of refusal: chiaki_bridge.KakusanCommandRefusal) -> KakusanError {
        switch refusal {
        case .not_armed:
            .internal
        case .core_closed:
            .cryptoUnavailable
        }
    }

    private static func error(of outcome: chiaki_bridge.KakusanCommandOutcome) -> KakusanError? {
        switch outcome.kind() {
        case .accepted:
            nil
        case .declined:
            error(of: outcome.decline())
        case .refused:
            error(of: outcome.refusal())
        }
    }
}
