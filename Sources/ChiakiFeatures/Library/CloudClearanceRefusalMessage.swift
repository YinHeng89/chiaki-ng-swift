import ChiakiModels
import Foundation

/// The words the app shows when the catalog refuses to launch a cloud title.
public enum CloudClearanceRefusalMessage {
    /// Why the title cannot be launched, with the price or release time when known.
    ///
    /// - Parameter refusal: The catalog's refusal.
    /// - Returns: One sentence for the player.
    public static func text(for refusal: CloudClearanceRefusal) -> String {
        switch refusal.refusal {
        case .notListed, .hidden:
            return "This title isn’t in the cloud catalog."
        case .buyToStream:
            return "Buy this title on PlayStation Store to stream it\(priced(refusal))."
        case .addToLibrary:
            return "Add this title to your library on PlayStation Store to stream it."
        case .needsPremium:
            return "PlayStation Plus Premium is required to stream this title."
        case .refusedByStreamService:
            return "PlayStation refused to stream this title."
        case .notStreamable:
            return refusal.notice.isEmpty
                ? "This title can’t be streamed."
                : "This title can’t be streamed: \(refusal.notice)"
        case .unannounced:
            return "This pre-order has no release date yet."
        case .notReleased:
            guard let time = refusal.time else {
                return "This title isn’t released yet."
            }
            return "Not released yet: unlocks \(time.formatted(date: .abbreviated, time: .shortened))."
        case .noTrustedClock:
            return "The release time couldn’t be checked against PlayStation’s clock. Try again."
        case .checkUnavailable:
            return refusal.needsSignIn
                ? CloudPlaybackFailureMessage.text(for: .signInRequired)
                : "The ownership check couldn’t be completed. Try again."
        case .invalidTitle:
            return "PlayStation has no record of your copy of this title."
        case .titleTakenDown:
            return "This title has been taken down from cloud streaming."
        case .streamingUnavailable:
            return "Cloud streaming isn’t available for your copy of this title."
        case .purchaseNeeded:
            return "Your copy of this title is no longer active. "
                + "Buy it again on PlayStation Store to stream it\(priced(refusal))."
        case .unexpectedEntitlementState:
            return "PlayStation reports your copy of this title in a state that can’t be streamed."
        case .chooseAGame:
            return "Choose one of the games in this bundle to play."
        }
    }

    private static func priced(_ refusal: CloudClearanceRefusal) -> String {
        refusal.price.isEmpty
            ? ""
            : " (\(refusal.price))"
    }
}
