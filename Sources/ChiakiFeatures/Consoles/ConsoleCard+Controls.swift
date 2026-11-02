import ChiakiModels
import SwiftUI
import DesignSystem
import MenuFocus

extension ConsoleCard {
    /// The connection tags; selectable buttons when the console offers both routes, a plain label otherwise.
    var tags: some View {
        HStack(spacing: 8) {
            ForEach(connections, id: \.self) { option in
                if connections.count > 1 {
                    FocusButton {
                        chosenConnection = option
                    } label: {
                        tag(option, selected: option == connection)
                            .opacity(playableConnections.contains(option)
                                ? 1
                                : Self.unavailableOpacity)
                    }
                    .buttonStyle(.plain)
                    .focusHighlightShape(.roundedRectangle(9))
                    .disabled(preview || !playableConnections.contains(option))
                    .menuFocused($focus, equals: .action(item, .connection(option)))
                    .environment(\.menuMove) { direction in
                        move(from: .action(item, .connection(option)), direction)
                    }
                    .accessibilityLabel("Play over \(option.title)")
                    .accessibilityHint(playableConnections.contains(option)
                        ? ""
                        : Self.missingLocallyNote)
                        .accessibilityAddTraits(option == connection
                            ? .isSelected
                            : [])
                } else {
                    tag(shownConnection, selected: false)
                }
            }
        }
    }

