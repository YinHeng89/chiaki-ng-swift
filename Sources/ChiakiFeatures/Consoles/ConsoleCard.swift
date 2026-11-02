import ChiakiClients
import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// A button on a console card other than Play, as a controller focus stop.
public enum ConsoleCardAction: Hashable, Sendable {
    /// The connection tag that plays over this route.
    case connection(ConsoleConnection)
    /// The continue button that relaunches the last played title.
    case resume
    /// The button that opens the console editor.
    case edit
    /// The button that deletes the console.
    case delete
}

/// Every controller focus stop of the console library.
public enum ConsoleLibraryFocus: Hashable, Sendable {
    /// The account profile button.
    case profile
    /// A section of the library rail.
    case librarySection(LibrarySection)
    /// The Play button of a console card.
    case console(DisplayedConsole)
    /// A button on a console card other than Play.
    case action(DisplayedConsole, ConsoleCardAction)
    /// The Add console button.
    case addConsole
    /// The Add account button.
    case addAccount
    /// The button of the shelf's status line.
    case statusAction
    /// The Join a game button.
    case joinGame
    /// The Notifications button.
    case notifications
    /// The Settings button.
    case settings
    /// The live developer log stop, shown while the live log button is turned on.
    case log
    /// The Quit button.
    case quit
    /// A recently played title of the console with this id, by its title id.
    case recentTitle(UUID, String)

    /// Whether Back on this stop may leave for the rail or quit, which a card's secondary button does not
    /// allow.
    public var backQuits: Bool {
        switch self {
        case .librarySection, .console, .addConsole, .addAccount, .statusAction, .profile, .joinGame,
             .notifications, .settings, .log,
             .quit, .recentTitle:
            true
        case .action:
            false
        }
    }
}

/// The route a console stream takes.
public enum ConsoleConnection: Hashable, Sendable {
    /// Over the home network, to a console found by its local address.
    case local
    /// Over the internet, through PSN.
    case remote

    /// The tag label of the route.
    var title: String {
        switch self {
        case .local:
            "Home network"
        case .remote:
            "Internet"
        }
    }

    /// The SF Symbol of the route's tag.
    var symbol: String {
        switch self {
        case .local:
            "wifi"
        case .remote:
            "globe"
        }
    }
}

/// A console's card on the library shelf: its art, name, connection tags and Play, Edit and Delete buttons,
/// with the last played title to continue when there is room.
struct ConsoleCard: View {
    /// The card as the shelf lists it.
    let item: DisplayedConsole
    /// The paired console the card shows.
    let console: RegistrationFlow.ConsoleTarget
    /// The name of the account paired with the console.
    let accountName: String
    /// Whether a connection is starting, which disables the card.
    let busy: Bool
    /// Whether the local scan sees the console, and whether it rests.
    var presence: ConsolePresence = .unknown
    /// The title last played on the console, offered to continue.
    var lastPlayed: RecentTitle?
    /// The layered key art of the last played title, once fetched.
    var art: GameArtLayers?
    /// Relaunches the last played title.
    var resume: () -> Void = {
    }
    /// Starts a stream over the home network.
    let startLocal: () -> Void
    /// Starts a stream over the internet.
    let startRemote: () -> Void
    /// Opens the console editor.
    let edit: () -> Void
    /// Asks to delete the console.
    let delete: () -> Void
    /// The library's controller focus.
    @MenuFocusState.Binding var focus: ConsoleLibraryFocus?
    /// Moves focus out of the card to the neighbouring stop on the shelf.
    let moveConsole: (MenuMoveDirection) -> Void
    /// Moves focus out of the continue button, when the shelf routes it differently from the rest of the
    /// card.
    var moveContinue: ((MenuMoveDirection) -> Void)?
    /// The card's size on a compact screen.
    var compactSize = ConsoleCard.compactSize
    /// The route the user picked with the connection tags, if any.
    @State var chosenConnection: ConsoleConnection?
    /// Whether the console's hostname resolved to an address outside the home network.
    @State var resolvedAddressOutside = false
    /// Classifies and resolves the console's address.
    @Environment(\.network) var network
    @State private var hovered = false
    /// The measured width of the card, which picks the wide layout and the continue form.
    @State var cardWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the last input came from a controller, a keyboard or the pointer, which decides when focus
    /// shows.
    @Environment(\.inputMode) var inputMode
    /// The room, stature and pointing method of the screen, which pick the compact card and size its controls.
    @Environment(\.screenLayout) var layout
    /// Whether the compact card draws the console art layered over its frame; a developer preview setting.
    @AppStorage(DeveloperPreviewSetting.layeredConsoleCards) var layeredCompactArt = true
    @Environment(\.streamerMode) private var streamerMode

    /// Whether the card is a developer preview that starts nothing.
    var preview: Bool {
        item.preview
    }

