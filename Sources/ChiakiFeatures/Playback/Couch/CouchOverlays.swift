import PlatformUI
import SwiftUI
import ComposableArchitecture
import ChiakiModels
import DesignSystem
import MenuFocus

/// Asks which saved account a new player or remote guest joins with, and notes why some cannot be chosen.
struct CouchAccountPickerOverlay: View {
    /// The menu navigator the overlay registers its controller handlers with.
    @Environment(\.menuNavigator) var navigator
    /// The couch, which owns the choice.
    let store: StoreOf<CouchReducer>
    @State private var presentationID = UUID()
    @State private var hostWindow: PlatformWindow?
    @State private var selection = 0
    @State private var moveHandlerID: MenuHandlerID?
    @State private var activationHandlerID: MenuHandlerID?
    @State private var backHandlerID: MenuHandlerID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout

    var body: some View {
        if let choice = store.choosing {
            ZStack {
                Dimming.standard.color
                VStack(spacing: 22) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 26, weight: .medium))
                        .frame(width: 56, height: 56)
                        .glassEffect(AppGlass.control, in: .circle)
                    VStack(spacing: 8) {
                        Text(store.seats.accountQuestion(for: choice))
                            .font(.title2.weight(.semibold))
                        Text(.playbackCouchAccountMustBeUser)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if store.accounts.isEmpty {
                        Text(.playbackCouchLoadingAccounts)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 120)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                                tile(account, index: index, choice: choice)
                            }
                        }
                    }
                    FocusButton {
                        cancel(choice)
                    } label: {
                        Text(.commonCancel)
                            .frame(maxWidth: .infinity)
                    }
                    .glassControlStyle()
                    .controlSize(.large)
                    .environment(\.menuItemFocused, selection == store.accounts.count)
                    .keyboardShortcut(.cancelAction)
                }
                .modifier(ScrollsWhenShort())
                .padding(30)
                .frame(maxWidth: 640)
                .modalCard(.overlay)
                .modifier(OverlayCardMargins())
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.96).combined(with: .opacity))
            }
            .background(WindowAccessor { hostWindow = $0 })
            .onAppear {
                selection = firstAvailable(choice)
                register()
            }
            .onChange(of: choice) { _, next in
                selection = firstAvailable(next)
            }
            .onDisappear(perform: unregister)
        }
    }

    private func tile(_ account: AccountProfile, index: Int, choice: CouchAccountChoice) -> some View {
        let availability = availability(of: account, for: choice)
        let focused = selection == index
        return FocusButton {
            choose(account, for: choice)
        } label: {
            VStack(spacing: 8) {
                avatar(account)
                Text(account.name)
                    .font(.headline)
                    .lineLimit(1)
                if let note = note(availability) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(availability == .unrecognised
                            ? CouchTone.failed.color
                            : .secondary)
                            .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .drawsOwnFocusHighlight()
        .disabled(availability != .available)
        .opacity(availability == .available
            ? 1
            : 0.5)
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

    @ViewBuilder
    private func avatar(_ account: AccountProfile) -> some View {
        if let data = account.avatarData, let image = PlatformImage(data: data) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(.circle)
        } else {
            Text(String(account.name.prefix(1)).uppercased())
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(.quaternary, in: .circle)
        }
    }

    private func note(_ availability: CouchAccountAvailability) -> LocalizedStringResource? {
        switch availability {
        case .available:
            nil
        case .host:
            .playbackCouchPlayer(number: 1)
        case .seated(let other):
            .playbackCouchPlayer(number: Int(other) + 1)
        case .joiningRemote:
            .playbackCouchAccountJoining
        case .unrecognised:
            .playbackCouchAccountNotOnConsole
        }
    }

    private func firstAvailable(_ choice: CouchAccountChoice) -> Int {
        store.accounts.firstIndex { availability(of: $0, for: choice) == .available }
            ?? store.accounts.count
    }

    private func availability(
        of account: AccountProfile,
        for choice: CouchAccountChoice
    ) -> CouchAccountAvailability {
        switch choice {
        case .pad(let pad):
            store.seats.availability(of: account, for: pad)
        case .remote:
            store.seats.availability(of: account, for: nil)
        }
    }

    private func choose(_ account: AccountProfile, for choice: CouchAccountChoice) {
        switch choice {
        case .pad(let pad):
            store.send(.chooseAccount(pad: pad, account: account.id))
        case .remote(let guest):
            store.send(.chooseRemoteAccount(guest: guest, account: account.id))
        }
    }

    private func cancel(_ choice: CouchAccountChoice) {
        store.send(Self.cancellation(of: choice))
    }

    /// The action that backs out of an account choice.
    ///
    /// - Parameter choice: The choice that is open now.
    /// - Returns: The cancellation for that pad or remote guest.
    static func cancellation(of choice: CouchAccountChoice) -> CouchReducer.Action {
        switch choice {
        case .pad(let pad):
            .cancel(pad: pad)
        case .remote(let guest):
            .cancelRemote(guest)
        }
    }

    private func move(_ direction: MenuMoveDirection, choice: CouchAccountChoice) {
        let count = store.accounts.count
        switch direction {
        case .left:
            selection = max(0, min(selection, count) - 1)
        case .right:
            selection = min(count, selection + 1)
        case .down:
            selection = count
        case .up:
            if selection == count {
                selection = firstAvailable(choice)
            }
        @unknown default:
            break
        }
    }

    private func activate(_ choice: CouchAccountChoice) {
        guard selection < store.accounts.count else {
            cancel(choice)
            return
        }
        let account = store.accounts[selection]
        guard availability(of: account, for: choice) == .available else {
            return
        }
        choose(account, for: choice)
    }

    private func owns(_ window: PlatformWindow) -> Bool {
        hostWindow.map { $0 === window } != false
    }

    private func register() {
        navigator?.inputGate.presentations.insert(presentationID)
        moveHandlerID = navigator?.handlers.registerFocusMove { window, direction in
            guard owns(window), let choice = store.choosing else {
                return false
            }
            move(direction, choice: choice)
            return true
        }
        activationHandlerID = navigator?.handlers.registerModalActivation { window in
            guard owns(window), let choice = store.choosing else {
                return false
            }
            activate(choice)
            return true
        }
        backHandlerID = navigator?.handlers.registerBack { window in
            guard owns(window), let choice = store.choosing else {
                return false
            }
            cancel(choice)
            return true
        }
    }

    private func unregister() {
        navigator?.inputGate.presentations.remove(presentationID)
        if let moveHandlerID {
            navigator?.handlers.unregister(moveHandlerID)
        }
        if let activationHandlerID {
            navigator?.handlers.unregister(activationHandlerID)
        }
        if let backHandlerID {
            navigator?.handlers.unregister(backHandlerID)
        }
        moveHandlerID = nil
        activationHandlerID = nil
        backHandlerID = nil
    }
}

/// Shows the couch's notices in the top trailing corner; clicking one dismisses it.
struct CouchNoticesOverlay: View {
    /// The couch, which owns the notices.
    let store: StoreOf<CouchReducer>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(store.notices) { item in
                HStack(spacing: 12) {
                    Capsule()
                        .fill(item.notice.tone.color)
                        .frame(width: 5, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.notice.title)
                            .font(.callout.weight(.semibold))
                        if let detail = item.notice.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 340, alignment: .leading)
                .glassPanel(.medium)
                .onTapGesture {
                    store.send(.dismissNotice(item.id))
                }
                .transition(reduceMotion
                    ? .opacity
                    : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.top, 96)
        .padding(.trailing, 28 + layout.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(AppMotion.animation(reduced: reduceMotion), value: store.notices)
        .allowsHitTesting(!store.notices.isEmpty)
    }
}

/// Lets a modal card's content scroll on a short screen, where the card would otherwise run off the top and
/// bottom, and leaves it in place on a tall one.
struct ScrollsWhenShort: ViewModifier {
    @Environment(\.screenLayout) private var layout

    /// Wraps the content in a vertical scroll view when the screen is short.
    @ViewBuilder
    func body(content: Content) -> some View {
        if layout.isShort {
            ScrollView(.vertical) {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

/// Keeps a modal card over the stream clear of the screen's edges and side inset, so a fixed card width
/// becomes the smaller of that width and the room left between the margins.
struct OverlayCardMargins: ViewModifier {
    @Environment(\.screenLayout) private var layout

    /// Pads the card on every side.
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, max(16, layout.sideInset))
            .padding(.top, 16)
            .padding(.bottom, max(16, layout.bottomChromeInset))
    }
}
