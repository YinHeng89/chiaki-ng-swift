import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// Account and Settings in the touch library: the signed-in account, its profiles and account actions, then the
/// settings categories, each opening its page.
struct MobileAccountView: View {
    /// The library.
    let store: StoreOf<LibraryFeature>

    /// The settings.
    let settings: StoreOf<SettingsFeature>

    @Environment(\.screenLayout) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MobilePageTitle(.mobileAccountTitle)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        account
                            .frame(minWidth: 300)
                        categories
                            .frame(minWidth: 300)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        account
                        categories
                    }
                }
            }
            .padding(.top, MobilePageTitle.topPadding(layout))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let selected = store.selectedProfile {
                HStack(spacing: 14) {
                    AccountAvatar(data: selected.avatarData, name: selected.name)
                        .frame(width: 52, height: 52)
                        .clipShape(.circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        let cloud = AccountCloudSummary(store: store)
                        Text(cloud.text)
                            .font(.subheadline)
                            .foregroundStyle(cloud.color)
                            .lineLimit(2)
                            .requires(.cloud, of: selected)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: .rect(cornerRadius: 24))
            }
            MobileGroup(title: .mobileAccountProfiles) {
                ForEach(store.accounts, id: \.id) { profile in
                    MobileRow(
                        verbatim: profile.name,
                        value: profile.id == store.selectedAccount
                            ? .mobileAccountCurrent
                            : nil
                    ) {
                        AccountAvatar(data: profile.avatarData, name: profile.name)
                            .frame(width: 29, height: 29)
                            .clipShape(.circle)
                    } action: {
                        store.send(.requested(.selectAccount(profile.id)))
                    }
                }
                MobileRow(.mobileAccountAdd, tint: Palette.accent) {
                    MobileRowIcon(symbol: "plus", color: Palette.accent.opacity(0.25))
                } action: {
                    store.send(.requested(.addAccount))
                }
            }
            if let selected = store.selectedProfile {
                MobileGroup(title: nil) {
                    if !store.isRefreshing {
                        MobileRow(.mobileAccountRefresh) {
                            MobileRowIcon(symbol: "arrow.clockwise", color: .blue)
                        } action: {
                            store.send(.requested(.refreshAccounts))
                        }
                    }
                    MobileRow(
                        .mobileAccountSignInAgain,
                        tint: store.needsSignIn
                            ? .orange
                            : nil
                    ) {
                        MobileRowIcon(symbol: "person.badge.key", color: .orange)
                    } action: {
                        store.send(.requested(.reconnectAccount(selected.id)))
                    }
                    MobileRow(.mobileAccountRemove, tint: .red) {
                        MobileRowIcon(symbol: "trash", color: .red)
                    } action: {
                        store.send(.requested(.removeAccount(selected.id)))
                    }
                }
            }
        }
    }

    private var categories: some View {
        MobileSettingsCategories(settings: settings) { route in
            settings.send(.select(route))
            store.send(.mobile(.settingsOpened(route)))
        }
    }
}

/// One settings category's page in the touch library, using the same page the settings panel shows.
struct MobileSettingsPage: View {
    /// The settings.
    @Bindable var settings: StoreOf<SettingsFeature>

    /// The category.
    let route: SettingsRoute

    @MenuFocusState private var networkFocus: NetworkSettingsFocus?

    var body: some View {
        page
            .id(route)
            .appConfirmation(settings.clearCacheConfirmation, confirm: {
                settings.send(.destination(.presented(.clearCache(.confirm))))
            }, cancel: {
                settings.send(.destination(.presented(.clearCache(.cancel))))
            })
            .sheet(item: $settings.scope(
                state: \.destination?.errorReport,
                action: \.destination.errorReport
            )) { report in
                ErrorReportSheet(store: report)
            }
            .tint(Palette.accent)
            .environment(\.settingsMenuFocus, true)
    }
}

