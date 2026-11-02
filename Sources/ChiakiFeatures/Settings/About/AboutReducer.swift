import ChiakiAssets
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Drives the About settings page: reads the core's build and the bundled contributor list when the page
/// appears, and opens the page's links.
@Reducer public struct AboutReducer {
    /// A place the page links to.
    public enum Link: Equatable, Sendable, CaseIterable {
        /// The chiaki-ng organisation on GitHub.
        case github
        /// The chiaki-ng Discord server.
        case discord
        /// The maintainer's email address.
        case email
        /// The original Chiaki by thestr4ng3r.
        case originalChiaki
        /// Pylux by Forward Technologies LLC.
        case pylux
        /// Pxplay by grill2010.
        case pxplay
        /// Cloudpad by Chaz.
        case cloudpad
        /// akira by xlanor.
        case akira
        /// Street Pea, the lead maintainer, on GitHub.
        case leadMaintainer
        /// The privacy policy.
        case privacyPolicy

        /// Where the link goes.
        public var url: URL {
            switch self {
            case .github:
                URL(string: "https://github.com/chiaki-ng")!
            case .discord:
                URL(string: "https://discord.gg/tAMbRuwXDH")!
            case .email:
                URL(string: "mailto:streetpea@proton.me")!
            case .originalChiaki:
                URL(string: "https://git.sr.ht/~thestr4ng3r/chiaki")!
            case .pylux:
                URL(string: "https://github.com/ForWard-Technologies-LLC/Pylux")!
            case .pxplay:
                URL(string: "https://streamingdv.github.io/pxplay/")!
            case .cloudpad:
                URL(string: "https://github.com/Chazq2023/CloudPad-Android")!
            case .akira:
                URL(string: "https://github.com/chiaki-ng/akira")!
            case .leadMaintainer:
                URL(string: "https://github.com/streetpea")!
            case .privacyPolicy:
                URL(string: "https://github.com/chiaki-ng/chiaki-ng-swift/blob/main/PRIVACY.md")!
            }
        }
    }

    /// What the page shows.
    @ObservableState public struct State: Equatable {
        /// The core's version and commit, once read.
        public var coreBuild: CoreBuild?

        /// Everyone who contributed to chiaki-ng, from the bundled list, once read.
        public var contributors: [String] = []

        /// Whether the contributor list is unfolded under its heading.
        public var contributorsShown = false

        /// Creates the page's state before anything is read.
        public init() {}
    }

    /// Everything the page reacts to.
    public enum Action: Equatable, Sendable {
        /// The page appeared: reads the core's build and the contributor list.
        case load

        /// The core's build and the contributor list were read.
        case loaded(CoreBuild, [String])

        /// Opens a link.
        case open(Link)

        /// Opens a contributor's GitHub profile by login.
        case openContributor(String)

        /// Unfolds or folds the contributor list.
        case toggleContributors
    }

    @Dependency(\.settings) private var settings
    @Dependency(\.openURL) private var openURL

    /// Creates the reducer.
    public init() {}

    /// The bundled list of chiaki-ng contributors, one login per line, in the order the page shows them.
    public static var bundledContributors: [String] {
        guard let url = ChiakiAssets.licensesURL?.appending(path: "Attributions/chiaki-ng-CONTRIBUTORS.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).map { line in
            line.trimmingCharacters(in: .whitespaces)
        }.filter { line in
            !line.isEmpty
        }
    }

    /// The GitHub profile of a contributor.
    ///
    /// - Parameter login: The contributor's GitHub login.
    /// - Returns: The profile's address, or `nil` when the login is not a plain GitHub login.
    public static func profileURL(of login: String) -> URL? {
        let allowed = login.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-"
        }
        guard !login.isEmpty, allowed else {
            return nil
        }
        return URL(string: "https://github.com/\(login)")
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                return .run { [settings] send in
                    await send(.loaded(settings.coreBuild(), Self.bundledContributors))
                }
            case let .loaded(build, contributors):
                state.coreBuild = build
                state.contributors = contributors
                return .none
            case .open(let link):
                return .run { [openURL] _ in
                    await openURL(link.url)
                }
            case .openContributor(let login):
                guard let url = Self.profileURL(of: login) else {
                    return .none
                }
                return .run { [openURL] _ in
                    await openURL(url)
                }
            case .toggleContributors:
                state.contributorsShown.toggle()
                return .none
            }
        }
    }
}
