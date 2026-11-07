import ChiakiAssets
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The touch About page: the app and core versions, the unofficial-client notice, the lead maintainer, the
/// Discord server, GitHub and the contact address, beside the projects and contributors chiaki-ng thanks and the
/// license.
struct MobileAboutSettingsPage: View {
    /// The settings.
    let settings: StoreOf<SettingsFeature>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    var body: some View {
        MobileSettingsForm {
            versions
            notice
            maintainer
            social
        } trailing: {
            thanks
            license
        }
        .onAppear {
            settings.send(.about(.load))
        }
    }

    private static let discordMark = brandMark("discord-white")
    private static let githubMark = brandMark("github-white")

    private static func brandMark(_ name: String) -> PlatformImage? {
        ChiakiAssets.url(forResource: name, withExtension: "png").flatMap { url in
            PlatformImage(contentsOf: url)
        }
    }

    private static var discordBlue: Color {
        Color(red: 0.345, green: 0.396, blue: 0.949)
    }

    private static var githubBlack: Color {
        Color(red: 0.14, green: 0.16, blue: 0.18)
    }

    private var store: StoreOf<AboutReducer> {
        settings.scope(state: \.about, action: \.about)
    }

    private var versions: some View {
        MobileSettingsGroup {
            MobileValueRow(.mobileAboutVersion, verbatim: AppVersion.display())
            MobileValueRow(.mobileAboutCore, verbatim: core)
            MobileValueRow(.mobileAboutLicense, verbatim: "AGPL-3.0")
        }
    }

    private var core: String {
        guard let build = store.coreBuild, !build.version.isEmpty else {
            return "libchiaki"
        }
        return build.commit.isEmpty
            ? "libchiaki \(build.version)"
            : "libchiaki \(build.version) (\(build.commit))"
    }

    private var notice: some View {
        MobileSettingsGroup {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 29, height: 29)
                    .background(Color.orange, in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(UnofficialClientNotice<EmptyView>.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(UnofficialClientNotice<EmptyView>.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .mobileRowPadding()
            .accessibilityElement(children: .contain)
        }
    }

    private var maintainer: some View {
        MobileSettingsGroup(.mobileAboutLeadMaintainer) {
            MobileValueRow(verbatimTitle: "Street Pea", verbatim: "github.com/streetpea") {
                store.send(.open(.leadMaintainer))
            }
            .accessibilityHint(Text(.mobileAboutLeadMaintainerHint))
        }
    }

    private var social: some View {
        MobileSettingsGroup {
            tile(
                mark: mark(
                    Self.discordMark,
                    tint: Self.discordBlue,
                    fallback: "bubble.left.and.bubble.right.fill"
                ),
                title: .mobileAboutDiscord, button: .mobileAboutDiscordButton, link: .discord
            ) {
                Text(.mobileAboutDiscordDetail)
            }
            tile(
                mark: mark(
                    Self.githubMark,
                    tint: Self.githubBlack,
                    fallback: "chevron.left.forwardslash.chevron.right"
                ),
                title: .mobileAboutGithub, button: .mobileAboutGithubButton, link: .github
            ) {
                Text(.mobileAboutGithubDetail)
            }
            tile(
                mark: mark(nil, tint: Color.primary.opacity(0.08), fallback: "envelope"),
                title: .mobileAboutContact, button: .mobileAboutContactButton, link: .email
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "streetpea@proton.me")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Text(.mobileAboutContactPreference)
                        .font(.caption)
                }
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
        let shown = detail()
        return FocusButton {
            store.send(.open(link))
        } label: {
            HStack(spacing: 12) {
                mark
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    shown
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(button))
    }

    private func mark(_ image: PlatformImage?, tint: Color, fallback: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint)
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 29, height: 29)
        .accessibilityHidden(true)
    }

    private var thanks: some View {
        MobileSettingsGroup(.mobileAboutThanks) {
            Text(.mobileAboutThanksDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mobileRowPadding()
            ForEach(AboutSettingsView.projects, id: \.name) { project in
                self.project(project)
            }
            contributorsRow
            if store.contributorsShown {
                contributors
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.contributorsShown)
    }

    @ViewBuilder
    private func project(_ project: AboutProject) -> some View {
        let link = project.link
        let author = project.author
        let note = project.note
        let label = HStack(spacing: 12) {
            AboutProjectLogo(logo: project.logo)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: project.name)
                    .foregroundStyle(
                        link == nil
                            ? Color.primary
                            : Palette.accent
                    )
                if author != nil || note != nil {
                    HStack(spacing: 4) {
                        if let author {
                            Text(.mobileAboutBy)
                                .foregroundStyle(.secondary)
                            Text(author)
                                .foregroundStyle(Palette.accent)
                        }
                        if let note {
                            Text(note)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.footnote)
                }
            }
            Spacer(minLength: 8)
            if link != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .mobileRowPadding()
        .contentShape(.rect)
        if let link {
            FocusButton {
                store.send(.open(link))
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(.mobileAboutProjectHint))
        } else {
            label
        }
    }

    private var contributorsRow: some View {
        FocusButton {
            store.send(.toggleContributors)
        } label: {
            HStack(spacing: 8) {
                Text(.mobileAboutAllContributors)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("\(store.contributors.count)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(
                        store.contributorsShown
                            ? .degrees(90)
                            : .zero
                    )
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(
                store.contributorsShown
                    ? .mobileAboutHideContributors
                    : .mobileAboutShowContributors
            )
        )
    }

    private var contributors: some View {
        WrappingRow(spacing: 6) {
            ForEach(store.contributors, id: \.self) { login in
                FocusButton {
                    store.send(.openContributor(login))
                } label: {
                    Text(login)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.accent.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(.mobileAboutContributorHint))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var license: some View {
        MobileSettingsGroup(.mobileAboutLicense) {
            Text(.mobileAboutLicenseText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mobileRowPadding()
        }
    }
}
