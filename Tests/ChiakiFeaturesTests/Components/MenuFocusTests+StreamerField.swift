@testable import ChiakiFeatures
import AppKit
import SwiftUI
import Testing
import DesignSystem
import MenuFocus
import ChiakiTestSupport

private struct StreamerFieldHost: View {
    let address: String
    let streamerMode: Bool
    @State private var text: String
    @MenuFocusState private var focused: Bool

    init(address: String, streamerMode: Bool) {
        self.address = address
        self.streamerMode = streamerMode
        _text = State(initialValue: address)
    }

    var body: some View {
        TextField("IP address or hostname", text: $text)
            .textFieldStyle(.plain)
            .streamerHiddenField(text)
            .menuFocusBinding($focused)
            .frame(width: 320)
            .padding(24)
            .environment(\.streamerMode, streamerMode)
            .task {
                for _ in 0..<5 {
                    focused = true
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
    }
}

@MainActor private func focusedTextAlpha(address: String, streamerMode: Bool) async -> CGFloat? {
    let harness = MenuFocusHarness(width: 400, height: 120) { _ in
        MenuFocusHostingView(rootView: StreamerFieldHost(address: address, streamerMode: streamerMode))
    }
    defer {
        harness.close()
    }
    await harness.open()
    await harness.pause(400)
    guard let editor = harness.window.firstResponder as? NSTextView, editor.string == address else {
        return nil
    }
    let storage = editor.textStorage
    let attributed = storage.flatMap { text in
        text.length > 0
            ? text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            : nil
    }
    let color = attributed ?? editor.textColor ?? .textColor
    return color.usingColorSpace(.sRGB)?.alphaComponent
}

extension MenuFocusTests {
    @Test func streamerModeKeepsAFocusedAddressFieldHidden() async throws {
        let hidden = try #require(await focusedTextAlpha(address: "192.168.1.27", streamerMode: true))
        let shown = try #require(await focusedTextAlpha(address: "192.168.1.27", streamerMode: false))
        #expect(hidden == 0, "focused text alpha \(hidden)")
        #expect(shown > 0.5)
    }
}
