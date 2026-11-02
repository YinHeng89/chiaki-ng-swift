import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import DesignSystem
import MenuFocus

/// A card that sets how the virtual touchpad is opened: a recorded keyboard shortcut, where a hardware keyboard
/// shortcut can be recorded, and an optional two-button controller combo whose buttons swap rather than repeat.
struct TouchpadShortcutCard: View {
    /// The controls settings feature whose draft touchpad shortcut the card edits and records.
    let store: StoreOf<ControlsSettingsFeature>
    private static let buttonChoices = Array(0...20)

    private var shortcut: TouchpadShortcut {
        store.draft.touchpadShortcut
    }

    private var onScreen: Binding<Bool> {
        Binding(
            get: {
                store.draft.onScreenTouchpad
            },
            set: { value in
                var draft = store.draft
                draft.onScreenTouchpad = value
                store.send(.edit(draft))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Virtual touchpad").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show the on-screen touchpad", isOn: onScreen)
                Text("When off, the touchpad never appears over the stream, even from the shortcut or combo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            shortcutControls
                .disabled(!store.draft.onScreenTouchpad)
        }
        .padding(20)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
        .background(ShortcutRecorder(id: store.shortcutCapture) { id, chord in
            store.send(.recordedTouchpadShortcut(id, chord))
        } cancel: {
            store.send(.cancelTouchpadShortcut)
        })
        .disabled(!store.isEditable)
    }

    private var shortcutControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
                HStack {
                    Text("Keyboard shortcut")
                    Spacer()
                    FocusButton {
                        if store.shortcutCapture == nil {
                            store.send(.recordTouchpadShortcut)
                        } else {
                            store.send(.cancelTouchpadShortcut)
                        }
                    } label: {
                        Text(store.shortcutCapture == nil
                            ? shortcut.key?.title ?? "Record shortcut"
                            : "Press a shortcut…")
                            .frame(minWidth: 90)
                    }
                    .glassControlStyle()
                    .accessibilityLabel("Virtual touchpad keyboard shortcut")
                }
            #endif
            Toggle("Controller combo", isOn: Binding(get: { !shortcut.buttons.isEmpty }, set: { enabled in
                store.send(.setTouchpadButtons(enabled
                        ? TouchpadShortcut.standard.buttons
                        : []))
            }))
            if shortcut.buttons.count >= 2 {
                HStack(spacing: 8) {
                    Text("Buttons")
                    Spacer()
                    picker(slot: 0)
                    Text("+").foregroundStyle(.secondary)
                    picker(slot: 1)
                }
            }
        }
    }

    private func picker(slot: Int) -> some View {
        Picker("Button \(slot + 1)", selection: Binding(get: { shortcut.buttons[slot] }, set: { code in
            choose(code, slot: slot)
        })) {
            ForEach(Self.buttonChoices, id: \.self) { code in
                Text(BindingRow.buttonName(code)).tag(code)
            }
        }
        .labelsHidden()
        .nativeFocusHighlight()
        .frame(maxWidth: 180)
    }

    private func choose(_ code: Int, slot: Int) {
        var buttons = shortcut.buttons
        if let existing = buttons.firstIndex(of: code), existing != slot {
            buttons.swapAt(existing, slot)
        } else {
            buttons[slot] = code
        }
        store.send(.setTouchpadButtons(buttons))
    }
}

