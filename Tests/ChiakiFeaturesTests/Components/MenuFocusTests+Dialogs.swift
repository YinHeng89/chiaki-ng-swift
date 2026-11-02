import ChiakiModels
import DesignSystem
import ChiakiClients
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func controllerMovesBetweenAlertButtonsAndActivatesTheFocusedOne() async {
        let harness = MenuFocusHarness(width: 500, height: 400) { _ in
            NSView()
        }
        defer {
            harness.close()
        }
        await harness.open()
        let alert = NSAlert()
        alert.messageText = "Delete this console?"
        alert.addButton(withTitle: "Delete console")
        alert.addButton(withTitle: "Cancel")
        var response: NSApplication.ModalResponse?
        alert.beginSheetModal(for: harness.window) {
            response = $0
        }
        await harness.pause(200)
        guard let sheet = harness.window.attachedSheet else {
            Issue.record("Alert sheet was not presented")
            return
        }
        AppKitAlertFocus.focusPreferredButton(in: sheet)
        #expect((sheet.firstResponder as? NSButton)?.title == "Cancel")
        harness.perform([.up], in: sheet)
        #expect((sheet.firstResponder as? NSButton)?.title == "Delete console")
        harness.perform([.down], in: sheet)
        #expect((sheet.firstResponder as? NSButton)?.title == "Cancel")
        harness.perform([.confirm], in: sheet)
        await harness.pause(200)
        #expect(response == .alertSecondButtonReturn)
    }

    private func consoleEditorHarness(
        _ draft: ConsoleDraft,
        toggled: LockIsolated<[Bool]>,
        forgotten: LockIsolated<Int>,
        width: CGFloat = 700,
        layout: ScreenLayout = ScreenLayout()
    ) -> MenuFocusHarness {
        MenuFocusHarness(width: width, height: 800) { _ in
            MenuFocusHostingView(rootView: ConsoleEditor(
                draft: draft,
                nameChanged: { _ in },
                addressChanged: { _ in },
                connectAtLaunchChanged: { value in
                    toggled.withValue {
                        $0.append(value)
                    }
                },
                forgetLoginPIN: {
                    forgotten.withValue {
                        $0 += 1
                    }
                },
                cancel: {},
                save: {},
                delete: {}
            )
            .environment(\.screenLayout, layout))
        }
    }

    @Test func consoleEditorStacksItsRowsOnANarrowTouchScreenAndKeepsTheWalk() async {
        let draft = ConsoleDraft(
            id: UUID(),
            name: "Living room",
            address: "192.168.1.50",
            generation: "PS5",
            remoteAvailable: false,
            hardwareID: nil,
            loginPIN: .saved
        )
        let forgotten = LockIsolated(0)
        let harness = consoleEditorHarness(
            draft,
            toggled: LockIsolated([]),
            forgotten: forgotten,
            width: 360,
            layout: ScreenLayout(room: .compact, stature: .tall, touch: true, sideInset: 0)
        )
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        #expect(harness.window.firstResponder is NSTextView)
        let nameFrame = harness.focusedFrame
        #expect(nameFrame.minX < 100, "\(nameFrame)")
        await harness.send(.down)
        #expect(harness.window.firstResponder is NSTextView)
        let addressFrame = harness.focusedFrame
        #expect(addressFrame.minY != nameFrame.minY)
        #expect(abs(addressFrame.minX - nameFrame.minX) < 4, "\(nameFrame) \(addressFrame)")
        await harness.send(.down)
        #expect(!(harness.window.firstResponder is NSTextView))
        await harness.send(.down)
        let forgetFrame = harness.focusedFrame
        #expect(forgetFrame.minY != addressFrame.minY)
        #expect(forgetFrame.midX > addressFrame.midX, "\(addressFrame) \(forgetFrame)")
        await harness.send(.down)
        let saveFrame = harness.focusedFrame
        #expect(saveFrame != forgetFrame)
        await harness.send([.up, .up, .up, .up])
        #expect(harness.window.firstResponder is NSTextView)
        #expect(harness.focusedFrame == nameFrame)
        await harness.send(.up)
        let closeFrame = harness.focusedFrame
        #expect(closeFrame.midX > nameFrame.midX)
    }

    @Test func consoleEditorStartsOnNameAndReachesEveryAction() async {
        let draft = ConsoleDraft(
            id: UUID(),
            name: "Living room",
            address: "192.168.1.50",
            generation: "PS5",
            remoteAvailable: false,
            hardwareID: nil
        )
        let toggled = LockIsolated<[Bool]>([])
        let harness = consoleEditorHarness(draft, toggled: toggled, forgotten: LockIsolated(0))
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        #expect(harness.window.firstResponder is NSTextView)
        let nameFrame = harness.focusedFrame
        await harness.send(.up)
        let closeFrame = harness.focusedFrame
        #expect(closeFrame.width < 60)
        #expect(closeFrame.midX > nameFrame.midX)
        await harness.send([.down, .down, .down])
        let toggleFrame = harness.focusedFrame
        #expect(!(harness.window.firstResponder is NSTextView))
        #expect(toggleFrame.minY != nameFrame.minY)
        await harness.send(.confirm)
        #expect(toggled.value == [true])
        await harness.send(.down)
        let saveFrame = harness.focusedFrame
        #expect(saveFrame != toggleFrame)
        #expect(saveFrame.width > closeFrame.width)
        await harness.send([.left, .left])
        #expect(harness.focusedFrame.midX < saveFrame.midX)
        await harness.send(.up)
        #expect(harness.focusedFrame == toggleFrame)
        await harness.send(.up)
        #expect(harness.window.firstResponder is NSTextView)
    }

    @Test func consoleEditorReachesForgetPINBetweenTheToggleAndActions() async {
        let draft = ConsoleDraft(
            id: UUID(),
            name: "Living room",
            address: "192.168.1.50",
            generation: "PS5",
            remoteAvailable: false,
            hardwareID: nil,
            loginPIN: .saved
        )
        let forgotten = LockIsolated(0)
        let harness = consoleEditorHarness(draft, toggled: LockIsolated([]), forgotten: forgotten)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        await harness.send([.down, .down])
        let toggleFrame = harness.focusedFrame
        await harness.send(.down)
        let forgetFrame = harness.focusedFrame
        #expect(forgetFrame.midX > toggleFrame.midX)
        await harness.send(.down)
        let saveFrame = harness.focusedFrame
        #expect(saveFrame != forgetFrame)
        await harness.send(.up)
        #expect(harness.focusedFrame == forgetFrame)
        await harness.send(.confirm)
        #expect(forgotten.value == 1)
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock {
            value
        }
    }

    func increment() {
        lock.withLock {
            value += 1
        }
    }
}

