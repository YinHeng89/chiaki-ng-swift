import ChiakiModels
import Foundation

/// How far a web sign-in has got, as the capture reports it.
public enum SignInStage: Hashable, Sendable {
    /// The sign-in pages are shown and the user is signing in.
    case browsing(SignInPage)

    /// A page finished loading over a connection secured with this certificate.
    case secured(SignInPage, SignInCertificate)

    /// The user signed in; the NPSSO is being read.
    case completing
}

/// The web sign-in page while it is shown, named by an id the sign-in screen renders.
///
/// State that holds it changes only when a new page opens. The page itself, and the browser that shows it, is
/// owned by the live ``AccountsClient``, which closes it when the capture ends; the screen asks the app for the
/// view that shows the page with this id.
public struct SignInPage: Hashable, Sendable {
    /// The page's id, new for each page opened.
    public let id: UUID

    /// Names a page.
    ///
    /// - Parameter id: The page's id.
    public init(id: UUID) {
        self.id = id
    }
}
