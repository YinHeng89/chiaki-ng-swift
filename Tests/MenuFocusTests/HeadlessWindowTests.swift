#if os(macOS)
    import AppKit
    import ChiakiTestSupport
    import Testing

    @MainActor
    struct HeadlessWindowTests {
        @Test func orderedInWindowsStayOffEveryDisplay() {
            let window = HeadlessWindow(
                contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            defer {
                window.close()
            }
            window.makeKeyAndOrderFront(nil)
            window.setFrame(CGRect(x: 0, y: 0, width: 900, height: 700), display: true)
            window.center()
            #expect(window.isVisible)
            #expect(window.frame.size == CGSize(width: 900, height: 700))
            for screen in NSScreen.screens {
                #expect(
                    !screen.frame.intersects(window.frame),
                    "window \(window.frame) on screen \(screen.frame)"
                )
            }
        }

        @Test func harnessWindowsStayOffEveryDisplayAndNeverActivate() async {
            let harness = MenuFocusHarness(width: 600, height: 400) { _ in
                NSView()
            }
            defer {
                harness.close()
            }
            await harness.open()
            #expect(harness.window.isVisible)
            #expect(!NSApplication.shared.isActive)
            for screen in NSScreen.screens {
                #expect(!screen.frame.intersects(harness.window.frame))
            }
        }
    }
#endif
