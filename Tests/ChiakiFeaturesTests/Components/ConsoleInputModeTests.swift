import ChiakiModels
import PlatformUI
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

@MainActor
private final class ConsoleCardFocusProbe {
    var focus: ConsoleLibraryFocus?
}

private struct ConsoleCardHost: View {
    let item: DisplayedConsole
    let probe: ConsoleCardFocusProbe
    @MenuFocusState private var focus: ConsoleLibraryFocus?

    var body: some View {
        ConsoleCard(
            item: item,
            console: item.target,
            accountName: "Test account",
            busy: false,
            startLocal: {},
            startRemote: {},
            edit: {},
            delete: {},
            focus: $focus,
            moveConsole: { _ in }
        )
        .onAppear {
            focus = .console(item)
        }
        .onChange(of: focus) { _, value in
            probe.focus = value
        }
    }
}

@MainActor @Suite(.serialized)
struct ConsoleInputModeTests {
    @Test(.requiresWindowServer) func pointerModeKeepsTheConsoleCardActionBarHidden() async throws {
        let console = FeatureFocusStores.console(1)
        let item = DisplayedConsole(target: console, preview: false)
        let pointer = try await consoleCardSnapshots(console, mode: .pointer)
        #expect(pointer.focus == .console(item))
        #expect(pointer.focused == pointer.unfocused)
        let controller = try await consoleCardSnapshots(console, mode: .controller)
        #expect(controller.focus == .console(item))
        #expect(controller.focused != controller.unfocused)
    }

    private struct CardSnapshots {
        let focus: ConsoleLibraryFocus?
        let focused: Data
        let unfocused: Data
    }

    private func consoleCardSnapshots(_ console: RegistrationFlow.ConsoleTarget,
                                      mode: InputMode) async throws -> CardSnapshots {
        let item = DisplayedConsole(target: console, preview: false)
        let probe = ConsoleCardFocusProbe()
        let harness = MenuFocusHarness(width: 520, height: 420) { _ in
            MenuFocusHostingView(rootView: ConsoleCardHost(item: item, probe: probe)
                .environment(\.inputMode, mode))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(700)
        let focus = probe.focus
        let focused = try snapshot(harness.host)
        harness.window.makeFirstResponder(nil)
        await harness.pause(700)
        let unfocused = try snapshot(harness.host)
        return CardSnapshots(focus: focus, focused: focused, unfocused: unfocused)
    }

    private func snapshot(_ view: NSView) throws -> Data {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}

@MainActor @Test func closingSettingsWithThePointerReturnsToTheGame() {
    #expect(SettingsPanelPresentation.returnsToStreamControls(after: .pointer) == false)
    #expect(SettingsPanelPresentation.returnsToStreamControls(after: .controller))
}
