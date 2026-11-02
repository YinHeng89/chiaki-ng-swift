import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The console editor sheet: rename the console, change its local address, set it to connect at launch,
/// forget
/// its saved login PIN, delete it, or save the draft.
public struct ConsoleEditor: View {
    /// Routes controller moves to the handler this sheet registers.
    @Environment(\.menuNavigator) var navigator
    /// A controller focus stop of the editor.
    public enum Field: Hashable {
        /// The Close button, the name and address fields, the connect-at-launch toggle, the Forget PIN
        /// button, and
        /// the Delete, Cancel and Save buttons.
        case close, name, address, connectAtLaunch, forgetLoginPIN, delete, cancel, save
    }
    /// The focused stop.
    @MenuFocusState var focusedField: Field?
    @Environment(\.streamerMode) private var streamerMode
    /// The window hosting the sheet, so the focus handler only acts on controller input aimed at it.
    @State var hostWindow: PlatformWindow?
    /// The registration of the controller focus-move handler, removed when the sheet disappears.
    @State var focusHandlerID: MenuHandlerID?
    /// The edited values, as the editor feature holds them.
    public let draft: ConsoleDraft
    /// Reports a typed name.
    public let nameChanged: (String) -> Void
    /// Reports a typed address.
    public let addressChanged: (String) -> Void
    /// Reports a change of the connect-at-launch toggle.
    public let connectAtLaunchChanged: (Bool) -> Void
    /// Marks the saved login PIN to be forgotten on save.
    public let forgetLoginPIN: () -> Void
    /// Closes the editor without saving.
    public let cancel: () -> Void
    /// Saves the draft.
    public let save: () -> Void
    /// Asks to delete the console.
    public let delete: () -> Void

    @Environment(\.screenLayout) private var screenLayout

