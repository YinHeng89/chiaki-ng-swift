import ChiakiClients
import ChiakiModels
import PlatformUI
import SwiftUI
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

@MainActor @Test(.requiresWindowServer) func controlsSettingsRendersAtCompactAndRegularSizes() async throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    for width in [760, 1320] {
        for dark in [false, true] {
            var state = SettingsFeature.State()
            state.route = .controls
            state.controls = .loaded()
            let store = Store(initialState: state) { SettingsFeature() } withDependencies: {
                $0.controllers = .testValue
                $0.uuid = .incrementing
            }
            try await renderSettings(SettingsView(store: store, window: nil), width: width, dark: dark,
                                     directory: directory, prefix: "controls")
        }
    }
}

private struct ControlsRenderCase {
    let width: Int
    let editing: ControlsEditTarget
    let listening: PlayStationControl?
    let prefix: String
}

@MainActor private func renderControls(_ item: ControlsRenderCase,
                                       devices: [ControllerDevice]) -> ControlsSettingsFeature.State {
    var controls = ControlsSettingsFeature.State.loaded()
    controls.devices = [devices[0]]
    for (index, device) in devices.enumerated() {
        controls.draft.remembered[device.preferenceKey] = RememberedController(
            device, seen: Date(timeIntervalSinceNow: -86_400 * Double(index * 2))
        )
    }
    controls.editing = item.editing
    if let target = item.listening {
        controls.mode = .capturing(ControlsCapture(
            id: UUID(), target: target, presetID: InputPreset.defaultID, source: .gamepadButton, family: .xbox
        ))
    }
    return controls
}

@MainActor @Test(.requiresWindowServer) func bindingBoardsRenderForEveryKindOfTarget() async throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    let dualSense = ControllerDevice(id: 1, preferenceKey: "dualsense", name: "DualSense Wireless Controller",
                                     transport: "USB", individual: true, rumble: true, lights: true,
                                     motion: true,
                                     touchpad: true, waveform: true, adaptiveTriggers: true)
    let xbox = ControllerDevice(id: 2, preferenceKey: "xbox", name: "Xbox Wireless Controller",
                                transport: "Bluetooth", individual: true, rumble: true, lights: false,
                                motion: false, touchpad: false, family: .xbox)
    let pro = ControllerDevice(id: 3, preferenceKey: "pro", name: "Pro Controller", transport: "Bluetooth",
                               individual: false, rumble: true, lights: false, motion: true, touchpad: false,
                               family: .nintendo)
    let cases = [
        ControlsRenderCase(width: 1320, editing: .keyboard, listening: nil, prefix: "board-keyboard"),
        ControlsRenderCase(
            width: 1320,
            editing: .controller("dualsense"),
            listening: nil,
            prefix: "board-dualsense"
        ),
        ControlsRenderCase(
            width: 1320,
            editing: .controller("xbox"),
            listening: .touchpad,
            prefix: "board-xbox"
        ),
        ControlsRenderCase(width: 1320, editing: .controller("pro"), listening: nil, prefix: "board-pro"),
        ControlsRenderCase(width: 1320, editing: .player(1), listening: nil, prefix: "board-player"),
        ControlsRenderCase(
            width: 760,
            editing: .controller("dualsense"),
            listening: nil,
            prefix: "board-compact"
        )
    ]
    for item in cases {
        for dark in [false, true] {
            var state = SettingsFeature.State()
            state.route = .controls
            state.controls = renderControls(item, devices: [dualSense, xbox, pro])
            let store = Store(initialState: state) { SettingsFeature() } withDependencies: {
                $0.controllers = ControllersClient(
                    devices: { [dualSense] },
                    testRumble: { _, _ in },
                    showLights: { _ in }
                )
                $0.uuid = .incrementing
                $0.date = .constant(Date())
            }
            let root = ScrollView {
                ControlsSettingsView(store: store.scope(state: \.controls, action: \.controls)).padding(28)
            }
            .background(dark
                ? Color(red: 0.07, green: 0.14, blue: 0.2)
                : Color(red: 0.93, green: 0.95, blue: 0.97))
            try await renderSettings(root, width: item.width, height: 1900, dark: dark, directory: directory,
                                     prefix: item.prefix)
        }
    }
}

