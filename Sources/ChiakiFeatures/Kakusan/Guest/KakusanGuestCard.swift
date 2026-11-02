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
    static let disclosureText = "The host’s shared access lasts for their whole console session. "
        + "Leaving stops the stream but doesn’t erase the shared key from this device."

    /// The guest.
    @Bindable var store: StoreOf<KakusanGuestFeature>

    var body: some View {
        switch store.join.phase {
        case .idle, .streaming:
            EmptyView()
        case .entering(let error):
            entering(error)
        case .previewing:
            progress("Join a game", symbol: "person.2", status: "Checking the invitation")
        case .previewed(let summary), .disclosureAccepted(let summary):
            preview(summary)
        case .preparingReply:
            progress("Join a game", symbol: "person.2", status: "Preparing your reply")
        case let .waitingForHost(_, reply, summary):
            waiting(reply, summary: summary)
        case .connecting:
            progress(
                "Connecting",
                symbol: "antenna.radiowaves.left.and.right",
                status: "Looking for a direct path"
            )
        case .verifying(_, let verification):
            verifying(verification)
        case .admitting, .readying:
            seat
        case .leaving:
            progress("Leaving", symbol: "rectangle.portrait.and.arrow.right", status: nil)
        case .ended(let outcome):
            ended(outcome)
        }
    }

    @ViewBuilder
    private func entering(_ error: KakusanError?) -> some View {
        KakusanHeader(symbol: "person.2", title: "Join a game")
        VStack(alignment: .leading, spacing: 8) {
            Text("Invitation")
                .font(.headline)
            KakusanTextBlockField(
                title: "Invitation",
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
            button("Paste invitation", .paste)
            button("Continue", .connect, prominent: true)
                .disabled(store.invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func preview(_ summary: KakusanInvitationSummary) -> some View {
        KakusanHeader(symbol: "person.2", title: "You’re invited to play")
        Text(store.hostName ?? "New device")
            .font(.title3.weight(.semibold))
        Text(KakusanHostClaim.text(knownAs: store.hostName))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 18) {
            Text("Room for \(summary.preview.capacity) players")
                .font(.callout)
                .foregroundStyle(.secondary)
            KakusanCountdownText(prefix: "Expires in", deadline: summary.preview.expiresAt)
        }
        disclosure
        HStack(spacing: 10) {
            button("Back", .back)
            button("Create reply", .create, prominent: true)
                .disabled(!store.disclosureAccepted)
        }
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared access")
                .font(.headline)
            Text(Self.disclosureText)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("I accept", isOn: Binding(
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
        KakusanHeader(symbol: "paperplane", title: "Send your reply")
        KakusanBlockPreview(label: "Reply", block: reply)
        KakusanCopyButton(
            title: "Copy reply",
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
            Text("Waiting for \(store.hostName ?? "the host")")
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            KakusanCountdownText(prefix: "Expires in", deadline: summary.preview.expiresAt)
        }
        button("Leave", .leave)
    }

    @ViewBuilder
    private func verifying(_ verification: KakusanVerification) -> some View {
        KakusanHeader(symbol: "checkmark.shield", title: "Check codes")
        if let peer = store.hostPeer {
            KakusanFingerprintView(title: "Host fingerprint", fingerprint: peer.fingerprint)
        }
        KakusanCodeDisplay(title: "Your code", code: verification.ownCode)
        KakusanCodeField(
            title: store.hostName.map { "\($0)’s code" } ?? "Host’s code",
            code: $store.code,
            selected: store.controls.selection == .code,
            keyboardRequest: store.keyboardRequest,
            submit: { store.send(.view(.codeSubmitted)) }
        )
        if verification.entry == .submitted {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for the host")
                    .foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 10) {
            button("Leave", .leave)
            button("Verify", .verify, prominent: true)
                .disabled(KakusanCode(store.code) == nil || verification.entry != .awaiting)
        }
    }

    @ViewBuilder private var seat: some View {
        KakusanHeader(symbol: "chair.lounge", title: "Waiting for a seat")
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: 60)
        rememberButton
        button("Leave", .leave)
    }

    @ViewBuilder
    private func ended(_ outcome: KakusanGuestOutcome) -> some View {
        KakusanHeader(symbol: outcome.symbolName, title: outcome.title)
        if outcome != .failed(.expired) {
            KakusanErrorText(text: outcome.label)
        }
        rememberButton
        button("Paste a new invitation", .create, prominent: true)
    }

    @ViewBuilder private var rememberButton: some View {
        if store.controls.shows(.remember) {
            button("Remember host", .remember)
        }
    }

    @ViewBuilder
    private func progress(_ title: String, symbol: String, status: String?) -> some View {
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
            button("Leave", .leave)
        }
    }

    private func button(_ title: String, _ control: KakusanControl, prominent: Bool = false) -> some View {
        KakusanActionButton(
            title: title,
            prominent: prominent,
            focused: store.controls.selection == control
        ) {
            store.send(.view(.controlActivated(control)))
        }
    }
}
