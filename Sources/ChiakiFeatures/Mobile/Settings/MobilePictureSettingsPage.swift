import ChiakiModels
import ComposableArchitecture
import DesignSystem
import PlatformUI
import SwiftUI

/// The touch Picture settings page: console or cloud stream settings, chosen at the top while an account is
/// signed in to PlayStation Network.
struct MobilePictureSettingsPage: View {
    /// The settings feature that owns the picture settings.
    let settings: StoreOf<SettingsFeature>

    @State private var streamKind = PictureSettingsContainerView.StreamKind.console

    /// Creates the page.
    ///
    /// - Parameter settings: The settings feature that owns the picture settings.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    private var shownKind: PictureSettingsContainerView.StreamKind {
        settings.psnReach == .signedIn
            ? streamKind
            : .console
    }

    private var kind: Binding<PictureSettingsContainerView.StreamKind>? {
        settings.psnReach == .signedIn
            ? $streamKind
            : nil
    }

    var body: some View {
        switch shownKind {
        case .console:
            MobileConsolePictureForm(
                store: settings.scope(state: \.picture, action: \.picture),
                streamKind: kind
            )
        case .cloud:
            MobileCloudPictureForm(
                store: settings.scope(state: \.cloudPicture, action: \.cloudPicture),
                streamKind: kind
            )
        }
    }
}

/// The console stream picture settings, for the home network and the internet.
private struct MobileConsolePictureForm: View {
    /// The persisted console picture settings being edited.
    @Bindable var store: StoreOf<PersistedSettingFeature<PictureSettings>>

    /// The console or cloud choice, or `nil` when only console settings are offered.
    let streamKind: Binding<PictureSettingsContainerView.StreamKind>?

    @State private var routeChoice = PictureSettingsView.RouteChoice.home

