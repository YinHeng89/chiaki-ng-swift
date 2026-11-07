import Foundation

/// The answer of the store page check on whether one edition of a game streams from the cloud on PS5.
public enum CloudCardCheck: Equatable, Sendable {
    /// The check is still running.
    case checking
    /// The store page lists the edition for cloud streaming, so playing is allowed.
    case streams
    /// The store page does not list the edition for cloud streaming.
    case notStreamable
    /// The stream server refused the game when it was launched.
    case refused
    /// The check could not get an answer, with the reason shown to the player.
    case unavailable(Unavailable)

    /// Why the store page check could not get an answer.
    public enum Unavailable: Equatable, Sendable {
        /// The account has no usable PSN sign-in.
        case noSignIn

        /// The store page did not answer.
        case noAnswer

        /// The edition was not in the store's answer.
        case editionMissing

        /// The store publishes no streaming notice for the edition.
        case noNotice

        /// The sentence shown to the player.
        public var message: LocalizedStringResource {
            switch self {
            case .noSignIn:
                .cloudCardCheckNoSignIn
            case .noAnswer:
                .cloudCardCheckNoAnswer
            case .editionMissing:
                .cloudCardCheckEditionMissing
            case .noNotice:
                .cloudCardCheckNoNotice
            }
        }
    }

    /// Whether the check lets the game be played, which is only the case once the store page confirms
    /// streaming.
    public var allowsPlay: Bool {
        self == .streams
    }

    /// Whether a game needs the store page check before it can be played.
    ///
    /// - Parameter game: The game about to be offered for play.
    /// - Returns: `true` when the catalog leaves the game's streaming support for the store page to confirm.
    public static func needed(for game: CloudGame) -> Bool {
        game.needsStorefrontCheck
    }

    /// Whether the check has an answer that asking again would not change.
    public var isSettled: Bool {
        switch self {
        case .checking, .unavailable:
            false
        case .streams, .notStreamable, .refused:
            true
        }
    }

    /// Maps the store page's streaming answer onto a check result, turning a missing edition or notice into
    /// an unavailable answer.
    ///
    /// - Parameter streaming: The streaming answer parsed from the store page.
    public init(_ streaming: StorefrontCheck.Streaming) {
        switch streaming {
        case .streams:
            self = .streams
        case .notStreamable:
            self = .notStreamable
        case .editionMissing:
            self = .unavailable(.editionMissing)
        case .noNotice:
            self = .unavailable(.noNotice)
        }
    }
}

/// The answer of the signed-in store page check for one cloud game: whether its edition streams, and whether
/// the store still offers the account a trial of it.
public struct CloudStoreCheck: Equatable, Sendable {
    /// Whether the edition streams, as the game's card shows it.
    public let card: CloudCardCheck

    /// Whether the store offers the account a trial of the game, or `nil` when the store gave no answer.
    public let offersTrial: Bool?

    /// Describes a store page check.
    ///
    /// - Parameters:
    ///   - card: Whether the edition streams.
    ///   - offersTrial: Whether the store offers a trial, or `nil` without an answer.
    public init(card: CloudCardCheck, offersTrial: Bool? = nil) {
        self.card = card
        self.offersTrial = offersTrial
    }
}

/// What the storefront says about streaming one title.
public struct StorefrontCheck: Equatable, Sendable {
    /// Whether the storefront says the title streams.
    public enum Streaming: Equatable, Sendable, CaseIterable {
        /// The title streams.
        case streams

        /// The storefront marks the title as not streamable.
        case notStreamable

        /// The storefront gives no notice either way.
        case noNotice

        /// The edition the account holds is missing from the storefront.
        case editionMissing
    }

    /// Whether the title streams.
    public let streaming: Streaming

    /// Whether the storefront says the account owns the title.
    public let ownedPerStore: Bool

    /// Whether the storefront offers adding the title to the library.
    public let offersLibraryAdd: Bool

    /// Whether the storefront offers the account a timed game trial of the title, which it stops doing once the
    /// account has used the trial, or `nil` when the storefront's answer matched no edition of the title.
    public let offersTrial: Bool?

    /// The storefront's notice, or an empty string.
    public let notice: String

    /// Describes a storefront answer.
    ///
    /// - Parameters:
    ///   - streaming: Whether it streams.
    ///   - ownedPerStore: Whether the store says it is owned.
    ///   - offersLibraryAdd: Whether the store offers a library add.
    ///   - notice: The store's notice.
    ///   - offersTrial: Whether the store offers the account a timed game trial, or `nil` without a matching
    ///     edition.
    public init(
        streaming: Streaming,
        ownedPerStore: Bool,
        offersLibraryAdd: Bool,
        notice: String,
        offersTrial: Bool? = nil
    ) {
        self.streaming = streaming
        self.ownedPerStore = ownedPerStore
        self.offersLibraryAdd = offersLibraryAdd
        self.notice = notice
        self.offersTrial = offersTrial
    }
}
