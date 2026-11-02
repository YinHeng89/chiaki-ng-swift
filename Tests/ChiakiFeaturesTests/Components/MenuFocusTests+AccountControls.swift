@testable import ChiakiFeatures
import ChiakiModels
import DesignSystem
import PlatformUI
import SwiftUI
import Testing
import MenuFocus
import ChiakiTestSupport

@MainActor
private final class AccountFocusProbe {
    var focus: ConsoleLibraryFocus?
    var request: ConsoleLibraryFocus?
}

private struct AccountControlsHost: View {
    let probe: AccountFocusProbe
    var profileCount = 1
    var refreshes = false
    var layout = ScreenLayout()
    @MenuFocusState private var focus: ConsoleLibraryFocus?
    @State private var refreshing = false
    private static let profiles = (0..<2).map {
        RegistrationFlow.Profile(id: UUID(), name: "Player \($0)", kind: .npsso, accountID: "\($0)")
    }

    var body: some View {
        let profiles = Array(Self.profiles.prefix(profileCount))
        AccountControls(
            profiles: profiles, selected: profiles.first, cloudText: "Ready", cloudHelp: "",
            cloudColor: .green,
            isRefreshing: refreshing,
            refresh: {
                if refreshes {
                    refreshing = true
                }
            },
            send: { _ in }, delete: { _ in },
            navigationFocus: $focus, moveToConsole: { _ in }, moveToLibraryTab: {}
        )
        .frame(width: 600, height: 200)
        .environment(\.screenLayout, layout)
        .onChange(of: focus) { _, value in
            probe.focus = value
        }
        .task {
            while !Task.isCancelled {
                if let request = probe.request {
                    probe.request = nil
                    focus = request
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}

extension MenuFocusTests {
    @Test func backFromAccountActionsReturnsToTheProfileButton() async {
        let probe = AccountFocusProbe()
        let harness = MenuFocusHarness(width: 700, height: 300) { _ in
            MenuFocusHostingView(rootView: AccountControlsHost(probe: probe))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        probe.request = .profile
        await harness.pause(200)
        #expect(probe.focus == .profile)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(probe.focus == nil)
        await harness.send(.back)
        await harness.pause(400)
        #expect(probe.focus == .profile)
        #expect(testNavigator.hasControlFocus(in: harness.window))
    }

    @Test func titledTouchActionsAreFingerSizedAndBackReturnsToTheProfileButton() async {
        let probe = AccountFocusProbe()
        let harness = MenuFocusHarness(width: 700, height: 300) { _ in
            MenuFocusHostingView(rootView: AccountControlsHost(
                probe: probe,
                profileCount: 2,
                layout: ScreenLayout(room: .regular, stature: .tall, touch: true, sideInset: 0)
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        probe.request = .profile
        await harness.pause(200)
        #expect(probe.focus == .profile)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(probe.focus == nil)
        var frames = [CGRect]()
        for _ in 0..<5 {
            frames.append(harness.focusedFrame)
            await harness.send(.left)
        }
        #expect(Set(frames.map(\.midX)).count == 5, "\(frames)")
        for frame in frames {
            #expect(frame.width >= ScreenLayout.touchTarget - 1, "\(frame)")
            #expect(frame.height >= ScreenLayout.touchTarget - 1, "\(frame)")
        }
        await harness.send(.back)
        await harness.pause(400)
        #expect(probe.focus == .profile)
        #expect(testNavigator.hasControlFocus(in: harness.window))
    }

    @Test func backFromTheAccountChooserReturnsToSwitchAccount() async {
        let probe = AccountFocusProbe()
        let harness = MenuFocusHarness(width: 700, height: 300) { _ in
            MenuFocusHostingView(rootView: AccountControlsHost(probe: probe, profileCount: 2))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        probe.request = .profile
        await harness.pause(200)
        await harness.send(.confirm)
        await harness.pause(300)
        await harness.send([.left, .left, .left, .left])
        await harness.pause(200)
        let switchFrame = harness.focusedFrame
        await harness.send(.confirm)
        await harness.pause(500)
        let popover = NSApp.windows
            .first { $0 !== harness.window && $0.isVisible && $0.parent === harness.window }
            ?? NSApp.windows
            .first {
                $0 !== harness.window && $0.isVisible && NSStringFromClass(type(of: $0)).contains("Popover") }
        guard let popover else {
            Issue.record("Account chooser did not open")
            return
        }
        harness.perform([.back], in: popover)
        await harness.pause(600)
        #expect(!popover.isVisible)
        #expect(testNavigator.hasControlFocus(in: harness.window))
        let after = harness.focusedFrame
        #expect(
            abs(after.midX - switchFrame.midX) < 4 && abs(after.midY - switchFrame.midY) < 4,
            "\(switchFrame) \(after)"
        )
    }
}

extension MenuFocusTests {
    private func refreshingAccountHarness(_ probe: AccountFocusProbe) async -> MenuFocusHarness {
        let harness = MenuFocusHarness(width: 900, height: 300) { _ in
            MenuFocusHostingView(rootView: AccountControlsHost(
                probe: probe,
                profileCount: 0,
                refreshes: true
            ))
        }
        await harness.open()
        await harness.pause(200)
        probe.request = .profile
        await harness.pause(200)
        return harness
    }

    @Test func accountMenuKeepsFocusWhenTheFocusedIconBecomesUnavailable() async {
        let probe = AccountFocusProbe()
        let harness = await refreshingAccountHarness(probe)
        defer {
            harness.close()
        }
        #expect(probe.focus == .profile)
        await harness.send([.confirm, .confirm])
        #expect(probe.focus == nil)
        #expect(harness.window.firstResponder is NSView)
        await harness.send(.back)
        #expect(probe.focus == .profile)
    }

    @Test func accountMenuKeepsDirectionalFocusInsideIconsAndBackRestoresProfile() async {
        let probe = AccountFocusProbe()
        let harness = await refreshingAccountHarness(probe)
        let window = harness.window
        defer {
            harness.close()
        }
        #expect(probe.focus == .profile)
        await harness.send(.confirm)
        #expect(probe.focus == nil)
        let finalIcon = window.firstResponder
        await harness.send(.left)
        #expect(window.firstResponder !== finalIcon)
        await harness.send(.left)
        let firstIcon = window.firstResponder
        await harness.send(.left)
        #expect(window.firstResponder === firstIcon)
        await harness.send(.back)
        #expect(probe.focus == .profile)
        #expect(window.firstResponder !== firstIcon)
        await harness.send(.confirm)
        let lastIcon = window.firstResponder
        await harness.send(.right)
        #expect(probe.focus == nil)
        #expect(window.firstResponder === lastIcon)
        await harness.send(.down)
        #expect(window.firstResponder === lastIcon)
        await harness.send(.back)
        #expect(probe.focus == .profile)
    }
}