extension MobileSettingsPage {
    @ViewBuilder private var page: some View {
        switch route {
        case .picture:
            MobilePictureSettingsPage(settings: settings)
        case .controls:
            MobileControlsSettingsPage(settings: settings)
        case .developer:
            MobileDeveloperSettingsPage(settings: settings)
        case .sound:
            MobileSoundSettingsPage(settings: settings)
        case .interface:
            MobileInterfaceSettingsPage(settings: settings)
        case .accessibility:
            MobileAccessibilitySettingsPage(settings: settings)
        case .network:
            MobileNetworkSettingsPage(settings: settings)
        case .entitlements:
            MobileEntitlementsSettingsPage(settings: settings)
        case .caches:
            MobileCachesSettingsPage(settings: settings)
        case .requests:
            MobileRequestsSettingsPage(settings: settings)
        case .tokens:
            MobileTokensSettingsPage(settings: settings)
        case .about:
            MobileAboutSettingsPage(settings: settings)
        case .remotePlayers:
            MobileRemotePlayersSettingsPage(settings: settings)
        default:
            SettingsPage(store: settings, route: route, networkFocus: $networkFocus)
        }
    }
}

/// A titled group of rows in the touch library, drawn as one rounded block.
struct MobileGroup<Content: View>: View {
    /// The group's title, or `nil` for none.
    let title: LocalizedStringResource?

    /// The rows.
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .textCase(.uppercase)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        row
                        if index < rows.count - 1 {
                            Divider().padding(.leading, 57)
                        }
                    }
                }
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 24))
        }
    }
}

/// A tappable row in the touch library: an icon, a title, an optional value and an optional chevron.
struct MobileRow<Icon: View>: View {
    /// The title.
    let title: Text

    /// The value shown at the trailing edge.
    var value: LocalizedStringResource?

    /// The title's colour.
    var tint: Color?

    /// Whether the row opens a page.
    var chevron = false

    /// The leading icon.
    @ViewBuilder let icon: Icon

    /// What a tap does.
    let action: () -> Void

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - value: The value shown at the trailing edge.
    ///   - tint: The title's colour.
    ///   - chevron: Whether the row opens a page.
    ///   - icon: The leading icon.
    ///   - action: What a tap does.
    init(
        _ title: LocalizedStringResource,
        value: LocalizedStringResource? = nil,
        tint: Color? = nil,
        chevron: Bool = false,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) {
        self.init(
            title: Text(title),
            value: value,
            tint: tint,
            chevron: chevron,
            icon: icon(),
            action: action
        )
    }

    /// Creates a row whose title is shown as it is, such as a name.
    ///
    /// - Parameters:
    ///   - verbatim: The title, shown without localization.
    ///   - value: The value shown at the trailing edge.
    ///   - tint: The title's colour.
    ///   - chevron: Whether the row opens a page.
    ///   - icon: The leading icon.
    ///   - action: What a tap does.
    init(
        verbatim: String,
        value: LocalizedStringResource? = nil,
        tint: Color? = nil,
        chevron: Bool = false,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) {
        self.init(
            title: Text(verbatim: verbatim),
            value: value,
            tint: tint,
            chevron: chevron,
            icon: icon(),
            action: action
        )
    }

    private init(
        title: Text,
        value: LocalizedStringResource?,
        tint: Color?,
        chevron: Bool,
        icon: Icon,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.tint = tint
        self.chevron = chevron
        self.icon = icon
        self.action = action
    }

    var body: some View {
        FocusButton(action: action) {
            HStack(spacing: 12) {
                icon
                title
                    .foregroundStyle(tint ?? .primary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusWithoutGrowth()
        .focusHighlightShape(MobileRowFocus.shape)
    }
}

/// A row's icon: a white symbol on a coloured rounded square.
struct MobileRowIcon: View {
    /// The symbol.
    let symbol: String

    /// The square's colour.
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: .rect(cornerRadius: 8))
    }
}
