import AppKit
import ChiakiTestSupport
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI
import Testing

@MainActor @Suite
struct TouchControlSizeTests {
    private func focusedHeight(touch: Bool, @ViewBuilder content: () -> some View) async -> CGFloat {
        let layout = ScreenLayout(room: .regular, stature: .tall, touch: touch)
        let harness = MenuFocusHarness(width: 400, height: 200) { _ in
            MenuFocusHostingView(rootView: content().padding().environment(\.screenLayout, layout))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.window.recalculateKeyViewLoop()
        harness.window.selectNextKeyView(nil)
        await harness.settle()
        return harness.focusedFrame.height
    }

    @Test(.requiresWindowServer) func segmentsGrowToAFingerOnTouchAndKeepTheirPointerSize() async {
        let pointer = await focusedHeight(touch: false) {
            FocusableSegments(options: ["One", "Two"], title: { $0 }, selection: .constant("One"))
        }
        let touch = await focusedHeight(touch: true) {
            FocusableSegments(options: ["One", "Two"], title: { $0 }, selection: .constant("One"))
        }
        #expect(pointer > 0)
        #expect(pointer < ScreenLayout.touchTarget - 8)
        #expect(touch >= ScreenLayout.touchTarget - 8)
    }

    @Test(.requiresWindowServer) func checkboxRowsGrowToAFingerOnTouchAndKeepTheirPointerSize() async {
        let pointer = await focusedHeight(touch: false) {
            Toggle("Keep", isOn: .constant(true)).toggleStyle(AccentCheckboxToggleStyle())
        }
        let touch = await focusedHeight(touch: true) {
            Toggle("Keep", isOn: .constant(true)).toggleStyle(AccentCheckboxToggleStyle())
        }
        #expect(pointer > 0)
        #expect(pointer < ScreenLayout.touchTarget)
        #expect(touch >= ScreenLayout.touchTarget)
    }
}
