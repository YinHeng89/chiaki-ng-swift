import ChiakiModels

/// The settings tab that is shown.
///
/// Only the selected tab is mounted, so a tab's appear effects run only while it is shown.
public enum SettingsRoute: CaseIterable, Equatable, Hashable, Sendable {
    /// Stream picture settings, for consoles and the cloud.
    case picture

    /// Sound output, microphone and spatial audio.
    case sound

    /// Controller and keyboard bindings.
    case controls

    /// Library layout and stream diagnostics.
    case interface

    /// PlayStation accessibility settings for cloud streams.
    case accessibility

    /// Discovery, datacenters, internet connection and console power.
    case network

    /// Kakusan guests and media tuning.
    case remotePlayers

    /// Logging and the error report, with Takion versions and developer previews in debug builds.
    case developer

    /// Why each cloud title is or is not offered.
    case entitlements

    /// Cached data the core keeps.
    case caches

    /// Recorded HTTP requests.
    case requests

    /// Held PlayStation tokens.
    case tokens

    /// The unofficial-client notice, the people and projects chiaki-ng thanks, where to reach it and its license.
    case about

    /// The tab's name.
    public var title: String {
        switch self {
        case .picture:
            "Picture"
        case .sound:
            "Sound"
        case .controls:
            "Controls"
        case .interface:
            "Interface"
        case .accessibility:
            "Accessibility"
        case .network:
            "Network"
        case .remotePlayers:
            "Remote players"
        case .developer:
            #if DEBUG
                "Developer"
            #else
                "Logging"
            #endif
        case .entitlements:
            "Entitlements"
        case .caches:
            "Caches"
        case .requests:
            "Requests"
        case .tokens:
            "Tokens"
        case .about:
            "About"
        }
    }

    /// The tab's name when it is shown under its symbol, short enough to fit beneath it.
    public var shortTitle: String {
        switch self {
        case .remotePlayers:
            "Players"
        case .accessibility:
            "Access"
        case .entitlements:
            "Entitled"
        case .picture, .sound, .controls, .interface, .network, .developer, .caches, .requests, .tokens,
             .about:
            title
        }
    }

    /// The SF Symbol that stands for the tab.
    public var symbol: String {
        switch self {
        case .picture:
            "display"
        case .sound:
            "speaker.wave.2"
        case .controls:
            "gamecontroller"
        case .interface:
            "sidebar.left"
        case .accessibility:
            "accessibility"
        case .network:
            "network"
        case .remotePlayers:
            "person.2"
        case .developer:
            "doc.text"
        case .entitlements:
            "checkmark.seal"
        case .caches:
            "internaldrive"
        case .requests:
            "arrow.left.arrow.right"
        case .tokens:
            "key"
        case .about:
            "info.circle"
        }
    }

    /// Whether the tab only applies to an account signed in to PlayStation Network.
    public var needsPSN: Bool {
        switch self {
        case .accessibility, .entitlements, .tokens:
            true
        case .picture, .sound, .controls, .interface, .network, .remotePlayers, .developer, .caches,
             .requests, .about:
            false
        }
    }

    /// Whether this build has what the tab configures: Remote players needs Kakusan.
    public var isBuilt: Bool {
        switch self {
        case .remotePlayers:
            KakusanBuild.included
        case .picture, .sound, .controls, .interface, .accessibility, .network, .developer, .entitlements,
             .caches, .requests, .tokens, .about:
            true
        }
    }

    /// Whether the tab inspects the app's internals, so only debug builds show it.
    public var isDeveloperTool: Bool {
        switch self {
        case .entitlements, .caches, .requests, .tokens:
            true
        case .picture, .sound, .controls, .interface, .accessibility, .network, .remotePlayers, .developer,
             .about:
            false
        }
    }

    /// The tabs shown for a PlayStation Network reach, in order.
    ///
    /// - Parameter reach: Whether any account is signed in to PlayStation Network.
    /// - Returns: Every tab this build has, without the PSN-only ones while no account is signed in, and
    ///   without the developer tools in release builds.
    public static func shown(for reach: PSNReach) -> [SettingsRoute] {
        allCases.filter { route in
            #if DEBUG
                let developerToolsShown = true
            #else
                let developerToolsShown = false
            #endif
            return route.isBuilt && (reach == .signedIn || !route.needsPSN)
                && (developerToolsShown || !route.isDeveloperTool)
        }
    }

    /// Whether the page draws its own title instead of the shared page title.
    public var drawsOwnTitle: Bool {
        switch self {
        case .picture, .controls, .about:
            true
        case .sound, .interface, .accessibility, .network, .remotePlayers, .developer, .entitlements, .caches,
             .requests, .tokens:
            false
        }
    }

    /// The widest every page is laid out, in points; every tab shares it, so switching tabs never resizes the
    /// panel or the tab bar.
    public static let pageWidth: Double = 1180
}