@MainActor @Test(.requiresWindowServer) func streamMenuPanelsRenderAtCompactAndRegularSizes() async throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    let configuration = streamTuningFixture()
    let statistics = streamStatisticsFixture()
    for width in [760, 1320] {
        for panel in StreamMenuPanel.allCases {
            let root = ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.55), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                StreamMenuPanelContent(
                    panel: panel,
                    configuration: .constant(configuration),
                    statistics: RenderStatistics(fixture: statistics),
                    diagnosticsLevel: .constant(.full),
                    diagnosticsGlass: .constant(.regular),
                    diagnosticsLayout: .constant(.sheet),
                    videoAnalysis: .constant(.hdrHeatmap),
                    troubleshootTopic: .constant(.wifi),
                    frameGenerationEligible: true,
                    stopTitle: "Disconnect",
                    stop: {}
                )
                .frame(maxWidth: 700)
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(28)
            }
            try await renderSettings(
                root,
                width: width,
                dark: true,
                directory: directory,
                prefix: "stream-\(panel.rawValue.lowercased())"
            )
        }
    }
}

@MainActor @Test(.requiresWindowServer) func diagnosticsOverlayRendersCompactFullAndHDR() async throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    var raw = streamStatisticsFixture()
    raw["audioReceivedChannels"] = 12
    raw["audioReceivedSampleRate"] = 48000
    raw["audioChannels"] = 8
    raw["audioSampleRate"] = 48000
    let telemetry = StreamTelemetry(
        statistics: RenderStatistics(fixture: raw),
        sourceFPS: 59.9,
        presentedFPS: 119.7,
        generatedFPS: 59.8,
        bitrateMbps: 34.7,
        lossPercent: 0.08
    )
    for level in [StreamDiagnosticsAppearance.Level.compact, .standard, .full] {
        let root = ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.8), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            StreamDiagnosticsOverlay(
                report: StreamDiagnosticsReport(telemetry: telemetry),
                appearance: StreamDiagnosticsAppearance(level: level),
                analysisMode: .hdrHeatmap
            )
        }
        try await renderSettings(
            root,
            width: 1320,
            dark: true,
            directory: directory,
            prefix: "diagnostics-\(level.rawValue)"
        )
    }
}

@MainActor @Test(.requiresWindowServer) func streamLoadingViewUsesTheAppAmbientBackground() async throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    let root = StreamLoadingView(
        status: "Negotiating video",
        activeStep: 2,
        stepCount: 4,
        cancel: {}
    )
    try await renderSettings(
        root,
        width: 1320,
        dark: true,
        directory: directory,
        prefix: "stream-loading"
    )
}

private func streamTuningFixture() -> StreamTuningConfiguration {
    StreamTuningConfiguration(
        presentationFrameRate: .generated120,
        upscaledOutput: .fourK,
        upscaler: .advancedSpatial,
        nativeHeight: 1080,
        frameGenerationAvailable: true
    )
}

private func streamStatisticsFixture() -> [String: NSNumber] {
    [
        "surfaces": 2_400,
        "completed": 2_398,
        "frameGenerationGenerated": 1_199,
        "generatedDrops": 1,
        "deadlineMisses": 2,
        "lost": 0,
        "received": 2_400,
        "bytes": 173_500_000,
        "recovered": 3,
        "decoderFailures": 0,
        "requestedHeight": 1080,
        "requestedFPS": 60,
        "requestedBitrate": 35_000,
        "requestedHEVC": true,
        "streamSeconds": 142,
        "sourceWidth": 1_920,
        "sourceHeight": 1_080,
        "outputWidth": 3_840,
        "outputHeight": 2_160,
        "presentationFrameRate": 120,
        "displayMaximumFPS": 120,
        "displayMaximumEDR": 1.6,
        "gpuMilliseconds": 4.2,
        "tenBit": true,
        "pq": true,
        "bt2020": true,
        "layerHDR": true,
        "advancedSpatial": true,
        "gpuError": 0
    ]
}

@MainActor private func renderSettings(_ root: some View, width: Int, height: Int = 900, dark: Bool,
                                       directory: String, prefix: String) async throws {
    _ = NSApplication.shared
    let view = MenuFocusHostingView(rootView: root.environment(\.colorScheme, dark
            ? .dark
            : .light))
    let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.appearance = NSAppearance(named: dark
        ? .darkAqua
        : .aqua)
    window.orderFrontRegardless()
    view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    let data = try await WindowCapture.of(window, view: view).png()
    let suffix = dark
        ? "dark"
        : "light"
    try data.write(to: URL(fileURLWithPath: directory)
        .appendingPathComponent("\(prefix)-\(width)-\(suffix).png"))
    window.close()
}