    /// Whether the console can be streamed over the internet.
    var remoteAvailable: Bool {
        console.remoteDeviceID != nil
    }

    /// The routes the card offers: always the home network, and the internet when the console supports it.
    var connections: [ConsoleConnection] {
        remoteAvailable
            ? [.local, .remote]
            : [.local]
    }

    /// Whether the home network route is unavailable: the console also plays over the internet and the scan
    /// searched without seeing it.
    var localUnavailable: Bool {
        !preview && remoteAvailable && presence == .notNearby
    }

    /// The routes Play can use now, without a home network route that is unavailable.
    var playableConnections: [ConsoleConnection] {
        connections.filter { connection in
            connection == .remote || !localUnavailable
        }
    }

    /// The route Play uses: the one picked, else the internet when the console is not nearby and supports it,
    /// else
    /// the home network.
    var connection: ConsoleConnection {
        if let chosenConnection, playableConnections.contains(chosenConnection) {
            return chosenConnection
        }
        return localUnavailable
            ? .remote
            : .local
    }

    /// Whether the controller focus is on one of the card's buttons.
    var containsFocus: Bool {
        switch focus {
        case .console(item), .action(item, _):
            true
        default:
            false
        }
    }

    /// The card border, accented while the card holds visible focus and brighter while hovered.
    var borderColor: Color {
        if inputMode.shows(containsFocus) {
            return Palette.accent.opacity(0.5)
        }
        return .white.opacity(hovered
            ? 0.2
            : 0.12)
    }

    /// The card width from which the wide layout is used.
    nonisolated static let wideWidth: CGFloat = 900

    /// Whether the card is at least ``ConsoleCard/wideWidth`` wide.
    var wide: Bool {
        cardWidth >= Self.wideWidth
    }

    /// How the last played title is shown at the card's width.
    var continueForm: ConsoleContinueForm {
        ConsoleContinueForm.of(kind: console.kind, lastPlayed: lastPlayed, cardWidth: cardWidth)
    }

    /// Whether the card shows the last played title.
    var showsContinue: Bool {
        continueForm != .hidden
    }

    /// The layered art to draw behind the card, only while the last played title is shown.
    var layeredArt: GameArtLayers? {
        showsContinue
            ? art
            : nil
    }

    /// The console's name, hidden in streamer mode.
    var name: String {
        StreamerMode.consoleName(
            console.name, address: console.address, kind: console.kind.rawValue, enabled: streamerMode
        )
    }

    var body: some View {
        if layout.isCompact {
            compactBody
        } else {
            regularBody
        }
    }

