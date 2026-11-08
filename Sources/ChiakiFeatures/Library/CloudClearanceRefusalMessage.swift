import ChiakiModels
import Foundation

/// The words the app shows when the catalog refuses to launch a cloud title.
public enum CloudClearanceRefusalMessage {
    /// Why the title cannot be launched, with the price or release time when known.
    ///
    /// - Parameter refusal: The catalog's refusal.
    /// - Returns: One sentence for the player.
    public static func text(for refusal: CloudClearanceRefusal) -> LocalizedStringResource {
        switch refusal.refusal {
        case .notListed, .hidden:
            return .libraryRefusalNotListed
        case .buyToStream:
            return refusal.price.isEmpty
                ? .libraryRefusalBuyToStream
                : .libraryRefusalBuyToStreamPrice(price: refusal.price)
        case .addToLibrary:
            return .libraryRefusalAddToLibrary
        case .needsPremium:
            return .libraryRefusalNeedsPremium
        case .refusedByStreamService:
            return .libraryRefusalRefusedByStreamService
        case .notStreamable:
            return refusal.notice.isEmpty
                ? .libraryRefusalNotStreamable
                : .libraryRefusalNotStreamableNotice(notice: refusal.notice)
        case .unannounced:
            return .libraryRefusalUnannounced
        case .notReleased:
            guard let time = refusal.time else {
                return .libraryRefusalNotReleased
            }
            let unlock = time.formatted(date: .abbreviated, time: .shortened)
            return .libraryRefusalNotReleasedUntil(time: unlock)
        case .noTrustedClock:
            return .libraryRefusalNoTrustedClock
        case .checkUnavailable:
            return refusal.needsSignIn
                ? CloudPlaybackFailureMessage.text(for: .signInRequired)
                : .libraryRefusalCheckUnavailable
        case .invalidTitle:
            return .libraryRefusalInvalidTitle
        case .titleTakenDown:
            return .libraryRefusalTitleTakenDown
        case .streamingUnavailable:
            return .libraryRefusalStreamingUnavailable
        case .purchaseNeeded:
            return refusal.price.isEmpty
                ? .libraryRefusalPurchaseNeeded
                : .libraryRefusalPurchaseNeededPrice(price: refusal.price)
        case .unexpectedEntitlementState:
            return .libraryRefusalUnexpectedEntitlementState
        case .chooseAGame:
            return .libraryRefusalChooseAGame
        }
    }
}
