@testable import ChiakiFeatures
import ChiakiModels
import PlatformUI
import SwiftUI
import Synchronization
import Testing
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func windowAccessorOverlayLetsClicksReachControlsBeneath() async {
        let count = Mutex(0)
        let harness = MenuFocusHarness(width: 200, height: 200) { _ in
            MenuFocusHostingView(rootView: Color.gray
                .overlay {
                    FocusButton {
                        count.withLock { $0 += 1 }
                    } label: {
                        Text("Back").frame(width: 120, height: 120)
                    }
                }
                .overlay {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(WindowAccessor { _ in })
                })
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: CGPoint(x: 100, y: 100), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: harness.window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) {
                harness.window.sendEvent(event)
            }
        }
        await harness.pause(200)
        #expect(count.withLock { $0 } == 1)
    }

    @Test func plainButtonsAcceptClicksAcrossTheirWholeLabel() async {
        let count = Mutex(0)
        let harness = MenuFocusHarness(width: 300, height: 100) { _ in
            MenuFocusHostingView(rootView: FocusButton {
                count.withLock { $0 += 1 }
            } label: {
                Text("Cloud").frame(width: 124).padding(.vertical, 10)
                    .background(Color.clear, in: .capsule)
            }
            .buttonStyle(.plain)
            .frame(width: 300, height: 100))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        click(CGPoint(x: 96, y: 50), in: harness.window)
        await harness.pause(200)
        #expect(count.withLock { $0 } == 1)
    }

    @Test func segmentsAcceptClicksOnTheirPadding() async {
        let segment = Mutex(0)
        let harness = MenuFocusHarness(width: 300, height: 100) { _ in
            MenuFocusHostingView(rootView: SegmentProbe { value in
                segment.withLock { $0 = value }
            }
            .frame(width: 300, height: 100))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        let second = segmentFrame(1, in: harness.host)
        #expect(second != nil)
        if let second {
            click(CGPoint(x: second.minX + 5, y: second.midY), in: harness.window)
            await harness.pause(300)
        }
        #expect(segment.withLock { $0 } == 1)
    }

    @Test func detectIsUnavailableWithoutAController() async {
        let detected = Mutex(0)
        let harness = MenuFocusHarness(width: 500, height: 100) { _ in
            MenuFocusHostingView(rootView: BindingRow(
                target: .cross, bindings: InputPreset.standard.bindings, listening: false,
                capture: { detected.withLock { $0 += 1 } }, change: { _, _, _ in },
                source: .gamepadButton, canDetect: false
            )
            .frame(width: 500, height: 100))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        click(CGPoint(x: 460, y: 50), in: harness.window)
        await harness.pause(200)
        #expect(detected.withLock { $0 } == 0)
    }
}

private struct SegmentProbe: View {
    let changed: (Int) -> Void
    @State private var selection = 0

    var body: some View {
        FocusableSegments(options: [0, 1], title: {
            $0 == 0
                ? "Keyboard"
                : "Mouse"
        }, selection: $selection)
            .onChange(of: selection) { _, value in
                changed(value)
            }
    }
}

@MainActor
private func segmentFrame(_ index: Int, in host: NSView) -> CGRect? {
    var frames = [CGRect]()
    func collect(_ view: NSView) {
        for sub in view.subviews {
            if String(describing: type(of: sub)).contains("KeyViewProxy") {
                frames.append(sub.convert(sub.bounds, to: nil))
            }
            collect(sub)
        }
    }
    collect(host)
    let segments = Set(frames.map { NSStringFromRect($0) }).map(NSRectFromString).sorted { $0.minX < $1.minX }
    return segments.indices.contains(index)
        ? segments[index]
        : nil
}

@MainActor
func click(_ point: CGPoint, in window: PlatformWindow) {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        if let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) {
            window.sendEvent(event)
        }
    }
}