    /// The pill label of a route.
    ///
    /// - Parameters:
    ///   - option: The route.
    ///   - selected: Whether the route is the one Play uses, which highlights the pill.
    /// - Returns: The tag.
    func tag(_ option: ConsoleConnection, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: option.symbol)
                .font(.system(size: 14, weight: .medium))
            Text(option.title)
                .font(.system(size: 14))
        }
        .foregroundStyle(selected
            ? Color.primary
            : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: layout.controlSize)
            .background(Color.white.opacity(selected
                    ? 0.16
                    : 0.06), in: .rect(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(.white.opacity(selected
                                ? 0.28
                                : 0), lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: 9))
    }

    /// The Play button, the Edit and Delete buttons of an editable console, and the not-found note.
    var actions: some View {
        HStack(spacing: 12) {
            FocusButton {
                play()
            } label: {
                Label(playTitle, systemImage: "play")
                    .font(.system(size: wide
                            ? 19
                            : 17, weight: .semibold))
                        .padding(.horizontal, wide
                            ? 18
                            : 14)
                            .padding(.vertical, wide
                                ? 7
                                : 4)
            }
            .glassControlStyle()
            .controlSize(.large)
            .focusBorderShape(.capsule)
            .disabled(preview)
            .menuFocused($focus, equals: .console(item))
            .environment(\.menuMove) { direction in
                move(from: .console(item), direction)
            }
            .accessibilityLabel("\(playTitle) \(name) over \(shownConnection.title)")
            .accessibilityHint(missingLocally
                ? Self.missingLocallyNote
                : "")
            if editable {
                iconButton("Edit console", icon: AppIcon.edit.rawValue, action: .edit, perform: edit)
                iconButton(
                    "Delete console",
                    icon: AppIcon.deleteAccount.rawValue,
                    role: .destructive,
                    action: .delete,
                    perform: delete
                )
            }
            if missingLocally {
                Text(Self.missingLocallyNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 4)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The note shown when a home network stream finds no console nearby.
    static let missingLocallyNote = "Not found on your home network"

    /// The opacity of a connection tag that cannot be used.
    static let unavailableOpacity = 0.4

    /// Whether a home network stream would start while the scan does not see the console.
    var missingLocally: Bool {
        !preview && presence == .notNearby && shownConnection == .local
    }

    /// Whether the console, without an internet route, is saved at an address outside the home network.
    var directAddressOutside: Bool {
        guard !remoteAvailable else {
            return false
        }
        if let local = network.literalIsLocal(console.address) {
            return !local
        }
        return resolvedAddressOutside
    }

    /// The route the card shows; a console saved at an outside address shows the internet route.
    var shownConnection: ConsoleConnection {
        directAddressOutside
            ? .remote
            : connection
    }

    /// Resolves whether the console's hostname is outside the home network, for a console with no internet
    /// route.
    func resolveAddressLocality() async {
        resolvedAddressOutside = false
        guard !preview, !remoteAvailable,
              network.literalIsLocal(console.address) == nil
        else {
            return
        }
        let local = await network.consoleIsLocal(console.address)
        resolvedAddressOutside = !local
    }

    /// The Play button's label, which offers to wake a console in rest mode.
    var playTitle: String {
        presence == .restMode && !preview
            ? "Wake and play"
            : "Play"
    }

    /// Whether the console is saved and can be edited or deleted.
    var editable: Bool {
        !preview && console.id != nil
    }

    /// A round icon button of the card that is a controller focus stop.
    ///
    /// - Parameters:
    ///   - label: The help text and accessibility label.
    ///   - icon: The SF Symbol.
    ///   - role: The button role, such as destructive.
    ///   - action: The focus stop the button is.
    ///   - perform: What the button does.
    /// - Returns: The button.
    func iconButton(
        _ label: String,
        icon: String,
        role: ButtonRole? = nil,
        action: ConsoleCardAction,
        perform: @escaping () -> Void
    ) -> some View {
        FocusButton(role: role, action: perform) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .frame(width: iconButtonSide, height: iconButtonSide)
        .glassControlStyle()
        .tint(.clear)
        .focusBorderShape(.circle)
        .menuFocused($focus, equals: .action(item, action))
        .environment(\.menuMove) { direction in
            move(from: .action(item, action), direction)
        }
        .help(label)
        .accessibilityLabel(label)
    }

    /// The side of a round icon button: 40 points, or the finger-sized minimum on touch.
    var iconButtonSide: CGFloat {
        max(40, layout.controlSize)
    }

    /// Starts a stream over the chosen route; does nothing on a preview card.
    func play() {
        guard !preview else {
            return
        }
        switch connection {
        case .local:
            startLocal()
        case .remote:
            startRemote()
        }
    }

    /// Moves controller focus from a card stop: across the tags or the buttons, between the tags and Play, or
    /// out
    /// of the card.
    ///
    /// - Parameters:
    ///   - current: The focused stop.
    ///   - direction: The direction of the move.
    func move(from current: ConsoleLibraryFocus, _ direction: MenuMoveDirection) {
        let tagStops = connections.count > 1
            ? playableConnections.map(ConsoleCardAction.connection)
            : []
        let actionStops: [ConsoleLibraryFocus] = [.console(item)] + (editable
            ? [.action(item, .edit), .action(item, .delete)]
            : []) + (showsContinue
            ? [.action(item, .resume)]
            : [])
        switch direction {
        case .left, .right:
            moveAcross(from: current, direction, tagStops: tagStops, actionStops: actionStops)
        case .up:
            if case .action(_, .connection) = current {
                moveConsole(.up)
            } else if tagStops.isEmpty {
                leave(from: current, .up)
            } else {
                focus = .action(item, .connection(connection))
            }
        case .down:
            if case .action(_, .connection) = current {
                focus = .console(item)
            } else {
                leave(from: current, .down)
            }
        @unknown default:
            break
        }
    }

    private func leave(from current: ConsoleLibraryFocus, _ direction: MenuMoveDirection) {
        if current == .action(item, .resume), let moveContinue {
            moveContinue(direction)
        } else {
            moveConsole(direction)
        }
    }

    private func moveAcross(
        from current: ConsoleLibraryFocus,
        _ direction: MenuMoveDirection,
        tagStops: [ConsoleCardAction],
        actionStops: [ConsoleLibraryFocus]
    ) {
        let step = direction == .left
            ? -1
            : 1
        if case .action(_, .connection) = current, case .action(_, let action) = current,
           let index = tagStops.firstIndex(of: action) {
            if tagStops.indices.contains(index + step) {
                focus = .action(item, tagStops[index + step])
            } else {
                moveConsole(direction)
            }
        } else if let index = actionStops.firstIndex(of: current) {
            if actionStops.indices.contains(index + step) {
                focus = actionStops[index + step]
            } else {
                leave(from: current, direction)
            }
        }
    }

    /// The context menu: play over either route, edit and delete; empty on a preview card.
    @ViewBuilder var contextMenuItems: some View {
        if !preview {
            Button("Play on home network", systemImage: AppIcon.start.rawValue, action: startLocal)
                .disabled(localUnavailable)
            if remoteAvailable {
                Button("Play over the internet", systemImage: "globe", action: startRemote)
            }
            Divider()
            Button("Edit console", systemImage: AppIcon.edit.rawValue, action: edit)
                .disabled(console.id == nil)
            Button(
                "Delete console",
                systemImage: AppIcon.deleteAccount.rawValue,
                role: .destructive,
                action: delete
            )
            .disabled(console.id == nil)
        }
    }
}
