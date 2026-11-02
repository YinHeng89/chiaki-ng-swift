@testable import ChiakiFeatures
import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func streamMenuShortcutPickersSitAboveTheLightBarAsOneRow() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = MenuFocusHarness(width: 1300, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 1180, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(200)
        var previous = window.firstResponder
        for _ in 0..<160 {
            await harness.send(.down)
            if window.firstResponder === previous {
                break
            }
            previous = window.firstResponder
        }
        await harness.send(.up)
        let lightBar = harness.focusedFrame
        await harness.send(.up)
        let row = harness.focusedFrame
        #expect(row.minY > lightBar.maxY)
        await harness.send([.left, .left, .left, .left])
        await harness.pause(400)
        var stops = [harness.focusedFrame.integral]
        for _ in 0..<3 {
            await harness.send(.right)
            await harness.pause(400)
            stops.append(harness.focusedFrame.integral)
        }
        #expect(Set(stops.map(\.minX)).count == 4)
        #expect(Set(stops.map(\.midY)).count == 1)
        let picker = harness.focusedView
        await harness.send(.down)
        await harness.pause(400)
        let pickerFrame = picker.map { $0.convert($0.bounds, to: nil) } ?? .zero
        #expect(harness.focusedFrame.maxY < pickerFrame.minY)
    }
}
