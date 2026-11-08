import ChiakiModels
import PlatformUI
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// Asks who uses a controller that just connected: player 1, a new player, or nobody for now.
struct CouchNewControllerOverlay: View {
    /// The couch, which owns the question.
    let store: StoreOf<CouchReducer>
    @State private var hostWindow: PlatformWindow?
    @State private var selection = CouchNewControllerChoice.newPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let device = store.newController {
            ZStack {
                Dimming.standard.color
                VStack(spacing: 22) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 26, weight: .medium))
                        .frame(width: 56, height: 56)
                        .glassEffect(AppGlass.control, in: .circle)
                    Text(.playbackCouchNewControllerQuestion(device: device.name))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        option(.playerOne, title: .playbackCouchPlayer(number: 1))
                        option(.newPlayer, title: newPlayerTitle)
                            .disabled(targetPad == nil)
                    }
                    FocusButton {
                        store.send(.newController(.notNow))
                    } label: {
                        Text(.playbackCouchNewControllerNotNow)
                            .frame(maxWidth: .infinity)
                    }
                    .glassControlStyle()
                    .controlSize(.large)
                    .environment(\.menuItemFocused, selection == .notNow)
                    .keyboardShortcut(.cancelAction)
                }
                .modifier(ScrollsWhenShort())
                .padding(30)
                .frame(maxWidth: 520)
                .modalCard(.overlay)
                .modifier(OverlayCardMargins())
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.96).combined(with: .opacity))
            }
            .background(WindowAccessor { hostWindow = $0 })
            .onAppear {
                selection = targetPad == nil
                    ? .playerOne
                    : .newPlayer
            }
            .menuInputBlocking()
            .menuHandlers(move: handleMove, modalActivate: handleActivation, back: handleBack)
        }
    }

    private var targetPad: UInt8? {
        if let pad = store.picking, pad != 0 {
            return pad
        }
        return store.seats.lowestOpenPad
    }

    private var newPlayerTitle: LocalizedStringResource {
        guard let pad = targetPad else {
            return .playbackCouchNewControllerNoFreeSeat
        }
        return .playbackCouchPlayer(number: Int(pad) + 1)
    }

    private func option(_ choice: CouchNewControllerChoice, title: LocalizedStringResource) -> some View {
        let focused = selection == choice
        return FocusButton {
            store.send(.newController(choice))
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .drawsOwnFocusHighlight()
        .background(Color.white.opacity(focused
                ? 0.14
                : 0.05), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(focused
                        ? Palette.accent
                        : Color.white.opacity(0.14), lineWidth: focused
                            ? 3
                            : 1)
            }
    }

    private func move(_ direction: MenuMoveDirection) {
        let seatOpen = targetPad != nil
        switch direction {
        case .left:
            if selection == .newPlayer {
                selection = .playerOne
            }
        case .right:
            if selection == .playerOne, seatOpen {
                selection = .newPlayer
            }
        case .down:
            selection = .notNow
        case .up:
            if selection == .notNow {
                selection = seatOpen
                    ? .newPlayer
                    : .playerOne
            }
        @unknown default:
            break
        }
    }

    private func owns(_ window: PlatformWindow) -> Bool {
        hostWindow.map { $0 === window } != false
    }

    private func handleMove(_ window: PlatformWindow, _ direction: MenuMoveDirection) -> Bool {
        guard owns(window) else {
            return false
        }
        move(direction)
        return true
    }

    private func handleActivation(_ window: PlatformWindow) -> Bool {
        guard owns(window) else {
            return false
        }
        store.send(.newController(selection))
        return true
    }

    private func handleBack(_ window: PlatformWindow) -> Bool {
        guard owns(window) else {
            return false
        }
        store.send(.newController(.notNow))
        return true
    }
}
