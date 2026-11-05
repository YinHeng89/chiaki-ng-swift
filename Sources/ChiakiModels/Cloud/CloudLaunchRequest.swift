import Foundation

/// A validated request to stream a cloud title for an account, optionally carrying the catalog's launch
/// clearance.
public struct CloudLaunchRequest: Equatable, Sendable {
    /// The account that streams the title.
    public let accountID: UUID

    /// The title to stream.
    public let game: CloudGame

    /// The catalog's clearance for this launch, or `nil` before the title is cleared.
    public private(set) var clearance: CloudLaunchClearanceToken?

    /// The game invitation the stream joins once it plays, when the title was launched to accept one.
    public var joining: CloudGameInvitation?

    /// Creates a request after checking the title is a PS Now or PS Cloud title with a product ID.
    ///
    /// - Parameters:
    ///   - accountID: The streaming account.
    ///   - game: The title.
    ///   - clearance: The catalog's clearance, if already obtained.
    ///   - joining: The game invitation to join once the stream plays, if any.
    /// - Throws: ``CloudPlaybackFailure/invalidTitle`` when the title cannot be launched in the cloud, or when
    ///   it is a PS Cloud title and ``PS5CloudLaunchBuild/included`` is `false`.
    public init(
        accountID: UUID,
        game: CloudGame,
        clearance: CloudLaunchClearanceToken? = nil,
        joining: CloudGameInvitation? = nil
    ) throws(CloudPlaybackFailure) {
        guard ["psnow", "pscloud"].contains(game.streamServiceType), !game.productId.isEmpty else {
            throw .invalidTitle
        }
        guard game.streamServiceType != "pscloud" || PS5CloudLaunchBuild.included else {
            throw .invalidTitle
        }
        self.accountID = accountID
        self.game = game
        self.clearance = clearance
        self.joining = joining
    }

    /// Returns a copy carrying a different clearance.
    ///
    /// - Parameter launch: The new clearance, or `nil` to drop it.
    /// - Returns: The updated request.
    public func cleared(by launch: CloudLaunchClearanceToken?) -> CloudLaunchRequest {
        var request = self
        request.clearance = launch
        return request
    }

    /// A copy with the clearance removed.
    public var uncleared: CloudLaunchRequest {
        cleared(by: nil)
    }
}

/// Why a cloud stream could not start or continue.
public enum CloudPlaybackFailure: Error, Equatable, Sendable {
    /// The title has no valid launch information, sign-in is needed, a previous stream is still closing, the
    /// video player failed, the connection timed out, or the video surface went away.
    case invalidTitle, signInRequired, busy, renderer, timedOut, surfaceLost

    /// The stream ended with a core outcome.
    case stream(StreamOutcome)

    /// PlayStation refused the launch, with the message to show.
    case refused(String)

    /// The title is not released yet, with when it unlocks.
    case notReleased(String)

    /// The title cannot be streamed, with PlayStation's reason.
    case notStreamable(String)
}
