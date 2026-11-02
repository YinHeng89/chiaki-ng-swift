import ChiakiDiagnostics
import ChiakiModels
import Foundation

/// The diagnostic lines written while a console is paired.
public enum PairingLog {
    /// What is being paired, as the subject of a sentence.
    ///
    /// - Parameter target: The console and how it is reached.
    /// - Returns: A phrase such as `"PIN registration of a PS5 at 192.0.2.4"`.
    public static func target(_ target: PairingTarget) -> String {
        let kind = target.kind == .ps5
            ? "PS5"
            : "PS4"
        switch target {
        case .atHome(let address, _):
            return "PIN registration of a \(kind) at \(address)"
        case .overInternet(let console):
            return "PSN registration of a \(kind) via PSN device \(LogFormat.hexPrefix(Data(console.deviceUID.bytes)))"
        }
    }

    /// The line written when an attempt starts.
    ///
    /// - Parameters:
    ///   - target: The console being paired.
    ///   - account: How the account is named in the log.
    /// - Returns: The line.
    public static func started(_ target: PairingTarget, for account: String) -> String {
        let named: String =
            if case .overInternet(let console) = target {
                ", console \"\(console.name)\""
            } else {
                ""
            }
        return "\(capitalised(self.target(target))) for \(account) started\(named)"
    }

    /// The line written when an attempt ends.
    ///
    /// - Parameters:
    ///   - target: The console that was being paired.
    ///   - result: The paired console or why the attempt failed.
    ///   - elapsed: How long the attempt ran.
    ///   - account: How the account is named in the log.
    /// - Returns: The line.
    public static func ended(
        _ target: PairingTarget,
        _ result: Result<PairedConsole, PairingFailure>,
        elapsed: Duration,
        for account: String
    ) -> String {
        let milliseconds = LogFormat.milliseconds(elapsed)
        switch result {
        case .success(let console):
            return "\(capitalised(self.target(target))) succeeded in \(milliseconds) ms: console \"\(console.name)\" "
                + "MAC \(LogFormat.mac(console.hardwareID.data)); saved for \(account)"
        case .failure(let failure):
            return "\(capitalised(self.target(target))) failed after \(milliseconds) ms: \(reason(failure))"
        }
    }

    /// Why an attempt failed, in words that help someone reading the log.
    ///
    /// - Parameter failure: The failure.
    /// - Returns: The reason.
    public static func reason(_ failure: PairingFailure) -> String {
        switch failure {
        case .overInternet(let stage, code: let code?):
            "during \(PairingFailureMessage.name(of: stage)): \(describe(code: code))"
        case .overInternet(let stage, code: nil):
            "during \(PairingFailureMessage.name(of: stage))"
        case .rejected:
            "the console refused the registration or its reply could not be read; a wrong or expired PIN is the "
                + "usual cause"
        case .unreachable:
            "the console did not answer or its address could not be reached"
        case .invalidInput:
            "the request was invalid before anything was sent (address, PIN or PSN token)"
        case .unavailable:
            "the core was not open or cannot pair this way"
        case .notSaved:
            "the pairing could not be saved"
        case .sessionPlaying:
            "a session is playing"
        case .cancelled:
            "cancelled"
        }
    }

    /// Names a code PSN or the console returned.
    ///
    /// - Parameter code: An HTTP status or a console or service reason.
    /// - Returns: The code with what kind of code it is.
    public static func describe(code: Int) -> String {
        (100...599).contains(code)
            ? "HTTP \(code) from the PSN service"
            : "console or service reason \(code)"
    }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