extension MenuFocusTests {
    @Test func playStationRetryKeepsControllerFocusOnThePage() async {
        let loads = LoadCounter()
        await withDependencies {
            $0.uuid = .incrementing
            $0.settings = .inMemory([DiscoverySettings()])
            $0.consoles.scanEvents = {
                AsyncStream { _ in
                }
            }
            $0.consoles.accountConsoles = { _, _ in
                loads.increment()
                try await Task.sleep(for: .milliseconds(150))
                throw URLError(.notConnectedToInternet)
            }
        } operation: {
            await expectPlayStationRetryKeepsFocus(loads: loads)
        }
    }

    private func expectPlayStationRetryKeepsFocus(loads: LoadCounter) async {
        let store = Store(initialState: AddConsoleFeature.State(
            account: UUID(),
            modes: [.automatic, .manual, .playStation],
            preferred: .playStation
        )) {
            AddConsoleFeature()
        }
        let harness = MenuFocusHarness(width: 700, height: 700) { _ in
            MenuFocusHostingView(rootView: AddConsoleView(
                store: store,
                discovery: DiscoveryFeature.State(),
                failure: nil
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(1200)
        #expect(loads.count == 1)
        await harness.send([.down, .down, .confirm])
        await harness.pause(400)
        #expect(loads.count == 2)
        await harness.send([.down, .confirm])
        await harness.pause(400)
        #expect(loads.count == 3)
    }
}

@MainActor
private final class KeyboardTextProbe {
    var text = ""
    var dismissed: Bool?
}

private struct NumberPadHost: View {
    let probe: KeyboardTextProbe
    let source: PlatformWindow

    var body: some View {
        ControllerOnScreenKeyboard(
            title: "PIN",
            text: Binding(
                get: {
                    probe.text
                },
                set: {
                    probe.text = $0
                }
            ),
            secure: true,
            numberPad: true,
            allowsNewline: false,
            sourceWindow: source,
            dismiss: {
                probe.dismissed = $0
            }
        )
    }
}

extension MenuFocusTests {
    @Test func numberPadNavigatesWithArrowKeysAndPressesTheSelectedKey() async {
        let probe = KeyboardTextProbe()
        let source = HeadlessWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let harness = MenuFocusHarness(width: 560, height: 460) { _ in
            MenuFocusHostingView(rootView: NumberPadHost(probe: probe, source: source))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        if let field = textFields(in: harness.host).first {
            harness.window.makeFirstResponder(field)
        }
        await harness.pause(100)
        #expect(harness.window.firstResponder is NSTextView)
        await pressKey(code: 125, characters: "\u{F701}", in: harness)
        await pressKey(code: 124, characters: "\u{F703}", in: harness)
        await pressKey(code: 36, characters: "\r", in: harness)
        #expect(probe.text == "5")
        #expect(probe.dismissed == nil)
        await pressKey(code: 18, characters: "1", in: harness)
        await pressKey(code: 36, characters: "\r", in: harness)
        #expect(probe.dismissed == true)
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        if let field = view as? NSTextField, field.isEditable {
            return [field]
        }
        return view.subviews.flatMap(textFields(in:))
    }

    private func pressKey(code: UInt16, characters: String, in harness: MenuFocusHarness) async {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: harness.window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: code
            ) {
                harness.window.sendEvent(event)
            }
        }
        await harness.pause(60)
    }
}

extension MenuFocusTests {
    @Test func controllerBackLeavesFindYourConsole() async {
        let backs = LoadCounter()
        await withDependencies {
            $0.uuid = .incrementing
            $0.settings = .inMemory([DiscoverySettings()])
            $0.consoles.scanEvents = {
                AsyncStream { _ in
                }
            }
        } operation: {
            let store = Store(initialState: AddConsoleFeature.State(
                account: UUID(),
                modes: [.automatic, .manual, .playStation]
            )) {
                AddConsoleFeature()
                Reduce { _, action in
                    if case .delegate(.left) = action {
                        backs.increment()
                    }
                    return .none
                }
            }
            let harness = MenuFocusHarness(width: 700, height: 700) { _ in
                MenuFocusHostingView(rootView: AddConsoleView(
                    store: store,
                    discovery: DiscoveryFeature.State(),
                    failure: nil
                ))
            }
            let override = KeyWindowOverride(harness.window)
            defer {
                override.restore()
                harness.close()
            }
            await harness.open()
            await harness.pause(400)
            await harness.send(.back)
            await harness.pause(100)
            #expect(backs.count == 1)
        }
    }
}