    var body: some View {
        MobileSettingsForm {
            MobileSettingsGroup(
                "Stream Settings For",
                footer: "Internet covers PlayStation connections and console addresses outside your local "
                    + "network."
            ) {
                if let streamKind {
                    MobileStreamKindRow(selection: streamKind)
                }
                MobilePickerRow("Connection", selection: $routeChoice) {
                    ForEach(PictureSettingsView.RouteChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .disabled(!store.isEditable)
            }
            MobilePictureStreamGroup(
                height: profile(\.height),
                fps: profile(\.fps),
                bitrate: profile(\.bitrateMbps),
                automaticBitrate: profile(\.automaticBitrate),
                automaticBitrateMbps: StreamProfile.automaticBitrateMbps(
                    height: store.draft[routeChoice.route].height
                ),
                resolutions: StreamProfile.heights
            )
            .disabled(!store.isEditable)
            codec
                .disabled(!store.isEditable)
        } trailing: {
            MobilePictureDisplayGroup(
                height: store.draft[routeChoice.route].height,
                fps: store.draft[routeChoice.route].fps,
                output: profile(\.upscaledOutput),
                upscaler: $store.draft.upscaler,
                presentation: $store.draft.presentationFrameRate,
                hdr: store.draft.launchCodec(
                    forPS5: true,
                    route: routeChoice.route,
                    displaySupportsHDR: DisplayDynamicRange.supportsHDR
                ) == .hevcHDR,
                fullScreen: $store.draft.fullScreenStreams
            )
            .disabled(!store.isEditable)
            MobilePictureColourGroup(
                adjustments: $store.draft.adjustments,
                reduceBanding: $store.draft.reduceBanding
            )
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: "picture settings") {
                store.send(.retry)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    private var codec: some View {
        let ps5 = routeChoice == .home
            ? $store.draft.localPS5Codec
            : $store.draft.remotePS5Codec
        let hdr = routeChoice == .home
            ? $store.draft.localPS5HDR
            : $store.draft.remotePS5HDR
        return MobileSettingsGroup(
            "Codec",
            footer: "PS4 streams always use \(PictureSettings.Codec.h264.title)."
        ) {
            MobilePickerRow("PS5", selection: ps5) {
                ForEach(PictureSettings.Codec.choices, id: \.self) { codec in
                    Text(codec.title).tag(codec)
                }
            }
            MobileToggleRow(
                "Use HDR When the Screen Supports It",
                detail: PictureCodecGroup.detail(for: ps5.wrappedValue),
                isOn: hdr
            )
            .disabled(ps5.wrappedValue != .hevc)
        }
    }

    private func profile<Value>(_ key: WritableKeyPath<StreamProfile, Value>) -> Binding<Value> {
        let profile: WritableKeyPath<PictureSettings, StreamProfile> = \PictureSettings.[routeChoice.route]
        let path: WritableKeyPath<PictureSettings, Value> = profile.appending(path: key)
        let draft: Binding<PictureSettings> = $store.draft
        return draft[dynamicMember: path]
    }
}

/// The cloud stream picture settings, for PS5 cloud and PS3 and PS4 cloud streams.
private struct MobileCloudPictureForm: View {
    /// The cloud picture feature holding the saved settings and the measured bandwidth.
    let store: StoreOf<CloudPictureSettingsFeature>

    /// The console or cloud choice, or `nil` when only console settings are offered.
    let streamKind: Binding<PictureSettingsContainerView.StreamKind>?

    @State private var service = CloudPictureSettingsView.Service.psCloud

    var body: some View {
        MobileCloudPictureFields(
            store: store.scope(state: \.picture, action: \.picture),
            streamKind: streamKind,
            service: $service,
            savedBandwidth: store.measuredBandwidth
        )
        .onAppear {
            store.send(.appeared)
        }
    }
}

/// The controls of the cloud picture settings, bound to the saved settings.
private struct MobileCloudPictureFields: View {
    /// The persisted cloud picture settings being edited.
    @Bindable var store: StoreOf<PersistedSettingFeature<CloudPictureSettings>>

    /// The console or cloud choice, or `nil` when only console settings are offered.
    let streamKind: Binding<PictureSettingsContainerView.StreamKind>?

    /// The cloud service whose resolution, bitrate and output controls are shown.
    @Binding var service: CloudPictureSettingsView.Service

    /// The connection bandwidth measured at an earlier launch, used for the automatic PS5 cloud bitrate when
    /// present.
    let savedBandwidth: CloudSavedBandwidth?

    var body: some View {
        MobileSettingsForm {
            MobileSettingsGroup("Stream Settings For") {
                if let streamKind {
                    MobileStreamKindRow(selection: streamKind)
                }
                MobilePickerRow("Service", selection: $service) {
                    ForEach(CloudPictureSettingsView.Service.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .disabled(!store.isEditable)
            }
            MobilePictureStreamGroup(
                height: service == .psCloud
                    ? $store.draft.psCloudHeight
                    : $store.draft.psNowHeight,
                fps: .constant(60),
                bitrate: service == .psCloud
                    ? $store.draft.psCloudBitrateMbps
                    : $store.draft.psNowBitrateMbps,
                automaticBitrate: service == .psCloud
                    ? $store.draft.psCloudAutomaticBitrate
                    : $store.draft.psNowAutomaticBitrate,
                automaticBitrateMbps: automaticBitrateMbps,
                automaticCaption: service == .psCloud
                    ? measuredCaption
                    : nil,
                resolutions: service == .psCloud
                    ? CloudPictureSettings.psCloudHeights
                    : CloudPictureSettings.psNowHeights,
                fixedFrameRate: true
            )
            .disabled(!store.isEditable)
            if service == .psCloud {
                MobileSettingsGroup("Dynamic Range", footer: dynamicRangeDetail) {
                    MobileToggleRow("HDR", isOn: $store.draft.hdr)
                }
                .disabled(!store.isEditable)
                MobileSettingsGroup("Stream Quality", footer: qualityDetail) {
                    MobilePickerRow("Quality", selection: $store.draft.psCloudQuality) {
                        ForEach(CloudStreamQuality.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                }
                .disabled(!store.isEditable)
            }
        } trailing: {
            if service == .psCloud {
                MobileSettingsGroup("Captures", footer: capturesFooter) {
                    MobilePickerRow(captureSaveTitle, selection: $store.draft.captureSaving) {
                        ForEach(CloudCaptureSaving.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                }
                .disabled(!store.isEditable)
            }
            MobilePictureDisplayGroup(
                height: service == .psCloud
                    ? store.draft.psCloudHeight
                    : store.draft.psNowHeight,
                fps: 60,
                output: service == .psCloud
                    ? $store.draft.upscaledOutput
                    : $store.draft.psNowUpscaledOutput,
                upscaler: $store.draft.upscaler,
                presentation: $store.draft.presentationFrameRate
            )
            .disabled(!store.isEditable)
            MobilePictureColourGroup(
                adjustments: $store.draft.adjustments,
                reduceBanding: $store.draft.reduceBanding
            )
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: "cloud picture settings") {
                store.send(.retry)
            }
            .padding(.horizontal, 16)
        }
    }

    private var automaticBitrateMbps: Int {
        guard service == .psCloud else {
            return CloudPictureSettings.automaticBitrateMbps(height: store.draft.psNowHeight)
        }
        return savedBandwidth.map { $0.kbps / 1000 }
            ?? CloudPictureSettings.automaticBitrateMbps(height: store.draft.psCloudHeight)
    }

    private var measuredCaption: String {
        if let savedBandwidth {
            return savedBandwidth.caption(now: Date())
        }
        let fallback = CloudPictureSettings.automaticBitrateMbps(height: store.draft.psCloudHeight)
        return "Measures your connection at launch, or uses \(fallback) Mbps if it cannot."
    }

    private var dynamicRangeDetail: String {
        store.draft.psCloudHeight > CloudPictureSettings.maximumSDRHeight
            ? "Streams in HDR when the display supports it."
            : "PS5 cloud streams HDR only at 1440p and 4K. At \(store.draft.psCloudHeight)p the stream "
                + "stays in SDR."
    }

    private var qualityDetail: String {
        switch store.draft.psCloudQuality {
        case .high:
            "Asks the service for higher picture quality, which uses more data."
        case .stable:
            "Asks the service to favour steady performance over picture quality."
        }
    }

    private var captureSaveTitle: String {
        #if os(macOS)
            "Save Captures to This Mac"
        #else
            "Save Captures to This Device"
        #endif
    }

    private var capturesFooter: String {
        let detail = switch store.draft.captureSaving {
        case .followPlayStation:
            "Follows the download setting in your PS5 capture settings."
        case .always:
            "Downloads every screenshot and video clip once the console finishes uploading it."
        case .never:
            "Captures stay in your PlayStation cloud media gallery."
        }
        guard store.draft.captureSaving != .never else {
            return detail
        }
        return detail + " " + captureDestination
    }

    private var captureDestination: String {
        #if os(macOS)
            store.draft.captureFolder.isEmpty
                ? CloudPictureSettings.defaultCaptureFolder.path
                : URL(fileURLWithPath: store.draft.captureFolder, isDirectory: true).path
        #else
            "Captures are added to your Photos library."
        #endif
    }
}

/// The row choosing whether console or cloud stream settings are shown.
private struct MobileStreamKindRow: View {
    /// The stream kind whose settings are shown.
    @Binding var selection: PictureSettingsContainerView.StreamKind

    var body: some View {
        MobilePickerRow("Streams", selection: $selection) {
            ForEach(PictureSettingsContainerView.StreamKind.allCases, id: \.self) { kind in
                Text(kind.title).tag(kind)
            }
        }
    }
}

/// The Stream group: resolution, frame rate, and the bitrate, chosen automatically or by a slider.
private struct MobilePictureStreamGroup: View {
    /// The stream height in lines chosen from the offered resolutions.
    @Binding var height: Int

    /// The stream frame rate, 30 or 60.
    @Binding var fps: Int

    /// The manual bitrate in megabits per second, edited by the slider.
    @Binding var bitrate: Int

    /// Whether the bitrate is chosen automatically instead of by the slider.
    @Binding var automaticBitrate: Bool

    /// The automatic bitrate in megabits per second, shown when automatic bitrate is on.
    let automaticBitrateMbps: Int

    /// A caption shown under the group while automatic bitrate is on, in place of the default one.
    var automaticCaption: String?

    /// The stream heights offered in the resolution menu.
    let resolutions: [Int]

    /// Whether the frame rate is fixed at 60 and shown as a value instead of a menu.
    var fixedFrameRate = false

    var body: some View {
        MobileSettingsGroup("Stream", footer: footer) {
            MobilePickerRow("Resolution", selection: $height) {
                ForEach(resolutions, id: \.self) { value in
                    Text(verbatim: "\(value)p").tag(value)
                }
            }
            if fixedFrameRate {
                MobileValueRow("Frame Rate", value: "60 fps")
            } else {
                MobilePickerRow("Frame Rate", selection: $fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }
            MobileToggleRow("Automatic Bitrate", isOn: $automaticBitrate)
            if automaticBitrate {
                MobileValueRow("Bitrate", value: "\(automaticBitrateMbps) Mbps")
            } else {
                MobileSliderRow(
                    title: "Bitrate",
                    valueText: "\(bitrate) Mbps",
                    value: bitrateValue,
                    range: bitrateRange,
                    step: 1
                )
            }
        }
    }

    private var footer: String {
        automaticBitrate
            ? automaticCaption ?? "Uses \(automaticBitrateMbps) Mbps for \(height)p."
            : "A lower bitrate uses less bandwidth; a higher one gives higher quality."
    }

    private var bitrateRange: ClosedRange<Double> {
        Double(StreamProfile.bitrateRange.lowerBound)...Double(StreamProfile.bitrateRange.upperBound)
    }

    private var bitrateValue: Binding<Double> {
        Binding {
            Double(bitrate)
        } set: {
            bitrate = Int($0)
        }
    }
}

/// The Display group: upscaled output, upscaling method, presentation frame rate and, when offered, full
/// screen streaming.
private struct MobilePictureDisplayGroup: View {
    /// The stream height, which decides which upscaled outputs and frame generation are available.
    let height: Int

    /// The stream frame rate, used to label the presentation frame rate choices.
    let fps: Int

    /// The upscaled output size.
    @Binding var output: UpscaledOutput

    /// The upscaling method used when output is upscaled.
    @Binding var upscaler: VideoUpscaler

    /// Whether frames are presented at the native rate or doubled by frame generation.
    @Binding var presentation: PresentationFrameRate

    /// Whether the stream is HDR, which shows that frame generation does not apply.
    var hdr = false

    /// The full screen streaming switch's binding, or `nil` to hide the switch.
    var fullScreen: Binding<Bool>?

    var body: some View {
        MobileSettingsGroup("Display", footer: footer) {
            MobilePickerRow("Upscaled Output", selection: $output) {
                ForEach(UpscaledOutput.available(for: height), id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
            MobilePickerRow("Upscaling Method", selection: $upscaler) {
                Text("MetalFX Spatial").tag(VideoUpscaler.metalFX)
                Text("Advanced Spatial").tag(VideoUpscaler.advancedSpatial)
            }
            .disabled(output == .disabled)
            MobilePickerRow("Presentation Frame Rate", selection: $presentation) {
                Text("\(fps) fps (native)").tag(PresentationFrameRate.source)
                Text("\(fps * 2) fps (2×)").tag(PresentationFrameRate.generated120)
                    .disabled(![720, 1080].contains(height))
            }
            if let fullScreen {
                MobileToggleRow(
                    "Full Screen While Streaming",
                    detail: "Full screen lets macOS turn on Game Mode, which doubles the Bluetooth rate for "
                        + "wireless controllers and gives DualSense haptics over Bluetooth more headroom.",
                    isOn: fullScreen
                )
                .accessibilityIdentifier("picture-full-screen")
            }
        }
    }

    private var footer: String? {
        if hdr {
            return "HDR streams play at the native frame rate; frame generation applies to standard dynamic "
                + "range streams."
        }
        if presentation != .source {
            return "Frame generation requires supported hardware and a \(fps * 2) Hz display."
        }
        return nil
    }
}

/// The Colour group: a slider for each colour adjustment, banding reduction and resetting the adjustments.
private struct MobilePictureColourGroup: View {
    /// The colour adjustments the sliders edit, normalised after every change.
    @Binding var adjustments: PictureAdjustments

    /// Whether colour banding reduction is turned on.
    @Binding var reduceBanding: Bool

    var body: some View {
        MobileSettingsGroup(
            "Colour",
            footer: "Applies to new streams. During a stream, adjust it live in the stream menu’s Colour "
                + "panel."
        ) {
            ForEach(StreamMenuColourControls.rows, id: \.title) { row in
                MobileSliderRow(
                    title: row.title,
                    valueText: row.format.describe(adjustments[keyPath: row.value]),
                    value: value(row),
                    range: row.range,
                    step: PictureAdjustments.step
                )
            }
            MobileToggleRow(
                "Reduce Colour Banding",
                detail: "Smooths visible steps in skies and dark gradients, which low bitrates make worse.",
                isOn: $reduceBanding
            )
            MobileButtonRow("Reset Colour") {
                adjustments = PictureAdjustments()
            }
        }
    }

    private func value(_ row: StreamMenuColourControls.Row) -> Binding<Double> {
        Binding(
            get: {
                adjustments[keyPath: row.value]
            },
            set: { next in
                var updated = adjustments
                updated[keyPath: row.value] = next
                adjustments = updated.normalized()
            }
        )
    }
}