    @ViewBuilder private var layout: some View {
        if screenLayout.isCompact {
            VStack(alignment: .leading, spacing: 14) {
                heading
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        identity
                        connections
                        launch
                        details
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                actions
            }
            .padding(18)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                heading
                identity
                connections
                launch
                details
                actions
            }
            .padding(30)
        }
    }

    public var body: some View {
        layout
            .background(WindowAccessor { hostWindow = $0 })
            .onAppear {
                registerFocusHandler()
                focusInitialField()
            }
            .onDisappear {
                if let focusHandlerID {
                    navigator?.handlers.unregister(focusHandlerID)
                    self.focusHandlerID = nil
                }
            }
    }

    private var heading: some View {
        return HStack(spacing: 18) {
            ConsoleArtwork(height: 82, kind: consoleKind)
                .frame(width: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit console")
                    .font(.title2.bold())
                Text(draft.generation)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            FocusButton(action: cancel) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .glassControlStyle()
            .focusBorderShape(.circle)
            .menuFocused($focusedField, equals: .close)
            .keyboardShortcut(.cancelAction)
            .help("Close console editor")
            .accessibilityLabel("Close console editor")
        }
    }

    private var identity: some View {
        editorSection("Identity") {
            editorField(
                "Name",
                value: draft.name,
                prompt: "Living room",
                focus: .name,
                changed: nameChanged
            )
        }
    }

    private var connections: some View {
        editorSection("Connections") {
            VStack(spacing: 12) {
                editorField(
                    "Local address",
                    value: draft.address,
                    prompt: "192.168.1.50 or console.local",
                    focus: .address,
                    changed: addressChanged
                )
                HStack(spacing: 10) {
                    capability("Local", icon: "wifi", available: true)
                    capability("Remote", icon: "globe", available: draft.remoteAvailable)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder private var details: some View {
        if let hardwareID = draft.hardwareID {
            editorSection("Details") {
                editorRow("Hardware ID") {
                    Text(StreamerMode.identifier(hardwareID, enabled: streamerMode))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: screenLayout.controlSpacing) {
            FocusButton("Delete console", systemImage: AppIcon.deleteAccount.rawValue, role: .destructive) {
                delete()
            }
            .glassControlStyle()
            .menuFocused($focusedField, equals: .delete)
            Spacer()
            FocusButton("Cancel", action: cancel)
                .glassControlStyle()
                .menuFocused($focusedField, equals: .cancel)
                .keyboardShortcut(.cancelAction)
            FocusButton("Save changes", action: save)
                .glassProminentControlStyle()
                .menuFocused($focusedField, equals: .save)
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
        }
    }

    /// The width of the label column beside a field when the row has room for it.
    static let labelWidth: CGFloat = 120

    /// A labelled editor row: the label in its column beside the content when that fits, and above it
    /// otherwise.
    ///
    /// - Parameters:
    ///   - label: The row's caption.
    ///   - content: The field, status or value the row holds.
    /// - Returns: The row.
    func editorRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        let content = content()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth, alignment: .leading)
                content
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    content
                }
            }
        }
    }

    /// A titled, rounded group of editor rows.
    ///
    /// - Parameters:
    ///   - title: The caption above the group.
    ///   - content: The rows.
    /// - Returns: The section.
    public func editorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
                .background(.primary.opacity(0.055), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
                }
        }
    }

    private func editorField(
        _ label: String,
        value: String,
        prompt: String,
        focus focusTarget: Field,
        changed: @escaping (String) -> Void
    ) -> some View {
        let binding = Binding(
            get: { value },
            set: { changed($0) }
        )
        return editorRow(label) {
            TextField(
                prompt,
                text: binding
            )
            .textFieldStyle(.plain)
            .frame(idealWidth: Self.fieldIdealWidth)
            .streamerHiddenField(value, active: focusTarget == .address)
            .menuFocusBinding($focusedField, equals: focusTarget)
            .controllerKeyboard(
                title: label,
                text: binding,
                isFocused: focusedField == focusTarget
            )
        }
        .padding(12)
    }

    /// The width a field asks for beside its label, so the row stacks only when the card is narrower than
    /// both, not when the typed text grows.
    static let fieldIdealWidth: CGFloat = 220

    private func capability(_ label: String, icon: String, available: Bool) -> some View {
        HStack(spacing: 10) {
            Label(label, systemImage: icon)
                .fontWeight(.medium)
            Spacer()
            Text(capabilityStatus(available))
                .font(.caption.weight(.semibold))
                .foregroundStyle(capabilityColor(available))
            Image(systemName: capabilityIcon(available))
                .foregroundStyle(capabilityColor(available))
        }
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 11))
    }

    private var consoleKind: RegistrationFlow.ConsoleKind {
        if draft.generation == RegistrationFlow.ConsoleKind.ps4.rawValue {
            return .ps4
        }
        return .ps5
    }

    private func capabilityStatus(_ available: Bool) -> String {
        if available {
            return "Ready"
        }
        return "Not set up"
    }

    private func capabilityIcon(_ available: Bool) -> String {
        if available {
            return "checkmark.circle.fill"
        }
        return "minus.circle"
    }

    private func capabilityColor(_ available: Bool) -> Color {
        if available {
            return .green
        }
        return .secondary
    }

    /// Whether the draft can be saved: a name of up to 100 characters and an address of up to 253 bytes
    /// without
    /// whitespace.
    public var valid: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 100 && !address.isEmpty
            && address.utf8.count <= 253
            && !address.contains(where: {
                $0.isWhitespace
            })
    }
}

extension ConsoleEditor {
    /// The bottom row of buttons, left to right; Save is left out while the draft is invalid.
    public var actionRow: [Field] {
        valid
            ? [.delete, .cancel, .save]
            : [.delete, .cancel]
    }

    /// Registers the handler that moves focus on controller input aimed at the editor's window, unless text
    /// is
    /// being edited.
    public func registerFocusHandler() {
        guard focusHandlerID == nil else {
            return
        }
        focusHandlerID = navigator?.handlers.registerFocusMove { window, direction in
            guard window === hostWindow,
                  !(navigator?.inputGate.isBlocking ?? false),
                  !(navigator?.isTrackingMenu ?? false),
                  !(navigator?.isEditingText(in: window) ?? false) else {
                return false
            }
            move(direction)
            return true
        }
    }