#if os(macOS)
    /// An invisible view that, while a shortcut recording is active, captures the next key chord in its
    /// window; Escape alone or the window losing key status cancels, and chords without an anchor modifier
    /// are swallowed and ignored.
    struct ShortcutRecorder: NSViewRepresentable {
        /// The ID of the recording in progress; the key monitor is installed only while this is set.
        let id: UUID?
        /// Called with the recording ID and the captured key chord.
        let receive: (UUID, KeyChord) -> Void
        /// Cancels the recording.
        let cancel: () -> Void
        @Environment(\.menuNavigator) private var navigator

        /// Creates the recorder view.
        func makeNSView(context: Context) -> RecorderView {
            RecorderView()
        }

        /// Hands the recording ID, callbacks and navigator to the view and installs or removes its key
        /// monitor.
        func updateNSView(_ view: RecorderView, context: Context) {
            view.id = id
            view.receive = receive
            view.cancel = cancel
            view.navigator = navigator
            view.updateMonitor()
        }

        /// Removes the key monitor when SwiftUI tears the view down.
        static func dismantleNSView(_ view: RecorderView, coordinator: ()) {
            view.removeMonitor()
        }

        /// The AppKit view that owns the local key-down monitor and marks its window as capturing keys so the
        /// menu navigator leaves key presses alone.
        final class RecorderView: NSView {
            /// The virtual key code of Escape, which cancels a recording when pressed without modifiers.
            static let escapeKeyCode: UInt16 = 53
            /// The ID of the recording in progress, or `nil` when no chord should be captured.
            var id: UUID?
            /// Called with the recording ID and the captured key chord.
            var receive: ((UUID, KeyChord) -> Void)?
            /// Called when the recording is cancelled by Escape or the window losing key status.
            var cancel: (() -> Void)?
            /// The navigator told which windows are capturing keys, and asked whether an event came from a
            /// controller.
            weak var navigator: AppKitMenuNavigator?
            private var monitor: Any?
            private weak var registeredWindow: PlatformWindow?

            /// Returns `nil` so the view never intercepts mouse clicks.
            override func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }

            /// Installs the key monitor when a recording is active and the view is in a window, and removes
            /// it otherwise.
            func updateMonitor() {
                if id != nil, window != nil {
                    installMonitor()
                } else {
                    removeMonitor()
                }
            }

            /// Removes the key monitor and unregisters the window from the navigator's key capture windows.
            func removeMonitor() {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
                if let registeredWindow {
                    navigator?.keyCaptureWindows.remove(ObjectIdentifier(registeredWindow))
                }
                registeredWindow = nil
            }

            private func installMonitor() {
                guard monitor == nil else {
                    return
                }
                if let window {
                    registeredWindow = window
                    navigator?.keyCaptureWindows.insert(ObjectIdentifier(window))
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let consumed = MainActor.assumeIsolated {
                        self?.handle(event) == true
                    }
                    return consumed
                        ? nil
                        : event
                }
            }

            /// Refreshes the key monitor and observes the new window losing key status.
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                updateMonitor()
                NotificationCenter.default.removeObserver(
                    self,
                    name: PlatformWindow.didResignKeyNotification,
                    object: nil
                )
                if let window {
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(windowLostFocus),
                        name: PlatformWindow.didResignKeyNotification, object: window
                    )
                }
            }

            @objc private func windowLostFocus(_ notification: Notification) {
                if id != nil {
                    cancel?()
                }
            }

            private func handle(_ event: NSEvent) -> Bool {
                guard let id, let window, event.window === window, !event.isARepeat,
                      window.attachedSheet == nil,
                      navigator?.isControllerEvent(event) != true else {
                    return false
                }
                let modifiers = ShortcutModifiers(event.modifierFlags)
                if event.keyCode == Self.escapeKeyCode, modifiers.isEmpty {
                    cancel?()
                    return true
                }
                guard !modifiers.isDisjoint(with: .anchors) else {
                    return true
                }
                let label = KeyCodeLabels.label(
                    for: Int(event.keyCode),
                    characters: event.charactersIgnoringModifiers
                )
                receive?(id, KeyChord(keyCode: Int(event.keyCode), modifiers: modifiers, label: label))
                return true
            }
        }
    }
#else
    /// A placeholder that does nothing on platforms without a hardware keyboard shortcut recorder.
    struct ShortcutRecorder: View {
        /// The recording in progress, ignored on this platform.
        let id: UUID?
        /// Called with a recorded chord, never invoked on this platform.
        let receive: (UUID, KeyChord) -> Void
        /// Cancels the recording, never invoked on this platform.
        let cancel: () -> Void

        var body: some View {
            EmptyView()
        }
    }
#endif
