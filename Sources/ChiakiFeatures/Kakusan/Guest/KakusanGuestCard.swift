import ChiakiModels
import ComposableArchitecture
import MenuFocus
import SwiftUI

/// The guest's joining card for the current phase.
///
/// Every control it draws is one of the feature's `ChiakiModels/KakusanControlGrid` controls, so controller
/// selection never lands on a control the card does not show.
struct KakusanGuestCard: View {
    /// What a guest is told before joining shares their console session.
    static let disclosureText: LocalizedStringResource = .kakusanGuestDisclosure

    /// The guest.
    @Bindable var store: StoreOf<KakusanGuestFeature>

    var body: some View {
        switch store.join.phase {
        case .idle, .streaming:
            EmptyView()
        case .entering(let error):
            entering(error)
        case .previewing:
            progress(.kakusanGuestJoinGame, symbol: "person.2", status: .kakusanGuestCheckingInvitation)
        case .previewed(let summary), .disclosureAccepted(let summary):
            preview(summary)
        case .preparingReply:
            progress(.kakusanGuestJoinGame, symbol: "person.2", status: .kakusanGuestPreparingReply)
        case let .waitingForHost(_, reply, summary):
            waiting(reply, summary: summary)
        case .connecting:
            progress(
                .kakusanStatusConnecting,
                symbol: "antenna.radiowaves.left.and.right",
                status: .kakusanInviteLookingForPath
            )
        case .verifying(_, let verification):
            verifying(verification)
        case .admitting, .readying:
            seat
        case .leaving:
            progress(.kakusanStatusLeaving, symbol: "rectangle.portrait.and.arrow.right", status: nil)
        case .ended(let outcome):
            ended(outcome)
        }
    }

    @ViewBuilder
    private func entering(_ error: KakusanError?) -> some View {
        KakusanHeader(symbol: "person.2", title: .kakusanGuestJoinGame)
        VStack(alignment: .leading, spacing: 8) {
            Text(.kakusanInviteInvitation)
                .font(.headline)
            KakusanTextBlockField(
                title: .kakusanInviteInvitation,
                text: $store.invitation,
                lines: 4 ... 6,
                selected: store.controls.selection == .text,
                keyboardRequest: store.keyboardRequest
            ) {
                store.send(.view(.invitationSubmitted))
            }
        }
        if let error {
            KakusanErrorText(text: error == .invalidBlock
                ? KakusanBlockAdvice.invitation(store.invitation)
                : error.label)
        }
        HStack(spacing: 10) {
            button(.kakusanGuestPasteInvitation, .paste)
            button(.commonContinue, .connect, prominent: true)
                .disabled(store.invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func preview(_ summary: KakusanInvitationSummary) -> some View {
        KakusanHeader(symbol: "person.2", title: .kakusanGuestInvited)
        Text(store.hostName ?? String(localized: .kakusanInviteNewDevice))
            .font(.title3.weight(.semibold))
        Text(KakusanHostClaim.text(knownAs: store.hostName))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 18) {
            Text(.kakusanGuestRoom(capacity: summary.preview.capacity))
                .font(.callout)
                .foregroundStyle(.secondary)
            KakusanCountdownText(deadline: summary.preview.expiresAt) {
                .kakusanInviteExpiresIn(time: $0)
            }
        }
        disclosure
        HStack(spacing: 10) {
            button(.commonBack, .back)
            button(.kakusanGuestCreateReply, .create, prominent: true)
                .disabled(!store.disclosureAccepted)
        }
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.kakusanGuestSharedAccess)
                .font(.headline)
            Text(Self.disclosureText)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(.kakusanGuestAccept, isOn: Binding(
                get: {
                    store.disclosureAccepted
                },
                set: { accepted in
                    store.send(.setDisclosure(accepted))
                }
            ))
            .toggleStyle(AccentCheckboxToggleStyle(focusable: false))
            .kakusanControl(.accept, in: store.controls)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private func waiting(_ reply: KakusanBlock, summary: KakusanInvitationSummary) -> some View {
        KakusanHeader(symbol: "paperplane", title: .kakusanGuestSendReply)
        KakusanBlockPreview(label: .kakusanInviteReply, block: reply)
        KakusanCopyButton(
            title: .kakusanGuestCopyReply,
            text: reply.text,
            copied: store.copied,
            file: store.shareFile,
            controls: store.controls,
            copy: { store.send(.view(.controlActivated(.copy))) },
            shown: { store.send(.view(.shareShown)) }
        )
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(store.hostName.map { LocalizedStringResource.kakusanGuestWaitingForNamedHost(name: $0) }
                ?? .kakusanGuestWaitingForHost)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            KakusanCountdownText(deadline: summary.preview.expiresAt) {
                .kakusanInviteExpiresIn(time: $0)
            }
        }
        button(.kakusanGuestLeave, .leave)
    }

    @ViewBuilder
    private func verifying(_ verification: KakusanVerification) -> some View {
        KakusanHeader(symbol: "checkmark.shield", title: .kakusanInviteCheckCodes)
        if let peer = store.hostPeer {
            KakusanFingerprintView(title: .kakusanGuestHostFingerprint, fingerprint: peer.fingerprint)
        }
        KakusanCodeDisplay(title: .kakusanInviteYourCode, code: verification.ownCode)
        KakusanCodeField(
            title: store.hostName.map { LocalizedStringResource.kakusanInviteNamedCode(name: $0) }
                ?? .kakusanGuestHostCode,
            code: $store.code,
            selected: store.controls.selection == .code,
            keyboardRequest: store.keyboardRequest,
            submit: { store.send(.view(.codeSubmitted)) }
        )
        if verification.entry == .submitted {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(.kakusanGuestWaitingForHost)
                    .foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 10) {
            button(.kakusanGuestLeave, .leave)
            button(.kakusanInviteVerify, .verify, prominent: true)
                .disabled(KakusanCode(store.code) == nil || verification.entry != .awaiting)
        }
    }

    @ViewBuilder private var seat: some View {
        KakusanHeader(symbol: "chair.lounge", title: .kakusanGuestWaitingForSeat)
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: 60)
        rememberButton
        button(.kakusanGuestLeave, .leave)
    }

    @ViewBuilder
    private func ended(_ outcome: KakusanGuestOutcome) -> some View {
        KakusanHeader(symbol: outcome.symbolName, title: outcome.title)
        if outcome != .failed(.expired) {
            KakusanErrorText(text: outcome.label)
        }
        rememberButton
        button(.kakusanGuestPasteNewInvitation, .create, prominent: true)
    }

    @ViewBuilder private var rememberButton: some View {
        if store.controls.shows(.remember) {
            button(.kakusanGuestRememberHost, .remember)
        }
    }

    @ViewBuilder
    private func progress(
        _ title: LocalizedStringResource,
        symbol: String,
        status: LocalizedStringResource?
    ) -> some View {
        KakusanHeader(symbol: symbol, title: title)
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            if let status {
                Text(status)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        if store.controls.shows(.leave) {
            button(.kakusanGuestLeave, .leave)
        }
    }

    private func button(
        _ title: LocalizedStringResource,
        _ control: KakusanControl,
        prominent: Bool = false
    ) -> some View {
        KakusanActionButton(
            title: title,
            prominent: prominent,
            focused: store.controls.selection == control
        ) {
            store.send(.view(.controlActivated(control)))
        }
    }
}
