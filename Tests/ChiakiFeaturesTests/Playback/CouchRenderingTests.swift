import ChiakiModels
import PlatformUI
import SwiftUI
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

private let couchHost = AccountProfile(
    id: UUID(), name: "Player", method: .npsso,
    accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(1))
)
private let couchMika = AccountProfile(
    id: UUID(), name: "Mika", method: .npsso, accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(2))
)
private let couchRin = AccountProfile(
    id: UUID(), name: "Rin", method: .npsso, accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(3))
)
private let couchSora = AccountProfile(
    id: UUID(), name: "Sora", method: .npsso, accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(4))
)

private func couchDevice(_ id: UInt32, _ name: String,
                         family: ControllerFamily = .playStation) -> ControllerDevice {
    ControllerDevice(
        id: id, preferenceKey: "unit:\(id)", name: name, transport: "Bluetooth", individual: true,
        rumble: true, lights: true, motion: true, touchpad: family == .playStation, family: family
    )
}

private func couchFixture(choosing: Bool) -> CouchReducer.State {
    var state = CouchReducer.State()
    state.begin(.ps5, hostAccount: couchHost.id)
    state.accounts = [couchHost, couchMika, couchRin, couchSora]
    _ = state.seats.claim(couchDevice(2, "Xbox Wireless Controller", family: .xbox))
    _ = state.seats.chooseAccount(couchMika, for: 1)
    _ = state.seats.apply(.confirmed(pad: 1, color: 0xff5f57))
    _ = state.seats.claim(couchDevice(4, "DualShock 4"))
    _ = state.seats.chooseAccount(couchSora, for: 2)
    _ = state.seats.apply(.accountUnresolvable(pad: 2))
    _ = state.seats.claim(couchDevice(3, "DualShock 4"))
    if !choosing {
        _ = state.seats.chooseAccount(couchRin, for: 2)
    }
    return state
}

private func backdrop() -> some View {
    LinearGradient(colors: [.blue.opacity(0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
}

@MainActor @Test(.requiresWindowServer) func couchScreensRender() async throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    let panelStore = Store(initialState: couchFixture(choosing: false)) { CouchReducer() }
    try await renderCouch(
        playersPanel(panelStore),
        directory: directory, name: "couch-players"
    )
    let swapStore = Store(initialState: swapFixture()) { CouchReducer() }
    try await renderCouch(
        playersPanel(swapStore),
        directory: directory, name: "couch-players-swap"
    )
    let pickerStore = Store(initialState: couchFixture(choosing: true)) { CouchReducer() }
    try await renderCouch(
        ZStack {
            backdrop()
            CouchAccountPickerOverlay(store: pickerStore)
        },
        directory: directory, name: "couch-account-picker"
    )
    var promptState = couchFixture(choosing: false)
    promptState.overlay = .newController(CouchNewControllerPrompt.State(device: couchDevice(
        6,
        "DualSense Wireless Controller"
    )))
    let promptStore = Store(initialState: promptState) { CouchReducer() }
    try await renderCouch(
        ZStack {
            backdrop()
            CouchNewControllerOverlay(store: promptStore)
        },
        directory: directory, name: "couch-new-controller"
    )
    let noticeStore = Store(initialState: noticeFixture()) { CouchReducer() }
    try await renderCouch(
        ZStack {
            backdrop()
            CouchNoticesOverlay(store: noticeStore)
        },
        directory: directory, name: "couch-notices"
    )
}

@MainActor @Test(.requiresWindowServer) func couchControlsRender() async throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    var controlsState = couchFixture(choosing: false)
    let controls = ControlsSettingsFeature.State.loaded()
    controlsState.overlay = .controls(CouchControlsFeature.State(pad: 1, settings: controls))
    let controlsStore = Store(initialState: controlsState) { CouchReducer() }
    try await renderCouch(
        ZStack {
            backdrop()
            CouchControlsOverlay(store: controlsStore)
        },
        directory: directory, name: "couch-controls"
    )
    var keyboardState = couchFixture(choosing: false)
    keyboardState.inventory = CouchInventory(
        controllers: [couchDevice(7, "DualSense Wireless Controller")],
        playerOne: couchDevice(7, "DualSense Wireless Controller")
    )
    keyboardState.overlay = .controls(CouchControlsFeature.State(pad: 0, keyboard: true, settings: controls))
    let keyboardStore = Store(initialState: keyboardState) { CouchReducer() }
    try await renderCouch(
        ZStack {
            backdrop()
            CouchControlsOverlay(store: keyboardStore)
        },
        directory: directory, name: "couch-controls-keyboard"
    )
}

@MainActor private func playersPanel(_ store: StoreOf<CouchReducer>) -> some View {
    ZStack {
        backdrop()
        StreamMenuPanelContent(
            panel: .players,
            configuration: .constant(StreamTuningConfiguration()),
            statistics: RenderStatistics(),
            diagnosticsLevel: .constant(.off),
            diagnosticsGlass: .constant(.regular),
            diagnosticsLayout: .constant(.sheet),
            videoAnalysis: .constant(.off),
            troubleshootTopic: .constant(.wifi),
            frameGenerationEligible: false,
            stopTitle: "Disconnect",
            stop: {},
            couch: store
        )
        .frame(maxWidth: 700)
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(28)
    }
}

private func swapFixture() -> CouchReducer.State {
    var state = couchFixture(choosing: false)
    _ = state.seats.apply(.confirmed(pad: 2, color: 0x3bc77a))
    _ = state.seats.claim(.keyboard)
    state.picking = 1
    state.inventory = CouchInventory(
        controllers: [
            couchDevice(2, "Xbox Wireless Controller", family: .xbox),
            couchDevice(3, "DualShock 4"),
            couchDevice(7, "DualSense Wireless Controller"),
            couchDevice(8, "DualSense Edge Wireless Controller")
        ],
        playerOne: couchDevice(7, "DualSense Wireless Controller")
    )
    return state
}

private func noticeFixture() -> CouchReducer.State {
    var state = couchFixture(choosing: false)
    state.notices = [
        CouchNoticeItem(id: UUID(), notice: .joined(
            pad: 1, player: CouchPlayer(device: couchDevice(2, "Xbox Wireless Controller", family: .xbox),
                                        account: couchMika), color: 0xff5f57
        )),
        CouchNoticeItem(id: UUID(), notice: .joinFailed(pad: 3, failure: .timedOut)),
        CouchNoticeItem(id: UUID(), notice: .released(pad: 2))
    ]
    return state
}

@MainActor private func renderCouch(_ root: some View, directory: String, name: String) async throws {
    _ = NSApplication.shared
    let view = MenuFocusHostingView(rootView: root.environment(\.colorScheme, .dark))
    let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 1320, height: 860),
                                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.appearance = NSAppearance(named: .darkAqua)
    window.orderFrontRegardless()
    view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(300))
    try await WindowCapture.of(window, view: view).png()
        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    window.close()
}
