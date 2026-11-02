import ChiakiDiagnostics
import PlatformUI
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ComposableArchitecture
import ChiakiTestSupport
import MenuFocus

@MainActor @Test(.requiresWindowServer, arguments: [ColorScheme.light, .dark])
func liveLogPanelRendersAtSmallWindowSize(scheme: ColorScheme) throws {
    var state = LiveLogReducer.State()
    state.phase = .paused
    state.snapshot = .init(entries: [
        .init(id: 1, line: "22:52:07 [INFO] Playback route: Remote console, new core"),
        .init(id: 2, line: "22:52:08 [ERROR] Control route: waiting for console ACCEPT timed out")
    ])
    let store = Store(initialState: state) { LiveLogReducer() }
    let view = LiveLogPanel(store: store, failure: "Remote console: Control route hole punching failed.")
        .frame(width: 420, height: 300)
        .environment(\.colorScheme, scheme)
    _ = NSApplication.shared
    let hosted = MenuFocusHostingView(rootView: view)
    hosted.frame = CGRect(x: 0, y: 0, width: 420, height: 300)
    hosted.appearance = NSAppearance(named: scheme == .dark
        ? .darkAqua
        : .aqua)
    hosted.layoutSubtreeIfNeeded()
    let representation = try #require(hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds))
    hosted.cacheDisplay(in: hosted.bounds, to: representation)
    #expect(representation.pixelsWide > 0 && representation.pixelsHigh > 0)
    let png = try #require(representation.representation(using: .png, properties: [:]))
    let name = scheme == .dark
        ? "dark"
        : "light"
    try png.write(to: URL(fileURLWithPath: "/tmp/chiaki-live-log-\(name).png"))
}