    /// The card's layout on a regular screen: art, header, name, tags and actions in a row.
    var regularBody: some View {
        HStack(spacing: continueForm == .compact
            ? 18
            : 24) {
                ConsoleArtwork(height: wide
                    ? 168
                    : 112, kind: console.kind)
                    .frame(width: wide
                        ? 132
                        : 90, height: wide
                            ? 180
                            : 120)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text(name)
                        .font(.system(size: wide
                                ? 34
                                : 26, weight: .semibold))
                            .lineLimit(1)
                            .padding(.top, 4)
                    tags
                        .padding(.top, 10)
                    actions
                        .padding(.top, wide
                            ? 20
                            : 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsContinue, let lastPlayed, layeredArt == nil {
                    VStack(alignment: .trailing, spacing: continueForm == .wide
                        ? 14
                        : 10) {
                            statusBadge
                            if continueForm == .wide {
                                continueButton(lastPlayed)
                            } else {
                                compactContinueButton(lastPlayed)
                            }
                        }
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, wide
                ? 36
                : 28)
                .padding(.vertical, wide
                    ? 30
                    : 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        cardWidth = width
                    }
                    .background {
                        continueArt
                    }
                    .overlay(alignment: .topTrailing) {
                        layeredStatus
                    }
                    .animation(reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.4), value: layeredArt)
                        .glassPanel(.modal)
                        .overlay {
                            RoundedRectangle(cornerRadius: GlassPanel.Radius.modal.points)
                                .strokeBorder(borderColor, lineWidth: inputMode.shows(containsFocus)
                                    ? 1.5
                                    : 1)
                        }
                        .disabled(busy)
                        .task(id: console.address) {
                            await resolveAddressLocality()
                        }
                        .onChange(of: localUnavailable) { _, unavailable in
                            guard unavailable, case .action(item, .connection) = focus else {
                                return
                            }
                            focus = .console(item)
                        }
                        .onHover {
                            hovered = $0
                        }
                        .animation(reduceMotion
                            ? nil
                            : .easeOut(duration: 0.15), value: borderColor)
                            .contextMenu {
                                contextMenuItems
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(name)
                            .accessibilityIdentifier("console-card")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(console.kind == .ps5
                ? "PLAYSTATION 5"
                : "PLAYSTATION 4")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if !showsContinue {
                statusBadge
            }
        }
    }

    /// The console's status dot and label, or Preview on a developer preview card.
    @ViewBuilder var statusBadge: some View {
        if preview {
            badge("Preview", color: .secondary)
        } else if let title = presence.title {
            badge(title, color: presence.color)
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status \(title)")
    }
}

extension ConsoleCard {
    /// The height of a short compact card.
    static let compactShortHeight: CGFloat = 120
    /// How far the layered console art of a short card rises above the card.
    static let compactArtRise: CGFloat = 20
    /// How far the layered console art of a short card hangs past its leading edge.
    static let compactArtOverhang: CGFloat = 10
    /// The inner padding of a short compact card.
    static let compactShortPadding: CGFloat = 14
    /// The width of the Play, Edit and Delete column of a short card.
    static let compactTrailingWidth: CGFloat = 96

    /// Whether the card is lower than half the tallest compact card and uses the short layout.
    var compactShort: Bool {
        compactSize.height < Self.compactTallest / 2
    }

    /// The height of the console art of a short card, taller when it is layered over the card's edge.
    var compactShortArtHeight: CGFloat {
        layeredCompactArt
            ? compactSize.height + Self.compactArtRise - 8
            : compactSize.height - 2 * Self.compactShortPadding
    }

    /// The width kept clear for the console art of a short card.
    static let compactShortArtColumn: CGFloat = 62

    /// The short compact card: art on the leading edge, name and connection in the middle, buttons trailing.
    var compactShortBody: some View {
        compactSurface(compactShortContent)
            .overlay(alignment: .bottomLeading) {
                ConsoleArtwork(height: compactShortArtHeight, kind: console.kind)
                    .fixedSize()
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 6)
                    .padding(
                        .bottom,
                        layeredCompactArt
                            ? 8
                            : Self.compactShortPadding
                    )
                    .offset(
                        x: layeredCompactArt
                            ? -Self.compactArtOverhang
                            : Self.compactShortPadding
                    )
                    .allowsHitTesting(false)
            }
    }

    private var compactShortContent: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: Self.compactShortArtColumn)
            VStack(alignment: .leading, spacing: 2) {
                compactCaption
                compactName
                compactConnectionStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                compactPlayButton(height: 44) { direction in
                    moveCompactShort(from: nil, direction)
                }
                if editable {
                    HStack(spacing: 8) {
                        compactIconButton(.edit) { direction in
                            moveCompactShort(from: .edit, direction)
                        }
                        compactIconButton(.delete) { direction in
                            moveCompactShort(from: .delete, direction)
                        }
                    }
                }
            }
            .frame(width: Self.compactTrailingWidth)
        }
        .padding(Self.compactShortPadding)
    }

    @ViewBuilder private var compactConnectionStatus: some View {
        HStack(spacing: 8) {
            if playableConnections.count > 1 {
                FocusButton {
                    cycleConnection()
                } label: {
                    compactConnectionChip(selected: true)
                }
                .buttonStyle(.plain)
                .focusHighlightShape(.roundedRectangle(10))
                .disabled(preview)
                .menuFocused($focus, equals: .action(item, .connection(connection)))
                .environment(\.menuMove) { direction in
                    moveCompactShort(from: .connection(connection), direction)
                }
                .accessibilityLabel("Play over \(connection.title)")
                .accessibilityHint("Switches between your home network and the internet")
            } else {
                compactConnectionChip(selected: false)
            }
            Text(compactStatusTitle ?? shownConnection.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func compactConnectionChip(selected: Bool) -> some View {
        Image(systemName: shownConnection.symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(
                selected
                    ? Color.primary
                    : Color.secondary
            )
            .frame(width: 44, height: 40)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        CompactRim.color.opacity(
                            selected
                                ? 1
                                : 0
                        ),
                        lineWidth: CompactRim.width
                    )
            }
            .frame(height: 44)
            .contentShape(.rect)
    }

    private func cycleConnection() {
        guard let index = playableConnections.firstIndex(of: connection) else {
            return
        }
        let next = playableConnections[(index + 1) % playableConnections.count]
        let held = focus == .action(item, .connection(connection))
        chosenConnection = next
        guard held else {
            return
        }
        focus = .action(item, .connection(next))
        Task { @MainActor in
            await Task.yield()
            if focus == nil {
                focus = .action(item, .connection(next))
            }
        }
    }

    /// Moves controller focus from a stop of a short compact card, or out of the card when the move leaves
    /// it.
    ///
    /// - Parameters:
    ///   - action: The focused card button, or `nil` for Play.
    ///   - direction: The direction of the move.
    func moveCompactShort(from action: ConsoleCardAction?, _ direction: MenuMoveDirection) {
        let toggle: ConsoleLibraryFocus? = playableConnections.count > 1 && !preview
            ? .action(item, .connection(connection))
            : nil
        let target: ConsoleLibraryFocus?
        switch (action, direction) {
        case (nil, .left):
            target = toggle
        case (nil, .down) where editable:
            target = .action(item, .edit)
        case (.connection, .right):
            target = .console(item)
        case (.edit, .up), (.delete, .up):
            target = .console(item)
        case (.edit, .left):
            target = toggle
        case (.edit, .right):
            target = .action(item, .delete)
        case (.delete, .left):
            target = .action(item, .edit)
        default:
            target = nil
        }
        if let target {
            focus = target
        } else {
            moveConsole(direction)
        }
    }
}

extension ConsoleCard {
    /// The continue button of a wide card: the title's tile, name and when it was last played.
    ///
    /// - Parameter title: The last played title.
    /// - Returns: The button, a focus stop that relaunches the title.
    func continueButton(_ title: RecentTitle) -> some View {
        FocusButton(action: resume) {
            HStack(spacing: 16) {
                CloudArtworkView(url: artworkURL(title.imageURL))
                    .frame(width: 92, height: 92)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title.name)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                    if let lastPlayed = title.lastPlayed {
                        Text(lastPlayed.formatted(.relative(presentation: .named).locale(.current)))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 220, alignment: .leading)
            }
            .padding(10)
            .glassEffect(AppGlass.control.interactive(), in: .rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(18))
        .menuFocused($focus, equals: .action(item, .resume))
        .environment(\.menuMove) { direction in
            move(from: .action(item, .resume), direction)
        }
        .accessibilityLabel("Continue \(title.name) on \(name)")
    }

    /// The smaller continue button of a card too narrow for the wide one.
    ///
    /// - Parameter title: The last played title.
    /// - Returns: The button, a focus stop that relaunches the title.
    func compactContinueButton(_ title: RecentTitle) -> some View {
        FocusButton(action: resume) {
            HStack(spacing: 10) {
                CloudArtworkView(url: artworkURL(title.imageURL))
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let lastPlayed = title.lastPlayed {
                        Text(lastPlayed.formatted(.relative(presentation: .named).locale(.current)))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 96, idealWidth: 116, maxWidth: 116, alignment: .leading)
            }
            .padding(8)
            .glassEffect(AppGlass.control.interactive(), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(14))
        .menuFocused($focus, equals: .action(item, .resume))
        .environment(\.menuMove) { direction in
            move(from: .action(item, .resume), direction)
        }
        .accessibilityLabel("Continue \(title.name) on \(name)")
        .accessibilityIdentifier("console-continue-compact")
    }

    /// The layered key art of the last played title, with a Continue pill that relaunches it.
    ///
    /// - Parameters:
    ///   - title: The last played title.
    ///   - layers: The title's background, hero and logo layers.
    /// - Returns: The art and its pill.
    func layeredContinueButton(_ title: RecentTitle, _ layers: GameArtLayers.Layered) -> some View {
        ConsoleContinueArt(
            layers: layers, wide: continueForm == .wide, focused: focus == .action(item, .resume),
            resume: resume
        ) {
            FocusButton(action: resume) {
                HStack(spacing: 8) {
                    Text("Continue")
                        .fontWeight(.semibold)
                    if let lastPlayed = title.lastPlayed {
                        Text(lastPlayed.formatted(.relative(presentation: .named).locale(.current)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: layout.controlSize)
                .glassEffect(AppGlass.control.interactive(), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .focusHighlightShape(.capsule)
            .menuFocused($focus, equals: .action(item, .resume))
            .environment(\.menuMove) { direction in
                move(from: .action(item, .resume), direction)
            }
            .accessibilityLabel("Continue \(title.name) on \(name)")
            .accessibilityIdentifier("console-continue-layered")
        }
    }

    /// The layered continue art drawn behind the card's trailing side, once the title's layers are fetched.
    @ViewBuilder var continueArt: some View {
        if let layers = layeredArt?.layered, let lastPlayed {
            Color.clear
                .overlay(alignment: .trailing) {
                    layeredContinueButton(lastPlayed, layers)
                        .frame(width: cardWidth * continueForm.artFraction)
                }
                .clipShape(.rect(cornerRadius: 26))
                .transition(.opacity)
        }
    }

    /// The status badge drawn over the layered art, on a dark capsule so it stays legible.
    @ViewBuilder var layeredStatus: some View {
        if layeredArt != nil {
            statusBadge
                .background(.black.opacity(0.35), in: .capsule)
                .padding(.top, 20)
                .padding(.trailing, 24)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func artworkURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil else {
            return nil
        }
        return url
    }
}

extension EnvironmentValues {
    /// The network checks the console cards classify addresses with, which the app supplies at its root.
    @Entry public var network = NetworkClient.testValue
}
