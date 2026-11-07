import ChiakiModels
import ComposableArchitecture
import SwiftUI
import DesignSystem
import MenuFocus

/// The library's navigation rail: section tabs, Join Game, Notifications, settings, the live log when it is
/// turned on, the account and Quit, docked to a window edge.
///
/// On a side edge under a pointer it shows icons only and widens to show titles after the pointer rests on
/// it, while the account sheet is open, or while a controller focuses one of its stops. On touch, where
/// nothing hovers, it never widens: every stop shows its title under its icon instead.
struct LibraryRailView<AccountSheet: View, AlertsPanel: View>: View {
    /// The rail's width on a side edge when it shows icons only.
    static var collapsedWidth: CGFloat {
        64
    }

    /// The rail's width on a side edge when every stop shows its title under its icon.
    static var labelledWidth: CGFloat {
        72
    }

    /// The rail's resting width on a side edge for a layout: ``labelledWidth`` on touch, ``collapsedWidth``
    /// under a pointer.
    ///
    /// - Parameter layout: The screen's layout traits.
    /// - Returns: The width in points.
    static func collapsedWidth(for layout: ScreenLayout) -> CGFloat {
        layout.hoverAffordances
            ? collapsedWidth
            : labelledWidth
    }

    /// The rail's width on a side edge when it shows titles.
    static var expandedWidth: CGFloat {
        220
    }

    /// The rail's height on the top or bottom edge.
    static var barHeight: CGFloat {
        64
    }

