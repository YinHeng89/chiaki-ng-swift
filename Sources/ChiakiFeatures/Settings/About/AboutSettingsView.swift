import ChiakiAssets
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The About settings page: the app and core versions, the unofficial-client notice, the people and projects
/// chiaki-ng thanks, the Discord server, the contact address, the license and the privacy policy.
public struct AboutSettingsView: View {
    /// The About reducer the page reads and sends actions to.
    public let store: StoreOf<AboutReducer>
    @Environment(\.screenLayout) private var layout

    /// Creates an About settings view.
    ///
    /// - Parameter store: The About reducer the page reads and sends actions to.
    public init(store: StoreOf<AboutReducer>) {
        self.store = store
    }

    /// The page.
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            versions
            UnofficialClientNotice()
            maintainer
            social
            thanks
            license
            privacy
        }
    }

    private static let discordMark = brandMark("discord-white")
    private static let githubMark = brandMark("github-white")

    private static func brandMark(_ name: String) -> PlatformImage? {
        ChiakiAssets.url(forResource: name, withExtension: "png").flatMap { url in
            PlatformImage(contentsOf: url)
        }
    }

    private var versions: some View {
        HStack(alignment: .top, spacing: 28) {
            figure(.settingsAboutVersion, AppVersion.display())
            figure(.settingsAboutCore, core)
            figure(.settingsAboutLicense, "AGPL-3.0")
        }
        .padding(.top, 4)
    }

    private var core: String {
        guard let build = store.coreBuild, !build.version.isEmpty else {
            return "chiaki-ng-core"
        }
        return build.commit.isEmpty
            ? "chiaki-ng-core \(build.version)"
            : "chiaki-ng-core \(build.version) (\(build.commit))"
    }

    private func figure(_ label: LocalizedStringResource, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }

    private var thanks: some View {
        SettingsCard(.settingsAboutThanksTitle) {
            Text(.settingsAboutThanksDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(Self.projects, id: \.name) { project in
                self.project(project.name, author: project.author, note: project.note, link: project.link)
                Divider()
            }
            contributors
        }
    }

    /// The affiliated projects the About page thanks, in the order it lists them.
    static let projects = [
        AboutProject(name: "thestr4ng3r", note: .settingsAboutNoteOriginalChiaki, link: .originalChiaki),
        AboutProject(name: "Chiaki-TV", author: "TechAntoHere", note: .settingsAboutNoteToBeReleased),
        AboutProject(name: "Pylux", author: "Forward Technologies LLC", link: .pylux),
        AboutProject(name: "Pxplay", author: "grill2010", link: .pxplay),
        AboutProject(name: "Cloudpad", author: "Chaz", link: .cloudpad),
        AboutProject(name: "akira", author: "xlanor", link: .akira),
    ]

    private func project(
        _ name: String, author: String? = nil, note: LocalizedStringResource? = nil, link: AboutReducer.Link?
    ) -> some View {
        HStack(spacing: 6) {
            if let link {
                self.link(Text(name), link, hint: .settingsAboutProjectHint)
            } else {
                Text(name)
                    .font(.callout.weight(.semibold))
            }
            if let author {
                byline(author)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
    }

    private func byline(_ author: String) -> Text {
        var line = AttributedString(localized: .settingsAboutProjectBy(author: author))
        if let range = line.range(of: author) {
            line[range].swiftUI.font = .callout.weight(.medium)
            line[range].swiftUI.foregroundColor = Palette.accent
        }
        return Text(line)
    }

    private var contributors: some View {
        VStack(alignment: .leading, spacing: 10) {
            FocusButton {
                store.send(.toggleContributors)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(store.contributorsShown
                            ? .degrees(90)
                            : .zero)
                    Text(.settingsAboutAllContributors)
                        .font(.callout)
                    Text("\(store.contributors.count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusHighlightShape(.roundedRectangle(8))
            .accessibilityLabel(store.contributorsShown
                ? .settingsAboutHideContributors
                : .settingsAboutShowContributors)
            if store.contributorsShown {
                WrappingRow(spacing: 6) {
                    ForEach(store.contributors, id: \.self) { login in
                        FocusButton {
                            store.send(.openContributor(login))
                        } label: {
                            Text(login)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Palette.accent.opacity(0.12), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusHighlightShape(.capsule)
                        .accessibilityHint(.settingsAboutContributorHint)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.contributorsShown)
    }

    private func link(_ name: Text, _ link: AboutReducer.Link, hint: LocalizedStringResource) -> some View {
        FocusButton {
            store.send(.open(link))
        } label: {
            name
                .font(.callout.weight(.semibold))
                .underline()
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(6))
        .accessibilityHint(hint)
    }

    private var maintainer: some View {
        SettingsCard(.settingsAboutLeadMaintainer) {
            HStack(spacing: 6) {
                link(Text(verbatim: "Street Pea"), .leadMaintainer, hint: .settingsAboutMaintainerHint)
                Text(verbatim: "github.com/streetpea")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 30)
        }
    }

    private var social: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                discord
                github
                contact
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 16) {
                discord
                github
                contact
            }
        }
    }

    private var discord: some View {
        tile(
            mark: mark(
                Self.discordMark,
                tint: Self.discordBlue,
                fallback: "bubble.left.and.bubble.right.fill"
            ),
            title: .settingsAboutDiscordTitle, button: .settingsAboutDiscordButton, link: .discord
        ) {
            Text(.settingsAboutDiscordDetail)
        }
    }

    private var github: some View {
        tile(
            mark: mark(
                Self.githubMark,
                tint: Self.githubBlack,
                fallback: "chevron.left.forwardslash.chevron.right"
            ),
            title: .settingsAboutGithubTitle, button: .settingsAboutGithubButton, link: .github
        ) {
            Text(.settingsAboutGithubDetail)
        }
    }

    private var contact: some View {
        tile(
            mark: mark(nil, tint: Color.primary.opacity(0.08), fallback: "envelope"),
            title: .settingsAboutContactTitle, button: .settingsAboutContactButton, link: .email
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "streetpea@proton.me")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text(.settingsAboutContactPreference)
                    .font(.caption)
            }
        }
    }

    private func tile(
        mark: some View,
        title: LocalizedStringResource,
        button: LocalizedStringResource,
        link: AboutReducer.Link,
        @ViewBuilder detail: () -> some View
    ) -> some View {
        let radius = GlassPanel.Radius.small
        let shown = detail()
        return FocusButton {
            store.send(.open(link))
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    mark
                    Text(title)
                        .font(.headline)
                }
                shown
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .padding(17)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(AppGlass.panel, in: .rect(cornerRadius: radius.points))
            .contentShape(radius.shape)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(radius.points))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(title)
        .accessibilityHint(button)
    }

    private func mark(_ image: PlatformImage?, tint: Color, fallback: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint)
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private static var discordBlue: Color {
        Color(red: 0.345, green: 0.396, blue: 0.949)
    }

    private static var githubBlack: Color {
        Color(red: 0.14, green: 0.16, blue: 0.18)
    }

    private var license: some View {
        SettingsCard(.settingsAboutLicense) {
            Text(.settingsAboutLicenseDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacy: some View {
        SettingsCard(.settingsAboutPrivacy) {
            VStack(alignment: .leading, spacing: 8) {
                Text(.settingsAboutPrivacyDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                link(
                    Text(.settingsAboutPrivacyPolicy),
                    .privacyPolicy,
                    hint: .settingsAboutPrivacyPolicyHint
                )
            }
        }
    }
}

/// Lays its children out left to right and starts a new line when the next one would not fit.
struct WrappingRow: Layout {
    /// The gap between neighbours on a line and between lines.
    let spacing: CGFloat

    /// The size the lines take within the proposed width.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite
            ? width
            : widest, height: y + lineHeight)
    }

    /// Places each child on the first line it fits.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// An affiliated project the About page thanks: its name, who made it, a note and its page.
struct AboutProject {
    /// The project's name.
    let name: String

    /// Who made it, when credited.
    var author: String?

    /// A note shown after it.
    var note: LocalizedStringResource?

    /// Its page, when it has one.
    var link: AboutReducer.Link?
}