    /// Focuses the name field once the sheet is on screen, retrying briefly until focus sticks.
    public func focusInitialField() {
        Task { @MainActor in
            for attempt in 0..<20 {
                await Task.yield()
                guard focusHandlerID != nil, hostWindow.map({ WindowFocus($0).isOnScreen }) != false else {
                    return
                }
                if attempt == 0 {
                    focusedField = .name
                } else if focusedField != nil {
                    return
                } else {
                    if let window = hostWindow {
                        navigator?.resignFocus(in: window)
                    }
                    focusedField = .name
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func move(_ direction: MenuMoveDirection) {
        guard let current = focusedField else {
            focusedField = .name
            return
        }
        switch direction {
        case .up, .down:
            moveVertically(from: current, down: direction == .down)
        case .left, .right:
            moveHorizontally(from: current, right: direction == .right)
        @unknown default:
            break
        }
    }

    /// The vertical column of stops above the button row; Forget PIN is included only while a PIN is saved.
    public var column: [Field] {
        draft.loginPIN == .saved
            ? [.close, .name, .address, .connectAtLaunch, .forgetLoginPIN]
            : [.close, .name, .address, .connectAtLaunch]
    }

    private func moveVertically(from current: Field, down: Bool) {
        if actionRow.contains(current) {
            if !down {
                focusedField = column.last
            }
            return
        }
        guard let index = column.firstIndex(of: current) else {
            return
        }
        if down {
            focusedField = index + 1 < column.count
                ? column[index + 1]
                : actionRow.last
        } else if index > 0 {
            focusedField = column[index - 1]
        }
    }

    private func moveHorizontally(from current: Field, right: Bool) {
        guard let index = actionRow.firstIndex(of: current) else {
            return
        }
        let next = right
            ? index + 1
            : index - 1
        if actionRow.indices.contains(next) {
            focusedField = actionRow[next]
        }
    }
}

extension ConsoleEditor {
    /// The Launch section: the connect-at-launch toggle and the login PIN status with its Forget PIN button.
    public var launch: some View {
        editorSection("Launch") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Connect at launch", isOn: Binding(
                        get: { draft.connectAtLaunch },
                        set: { connectAtLaunchChanged($0) }
                    ))
                    .toggleStyle(AccentCheckboxToggleStyle(focusable: false))
                    .menuFocusable()
                    .menuFocusBinding($focusedField, equals: .connectAtLaunch)
                    .focusEffectDisabled()
                    .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
                        connectAtLaunchChanged(!draft.connectAtLaunch)
                        return .handled
                    }
                    .environment(\.menuItemFocused, focusedField == .connectAtLaunch)
                    Text("chiaki-ng wakes this console and starts streaming when it opens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 23)
                }
                editorRow("Login PIN") {
                    Text(loginPINStatus)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if draft.loginPIN == .saved {
                        FocusButton("Forget PIN") {
                            focusedField = .connectAtLaunch
                            forgetLoginPIN()
                        }
                        .glassControlStyle()
                        .controlSize(.small)
                        .menuFocused($focusedField, equals: .forgetLoginPIN)
                        .accessibilityHint("Removes the saved login PIN when you save changes")
                    }
                }
            }
            .padding(12)
        }
    }

    private var loginPINStatus: String {
        switch draft.loginPIN {
        case .none:
            "Not saved"
        case .saved:
            "Saved and sent automatically"
        case .forgotten:
            "Forgotten when you save"
        }
    }
}

/// The console editor presented as the root's `consoleEditor` destination, over a dimmed screen.
///
/// It shows the editor card while there is a draft; the deletion question and failures are shown by the
/// root's confirmation card.
public struct ConsoleEditorModal: View {
    /// The presented editor.
    public let store: StoreOf<ConsoleEditorFeature>

    /// The size of the window the modal is centred in.
    public let size: CGSize

    @Environment(\.screenLayout) private var layout

    /// Creates a console editor modal.
    ///
    /// - Parameters:
    ///   - store: The presented editor.
    ///   - size: The size of the window the modal is centred in.
    public init(store: StoreOf<ConsoleEditorFeature>, size: CGSize) {
        self.store = store
        self.size = size
    }

    /// The view.
    public var body: some View {
        if let draft = store.flow.draft {
            ZStack {
                Dimming.light.color
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.view(.cancel))
                    }
                    .accessibilityLabel("Dismiss console editor")
                ConsoleEditor(
                    draft: draft,
                    nameChanged: {
                        store.send(.view(.setName($0)))
                    },
                    addressChanged: {
                        store.send(.view(.setAddress($0)))
                    },
                    connectAtLaunchChanged: {
                        store.send(.view(.setConnectAtLaunch($0)))
                    },
                    forgetLoginPIN: {
                        store.send(.view(.forgetLoginPIN))
                    },
                    cancel: {
                        store.send(.view(.cancel))
                    },
                    save: {
                        store.send(.view(.confirm))
                    },
                    delete: {
                        store.send(.view(.delete))
                    }
                )
                .frame(maxWidth: cardWidth)
                .menuFocusSection()
                .modalCard(.app)
            }
            .ignoresSafeArea(.container)
        }
    }

    /// The margin a card that spans the window keeps from its sides.
    static let fillMargin: CGFloat = 16

    private var cardWidth: CGFloat {
        if layout.sheetsFillWidth {
            return max(0, size.width - 2 * max(Self.fillMargin, layout.sideInset))
        }
        return min(620, max(0, size.width - 40))
    }
}