    /// The rail's stops and focus rules.
    let rail: LibraryRail
    /// The library section currently shown.
    let selected: LibrarySection
    /// The signed-in account the profile stop names, if any.
    let account: RegistrationFlow.Profile?
    /// The library's controller focus, bound to the stops.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// The account sheet the account stop presents, while it is open.
    @Binding var accountSheet: StoreOf<LibraryAccountSheetFeature>?
    /// Acts on a stop that was clicked or pressed.
    let activate: (ConsoleLibraryFocus) -> Void
    /// Moves controller focus from a stop in a direction.
    let move: (ConsoleLibraryFocus, MenuMoveDirection) -> Void
    /// Receives whether the rail is currently widened.
    var shownExpanded: Binding<Bool> = .constant(false)
    /// How many alerts arrived since the Notifications panel was last opened, shown as the bell's badge.
    var unseenAlerts = 0
    /// Whether the Notifications panel is open.
    var alertsShown: Binding<Bool> = .constant(false)
    /// Builds the Notifications panel's content.
    @ViewBuilder let alerts: () -> AlertsPanel
    /// Builds the account sheet's content.
    @ViewBuilder let sheet: (StoreOf<LibraryAccountSheetFeature>) -> AccountSheet
    @Environment(\.inputMode) private var inputMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.topControlsLayout) private var topControlsLayout
    @Environment(\.screenLayout) private var layout
    @State private var hover = RailHover.outside
    @State private var settingsHostID = UUID()

    /// Whether the rail shows titles beside its icons.
    var expanded: Bool {
        if !rail.edge.isVertical {
            return true
        }
        guard layout.hoverAffordances else {
            return false
        }
        return hover == .inside || accountSheet != nil || alertsShown.wrappedValue
            || inputMode.shows(rail.contains(focus.wrappedValue))
    }

    /// Whether every stop shows its title under its icon, as it does on a side edge on touch, where the rail
    /// cannot widen on hover and a tooltip has no finger equivalent.
    var labelled: Bool {
        rail.edge.isVertical && !layout.hoverAffordances
    }

    var body: some View {
        stack
            .padding(10)
            .glassPanel(.large)
            .onHover(perform: hovered)
            .animation(AppMotion.animation(reduced: reduceMotion), value: expanded)
            .onChange(of: expanded, initial: true) { _, value in
                shownExpanded.wrappedValue = value
            }
            .onAppear {
                topControlsLayout?.hostSettings(settingsHostID, true)
            }
            .onDisappear {
                topControlsLayout?.hostSettings(settingsHostID, false)
            }
    }

    private func hovered(_ inside: Bool) {
        guard inside else {
            hover = .outside
            return
        }
        let attempt = UUID()
        hover = .waiting(attempt)
        Task { @MainActor in
            try? await Task.sleep(for: RailHover.intent)
            if hover == .waiting(attempt) {
                hover = .inside
            }
        }
    }

    @ViewBuilder private var stack: some View {
        if rail.edge.isVertical {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rail.leading, id: \.self, content: item)
                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                ForEach(rail.trailing, id: \.self, content: item)
            }
            .frame(width: stackWidth, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                ForEach(rail.leading, id: \.self, content: item)
                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                ForEach(rail.trailing, id: \.self, content: item)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.barHeight - 20)
        }
    }

    private var stackWidth: CGFloat {
        if expanded {
            return Self.expandedWidth - 20
        }
        return Self.collapsedWidth(for: layout) - 20
    }

    private var popoverEdge: Edge {
        switch rail.edge {
        case .top:
            .bottom
        case .left:
            .trailing
        case .right:
            .leading
        case .bottom:
            .top
        }
    }

    @ViewBuilder
    private func item(_ stop: ConsoleLibraryFocus) -> some View {
        let button = FocusButton {
            activate(stop)
        } label: {
            itemLabel(stop)
                .frame(maxWidth: rail.edge.isVertical
                    ? .infinity
                    : nil, minHeight: max(44, layout.controlSize), alignment: labelled
                        ? .center
                        : .leading)
                    .background(
                        isSelected(stop)
                            ? Palette.accent.opacity(0.22)
                            : .clear,
                        in: .rect(cornerRadius: 13)
                    )
                    .contentShape(.rect(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected(stop)
            ? Color.primary
            : Color.secondary)
            .focusHighlightShape(.roundedRectangle(13))
            .focusWithoutGrowth()
            .disabled(rail.unavailable.contains(stop))
            .opacity(rail.unavailable.contains(stop)
                ? 0.4
                : 1)
                .menuFocused(focus, equals: stop)
                .environment(\.menuMove) { direction in
                    move(stop, direction)
                }
                .help(title(of: stop))
                .accessibilityLabel(title(of: stop))
                .accessibilityAddTraits(isSelected(stop)
                    ? .isSelected
                    : [])
        if stop == .profile {
            button.popover(item: $accountSheet, arrowEdge: popoverEdge, content: sheet)
        } else if stop == .notifications {
            button.popover(isPresented: alertsShown, arrowEdge: popoverEdge, content: alerts)
        } else {
            button
        }
    }

    @ViewBuilder
    private func itemLabel(_ stop: ConsoleLibraryFocus) -> some View {
        if labelled {
            VStack(spacing: 3) {
                stopIcon(stop)
                Text(shortTitle(of: stop))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 14) {
                stopIcon(stop)
                if expanded {
                    Text(title(of: stop))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func stopIcon(_ stop: ConsoleLibraryFocus) -> some View {
        icon(of: stop)
            .foregroundStyle(isSelected(stop)
                ? Palette.accent
                : Color.secondary)
                .frame(width: 28, height: 28)
    }

    private func isSelected(_ stop: ConsoleLibraryFocus) -> Bool {
        stop == .librarySection(selected)
    }

    @ViewBuilder
    private func icon(of stop: ConsoleLibraryFocus) -> some View {
        switch stop {
        case .librarySection(let section):
            Image(systemName: section.icon.rawValue).font(.system(size: 17, weight: .medium))
        case .joinGame:
            Image(systemName: "person.2").font(.system(size: 15, weight: .medium))
        case .notifications:
            Image(systemName: "bell").font(.system(size: 16, weight: .medium))
                .overlay(alignment: .topTrailing) {
                    AlertsBadge(count: unseenAlerts)
                        .offset(x: 8, y: -6)
                }
        case .settings:
            AppIcon.settings.image.font(.system(size: 17, weight: .medium))
        case .log:
            AppIcon.logging.image.font(.system(size: 16, weight: .medium))
        case .quit:
            AppIcon.quit.image.font(.system(size: 16, weight: .medium))
        case .profile:
            if let account {
                AccountAvatar(data: account.avatarData, name: account.name)
                    .scaleEffect(0.7)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "person.crop.circle").font(.system(size: 18, weight: .medium))
            }
        default:
            EmptyView()
        }
    }

    private func shortTitle(of stop: ConsoleLibraryFocus) -> LocalizedStringResource {
        switch stop {
        case .joinGame:
            .libraryRailJoin
        case .notifications:
            .libraryRailAlerts
        case .log:
            .libraryRailLog
        case .profile:
            .libraryRailAccount
        default:
            title(of: stop)
        }
    }

    private func title(of stop: ConsoleLibraryFocus) -> LocalizedStringResource {
        switch stop {
        case .librarySection(let section):
            section.title
        case .joinGame:
            .libraryBarJoinGame
        case .notifications:
            unseenAlerts > 0
                ? .libraryBarNotificationsNew(count: unseenAlerts)
                : .libraryBarNotifications
        case .settings:
            .commonSettings
        case .log:
            .libraryRailDeveloperLog
        case .quit:
            .libraryRailQuit
        case .profile:
            account.map { .verbatim($0.name) } ?? .libraryRailAccounts
        default:
            ""
        }
    }
}

extension EnvironmentValues {
    /// The window edge the library rail is docked to.
    @Entry var libraryRailEdge = LibraryRailEdge.left
    /// The height the cloud library's game detail fills.
    @Entry var cloudLibraryHeight: CGFloat = 820
    /// Whether the cloud library sits beside the library rail, so Back moves focus to the rail.
    @Entry var libraryRailShown = false
}

/// The count of new alerts on the Notifications bell, hidden when there are none.
struct AlertsBadge: View {
    /// How many alerts are new.
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 9
                ? "9+"
                : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.red, in: .capsule)
                .accessibilityHidden(true)
        }
    }
}

/// Whether the pointer is over the side rail, with a short wait before it counts as inside.
enum RailHover: Equatable {
    /// The pointer is outside the rail.
    case outside
    /// The pointer entered the rail and is waiting out ``RailHover/intent`` for the attempt with this id.
    case waiting(UUID)
    /// The pointer has rested on the rail long enough to widen it.
    case inside

    /// How long the pointer must rest on the rail before it widens.
    static let intent = Duration.milliseconds(250)
}
