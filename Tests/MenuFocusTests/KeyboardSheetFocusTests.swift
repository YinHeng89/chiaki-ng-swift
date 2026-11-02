import AppKit
import ChiakiTestSupport
import MenuFocus
import PlatformUI
import SwiftUI
import Testing

@MainActor @Suite(.serialized, .requiresWindowServer)
struct KeyboardSheetFocusTests {
    @Test func keyboardSheetIsReleasedWhenItsParentEndsIt() async {
        let harness = MenuFocusHarness(width: 700, height: 500) { _ in
            NSView()
        }
        defer {
            harness.close()
        }
        await harness.open()
        weak var sheet: PlatformWindow?
        var dismissals = 0
        autoreleasepool {
            ControllerKeyboardSheet.present(
                in: harness.window,
                navigator: harness.navigator,
                glyphs: nil,
                request: ControllerKeyboardSheet.Request(title: "Password", text: "secret", secure: true),
                update: { _ in
                },
                dismissed: { _ in
                    dismissals += 1
                }
            )
            sheet = harness.window.attachedSheet
        }
        await harness.pause(300)
        #expect(sheet != nil)
        autoreleasepool {
            if let attached = harness.window.attachedSheet {
                harness.window.endSheet(attached)
            }
        }
        await harness.pause(500)
        #expect(sheet == nil)
        #expect(dismissals == 0)
    }
}
