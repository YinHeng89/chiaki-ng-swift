import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// One guest's invitation card: the invitation, the reply, code checks and how the attempt ended.
///
/// Every control it draws is one of the invite feature's `ChiakiModels/KakusanControlGrid` controls, and
/// every press is sent to the feature as `ChiakiFeatures/KakusanInviteFeature/Action/View/controlActivated(_:)`.
struct KakusanInviteCard: View {
    /// The card's drafts and selection.
    @Bindable var store: StoreOf<KakusanInviteFeature>
    /// The guest the card shows.
    let guest: KakusanHostFeature.Guest
    /// The host, for seats, hosting and the cooldown.
    let host: KakusanHostFeature.State

    var body: some View {
        KakusanModal(
            width: 560,
            controls: store.controls,
            move: { store.send(.view(.moved($0))) },
            activate: activate,
            back: { store.send(.view(.backPressed)) },
            content: { content }
        )
    }

    private func activate(_ control: KakusanControl) {
        store.send(.view(.controlActivated(control)))
    }

    @ViewBuilder private var content: some View {
        switch guest.attempt.phase {
        case .preparing:
            header("person.badge.plus", .kakusanStatusPreparing)
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
            action(.kakusanInviteCancelInvitation, .cancel, destructive: true)
        case let .invitation(invitation, progress):
            invitationContent(invitation, progress: progress)
        case .connecting:
            header("antenna.radiowaves.left.and.right", .kakusanStatusConnecting)
            peerSection
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(.kakusanInviteLookingForPath)
                    .foregroundStyle(.secondary)
            }
            action(.commonCancel, .cancel, destructive: true)
        case let .verifying(_, verification):
            verifyingContent(verification)
        case .closing:
            header("person.badge.minus", .kakusanInviteClosing)
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
        case .admitting, .readying, .active, .ended:
            endedContent
        }
    }

    @ViewBuilder
    private func invitationContent(_ invitation: KakusanInvitation,
                                   progress: KakusanReplyImport) -> some View {
        header("person.badge.plus", .kakusanInviteTitle) {
            if let seats = host.seats {
                Text(.kakusanInviteSeatsFree(free: seats.free, capacity: seats.capacity))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        KakusanBlockPreview(label: .kakusanInviteInvitation, block: invitation.block)
        KakusanCopyButton(
            title: .kakusanInviteCopyInvitation,
            text: invitation.block.text,
            copied: store.copied,
            file: store.shareFile,
            controls: store.controls,
            copy: { activate(.copy) },
            shown: { store.send(.view(.shareShown)) }
        )
        KakusanCountdownText(deadline: invitation.expiresAt) {
            .kakusanInviteExpiresIn(time: $0)
        }
        if !host.expectations.isEmpty {
            expectationChips
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(.kakusanInviteReply)
                    .font(.headline)
                Spacer(minLength: 12)
                KakusanIconButton(
                    symbol: "doc.on.clipboard",
                    label: .kakusanInvitePasteReply,
                    focused: store.controls.selection == .paste
                ) {
                    activate(.paste)
                }
            }
            KakusanTextBlockField(
                title: .kakusanInviteReply,
                text: $store.reply,
                lines: 3 ... 4,
                selected: store.controls.selection == .text,
                keyboardRequest: store.keyboardRequest
            )
        }
        if case .rejected(let error) = progress {
            KakusanErrorText(text: error == .invalidBlock
                ? KakusanBlockAdvice.reply(store.reply)
                : error.label)
        }
        HStack(spacing: 10) {
            action(.kakusanInviteCancelInvitation, .cancel, destructive: true)
            action(.kakusanInviteConnect, .connect, prominent: true)
                .disabled(store.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Self
                    .importing(progress))
        }
    }

    private static func importing(_ progress: KakusanReplyImport) -> Bool {
        if case .importing = progress {
            return true
        }
        return false
    }

    private var expectationChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.kakusanInviteExpectedFor)
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(host.expectations, id: \.self) { name in
                    let chosen = guest.expected == name
                    FocusButton(name ?? String(localized: .kakusanInviteNewDevice)) {
                        activate(.expect(name))
                    }
                    .glassControlStyle()
                    .tint(chosen
                        ? Palette.accent
                        : nil)
                        .accessibilityAddTraits(chosen
                            ? .isSelected
                            : [])
                            .kakusanControl(.expect(name), in: store.controls)
                }
            }
        }
    }

    @ViewBuilder private var peerSection: some View {
        if let peer = guest.attempt.peer {
            Text(guest.name ?? String(localized: .kakusanInviteNewDevice))
                .font(.title3.weight(.semibold))
            if case .changedKey(let saved) = guest.recognition {
                KakusanErrorText(text: .kakusanInviteChangedKey(name: saved.nickname))
            }
            KakusanFingerprintView(title: .kakusanInviteDeviceFingerprint, fingerprint: peer.fingerprint)
        }
    }

    @ViewBuilder
    private func verifyingContent(_ verification: KakusanVerification) -> some View {
        KakusanHeader(symbol: "checkmark.shield", title: .kakusanInviteCheckCodes)
        if guest.attempt.peer != nil {
            Text(guest.name ?? String(localized: .kakusanInviteNewDevice))
                .font(.title3.weight(.semibold))
        }
        if case .changedKey(let saved) = guest.recognition {
            KakusanErrorText(text: .kakusanInviteChangedKey(name: saved.nickname))
        }
        KakusanCodeDisplay(title: .kakusanInviteYourCode, code: verification.ownCode)
        KakusanCodeField(
            title: guest.name.map { LocalizedStringResource.kakusanInviteNamedCode(name: $0) }
                ?? .kakusanInviteTheirCode,
            code: $store.code,
            selected: store.controls.selection == .code,
            keyboardRequest: store.keyboardRequest,
            submit: { store.send(.view(.codeSubmitted)) }
        )
        if verification.entry == .submitted {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(.kakusanInviteWaitingForPlayer)
                    .foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 10) {
            action(.commonCancel, .cancel, destructive: true)
            action(.kakusanInviteVerify, .verify, prominent: true)
                .disabled(KakusanCode(store.code) == nil || verification.entry != .awaiting)
        }
    }

    @ViewBuilder private var endedContent: some View {
        let outcome = guest.attempt.outcome ?? .cancelled
        header(outcome.symbolName, outcome.title)
        if outcome != .failed(.expired) {
            KakusanErrorText(text: outcome.label)
        }
        if case .unavailable(let error) = host.hosting {
            KakusanErrorText(text: error.label)
        }
        if let until = host.cooldownUntil {
            KakusanCountdownText(deadline: until) {
                .kakusanInviteTryAgainIn(time: $0)
            }
        }
        action(.kakusanInviteCreateNew, .create, prominent: true)
            .disabled(!host.invitesOpen)
    }

    private func header(_ symbol: String, _ title: LocalizedStringResource) -> some View {
        header(symbol, title) {
            EmptyView()
        }
    }

    private func header(_ symbol: String, _ title: LocalizedStringResource,
                        @ViewBuilder detail: () -> some View) -> some View {
        HStack(spacing: 12) {
            KakusanHeader(symbol: symbol, title: title)
            Spacer(minLength: 12)
            detail()
            KakusanIconButton(
                symbol: "xmark",
                label: .commonClose,
                focused: store.controls.selection == .close
            ) {
                activate(.close)
            }
        }
    }

    private func action(
        _ title: LocalizedStringResource,
        _ control: KakusanControl,
        prominent: Bool = false,
        destructive: Bool = false
    ) -> some View {
        KakusanActionButton(
            title: title,
            prominent: prominent,
            destructive: destructive,
            focused: store.controls.selection == control
        ) {
            activate(control)
        }
    }
}

/// A round glass icon button on a Kakusan card.
private struct KakusanIconButton: View {
    /// The SF Symbol shown.
    public let symbol: String
    /// The button's accessible name and help.
    public let label: LocalizedStringResource
    /// Whether controller navigation selected the button.
    public let focused: Bool
    /// What the button does.
    public let perform: () -> Void

    /// Creates a Kakusan icon button.
    ///
    /// - Parameters:
    ///   - symbol: The SF Symbol shown.
    ///   - label: The button's accessible name and help.
    ///   - focused: Whether controller navigation selected the button.
    ///   - perform: What the button does.
    public init(
        symbol: String,
        label: LocalizedStringResource,
        focused: Bool,
        perform: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.label = label
        self.focused = focused
        self.perform = perform
    }

    public var body: some View {
        FocusButton(action: perform) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
        }
        .glassControlStyle()
        .focusBorderShape(.circle)
        .help(Text(label))
        .accessibilityLabel(label)
        .environment(\.menuItemFocused, focused)
    }
}
