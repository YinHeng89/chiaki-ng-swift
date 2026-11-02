import ChiakiModels
import PlatformUI
import SwiftUI
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

@MainActor @Test(.requiresWindowServer) func cloudLibraryRendersPopulatedViewport() async throws {
    guard let path = ProcessInfo.processInfo.environment["CHIAKI_CLOUD_RENDER_FIXTURE"],
          let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    let snapshot = try CloudLibrarySnapshot.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    for width in [760, 1620] {
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        state.selection = snapshot.games.first?.id
        let store = Store(initialState: state) { CloudLibraryFeature() }
        let root = CloudLibraryView(store: store, height: 820)
            .padding(28)
            .background(Color(red: 0.055, green: 0.085, blue: 0.12))
            .environment(\.colorScheme, .dark)
        _ = NSApplication.shared
        let view = MenuFocusHostingView(rootView: root)
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 876),
                                    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: .darkAqua)
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(3))
        view.layoutSubtreeIfNeeded()
        try await WindowCapture.of(window, view: view).png()
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("cloud-\(width).png"))
        window.close()
    }
}
