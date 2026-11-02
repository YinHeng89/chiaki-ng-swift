import ChiakiModels
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// The stream menu's Players panel: cards for player 1 and the three extra seats, the controller picker and
/// the remote play section.
struct StreamPlayersPanel: View {
    /// The couch, which owns the seats.
    let store: StoreOf<CouchReducer>
    /// The remote play host, when the stream can host guests.
    var kakusan: StoreOf<KakusanHostFeature>?
    /// The stream menu's focus, when the panel is shown in the menu.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The menu control that has focus.
    var focusedControl: StreamMenuControl?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Players").font(.title2.weight(.semibold))
                Spacer(minLength: 12)
                Text("\(store.seats.takenCount + 1) of 4 seats taken")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    cards
                }
                .frame(minWidth: 600)
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        hostCard
                        seatCard(1)
                    }
                    GridRow {
                        seatCard(2)
                        seatCard(3)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let pad = store.picking {
                picker(for: pad)
            }
            remoteSection
        }
        .task {
            store.send(.loadInventory)
        }
    }

    /// The panel's focusable controls in order, for controller navigation.
    static func controls(for state: CouchReducer.State) -> [StreamMenuControl] {
        if let pad = state.picking {
            return state.controllerOptions(for: pad)
                .filter(\.available)
                .map { .playerPick($0.id) } + [.playerCancelPick]
        }
        var controls: [StreamMenuControl] = state.devices(of: 0).isEmpty
            ? [.playerReassign(0)]
            : [.playerControls(0), .playerReassign(0)]
        for pad in CouchSeats.pads {
            switch state.seats[pad] {
            case .open:
                if state.seats.lowestOpenPad == pad {
                    controls.append(.playerAdd(pad))
                }
            case .ready where state.seats[pad].remote != nil:
                controls.append(.playerRemove(pad))
            case .ready:
                controls += [.playerControls(pad), .playerReassign(pad), .playerRemove(pad)]
            case .choosingAccount, .joining, .pickingOnConsole, .passcode:
                controls.append(.playerRemove(pad))
            }
        }
        return controls
    }

    @ViewBuilder
    private var cards: some View {
        hostCard
        ForEach(CouchSeats.pads, id: \.self) { pad in
            seatCard(pad)
        }
    }

    private var playerOneInput: String {
        let keyboard = store.keyboardSeat == nil
        guard let controller = store.inventory.playerOne else {
            return keyboard
                ? ControllerDevice.keyboard.name
                : "No controller"
        }
        return keyboard
            ? "\(controller.name) and the keyboard"
            : controller.name
    }

    private var hostCard: some View {
        card(highlighted: store.picking == 0) {
            header(player: 1, bar: store.state.lightBar(for: 0), tag: "Host")
            if store.picking == 0 {
                choosingBody
            } else {
                Text("Ready")
                    .font(.callout)
                    .foregroundStyle(CouchTone.ready.color)
                Text(playerOneInput)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 6) {
                    if !store.state.devices(of: 0).isEmpty {
                        action("Controls", symbol: "slider.horizontal.3", target: .playerControls(0)) {
                            store.send(.openControls(pad: 0))
                        }
                    }
                    action("Change controller", symbol: "arrow.left.arrow.right",
                           target: .playerReassign(0)) {
                        store.send(.pickController(pad: 0))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func seatCard(_ pad: UInt8) -> some View {
        let seat = store.seats[pad]
        if seat == .open {
            card(highlighted: store.picking == pad, dashed: true) {
                header(player: Int(pad) + 1, bar: nil, tag: nil)
                if store.picking == pad {
                    choosingBody
                } else {
                    Text("Open")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if store.seats.lowestOpenPad == pad {
                        Spacer(minLength: 4)
                        action("Add player", symbol: "plus", target: .playerAdd(pad)) {
                            store.send(.pickController(pad: pad))
                        }
                    }
                }
            }
        } else {
            let status = status(of: pad)
            card(highlighted: store.picking == pad) {
                header(player: Int(pad) + 1, bar: store.state.lightBar(for: pad), tag: remoteTag(seat))
                if let name = seatName(seat) {
                    Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                }
                if store.picking == pad {
                    choosingBody
                } else {
                    seatStatus(seat, status: status)
                    if let device = seat.device {
                        Text(device.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    actions(pad, seat: seat)
                }
            }
        }
    }
}

extension StreamPlayersPanel {
    @ViewBuilder
    private var choosingBody: some View {
        Text("Choosing a controller")
            .font(.callout)
            .foregroundStyle(CouchTone.waiting.color)
    }

    private func picker(for pad: UInt8) -> some View {
        let options = store.state.controllerOptions(for: pad)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Controller for Player \(Int(pad) + 1)")
                .font(.headline)
            if options.isEmpty {
                Text("No other controllers connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(options) { option in
                pickerRow(option, pad: pad)
                    .padding(.horizontal, 8)
            }
            action("Cancel", symbol: nil, target: .playerCancelPick) {
                store.send(.cancelPicking)
            }
            .frame(maxWidth: 200)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }

    private func pickerRow(_ option: CouchControllerOption, pad: UInt8) -> some View {
        let target = StreamMenuControl.playerPick(option.id)
        let focused = focusedControl == target
        return FocusButton {
            store.send(.choose(pad: pad, device: option.device))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.device.isKeyboard
                    ? "keyboard"
                    : "gamecontroller")
                    .frame(width: 24)
                Text(title(of: option, for: pad))
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                if let tag = tag(of: option) {
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: .capsule)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.1))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!option.available)
        .opacity(option.available
            ? 1
            : 0.45)
            .focusHighlightShape(.roundedRectangle(12))
            .modifier(OptionalStreamMenuButtonFocus(focus: focus, target: target, focused: focused))
    }

    private func title(of option: CouchControllerOption, for pad: UInt8) -> String {
        if option.device.isKeyboard, pad == 0, option.holder == .playerOne {
            return "Keyboard only"
        }
        return option.device.name
    }

    private func tag(of option: CouchControllerOption) -> String? {
        switch option.holder {
        case nil:
            nil
        case .playerOne:
            option.device.isKeyboard && store.inventory.playerOne != nil
                ? nil
                : "Player 1"
        case .seat(let other):
            "Player \(Int(other) + 1)"
        }
    }

    private func actions(_ pad: UInt8, seat: CouchSeat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rememberAction(seat)
            if case .ready = seat, seat.remote == nil {
                action("Controls", symbol: "slider.horizontal.3", target: .playerControls(pad)) {
                    store.send(.openControls(pad: pad))
                }
                action("Change controller", symbol: "arrow.left.arrow.right", target: .playerReassign(pad)) {
                    store.send(.pickController(pad: pad))
                }
            }
            action(
                seat.waitingForConsole || seat.player == nil
                    ? "Cancel join"
                    : "Remove",
                symbol: nil,
                target: .playerRemove(pad),
                destructive: true
            ) {
                store.send(.cancel(pad: pad))
            }
        }
    }

    /// A seat's button, which takes menu focus as `target`.
    ///
    /// - Parameters:
    ///   - title: The button's title.
    ///   - symbol: The SF Symbol shown beside the title, if any.
    ///   - target: The menu control the button stands for.
    ///   - destructive: Whether the button removes something.
    ///   - perform: What the button does.
    func action(
        _ title: String, symbol: String?, target: StreamMenuControl, destructive: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        FocusButton(role: destructive
            ? .destructive
            : nil, action: perform) {
                Group {
                    if let symbol {
                        Label(title, systemImage: symbol)
                    } else {
                        Text(title)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: target,
                focused: focusedControl == target
            ))
            .glassControlStyle()
            .controlSize(.small)
    }

    private func header(player: Int, bar: Color?, tag: String?) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(bar ?? Color.secondary.opacity(0.35))
                .frame(width: 5, height: 20)
            Text("Player \(player)").font(.headline)
            if let tag {
                Spacer(minLength: 0)
                Text(tag.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
        }
    }

    private func card<Content: View>(
        highlighted: Bool, dashed: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(dashed
                        ? Color.clear
                        : Color.white.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        highlighted
                            ? Palette.accent
                            : Color.white.opacity(dashed
                                ? 0.22
                                : 0.12),
                        style: StrokeStyle(lineWidth: highlighted
                            ? 2
                            : 1, dash: dashed
                                ? [5, 4]
                                : [])
                    )
            }
    }
}
