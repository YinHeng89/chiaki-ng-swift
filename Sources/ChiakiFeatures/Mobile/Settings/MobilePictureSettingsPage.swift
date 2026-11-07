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
                .mobilePictureStreamSettingsFor,
                footer: .mobilePictureInternetFooter
            ) {
                if let streamKind {
                    MobileStreamKindRow(selection: streamKind)
                }
                MobilePickerRow(
                    .mobilePictureConnection,
                    selection: $routeChoice,
                    choices: PictureSettingsView.RouteChoice.allCases
                ) { choice in
                    choice.title
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
            SettingsPersistenceBanner(store.setting, subject: .mobilePicturePersistenceSubject) {
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
            .mobilePictureCodec,
            footer: .mobilePictureCodecFooter(codec: String(localized: PictureSettings.Codec.h264.title))
        ) {
            MobilePickerRow(
                .mobilePictureCodecPs5,
                selection: ps5,
                choices: PictureSettings.Codec.choices
            ) { codec in
                codec.title
            }
            MobileToggleRow(
                .mobilePictureHdrWhenSupported,
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
            MobileSettingsGroup(.mobilePictureStreamSettingsFor) {
                if let streamKind {
                    MobileStreamKindRow(selection: streamKind)
                }
                MobilePickerRow(
                    .mobilePictureService,
                    selection: $service,
                    choices: CloudPictureSettingsView.Service.allCases
                ) { choice in
                    choice.title
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
                MobileSettingsGroup(.mobilePictureDynamicRange, footer: dynamicRangeDetail) {
                    MobileToggleRow(.mobilePictureHdr, isOn: $store.draft.hdr)
                }
                .disabled(!store.isEditable)
                MobileSettingsGroup(.mobilePictureStreamQuality, footer: qualityDetail) {
                    MobilePickerRow(
                        .mobilePictureQuality,
                        selection: $store.draft.psCloudQuality,
                        choices: CloudStreamQuality.allCases
                    ) { choice in
                        choice.title
                    }
                }
                .disabled(!store.isEditable)
            }
        } trailing: {
            if service == .psCloud {
                MobileSettingsGroup(.mobilePictureCaptures, footer: capturesFooter) {
                    MobilePickerRow(
                        captureSaveTitle,
                        selection: $store.draft.captureSaving,
                        choices: CloudCaptureSaving.allCases
                    ) { choice in
                        choice.title
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
            SettingsPersistenceBanner(store.setting, subject: .mobilePictureCloudPersistenceSubject) {
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

    private var measuredCaption: LocalizedStringResource {
        if let savedBandwidth {
            return savedBandwidth.caption(now: Date())
        }
        let fallback = CloudPictureSettings.automaticBitrateMbps(height: store.draft.psCloudHeight)
        return .mobilePictureMeasuredCaption(mbps: fallback)
    }

    private var dynamicRangeDetail: LocalizedStringResource {
        store.draft.psCloudHeight > CloudPictureSettings.maximumSDRHeight
            ? .mobilePictureHdrSupported
            : .mobilePictureHdrUnsupported(height: String(store.draft.psCloudHeight))
    }

    private var qualityDetail: LocalizedStringResource {
        switch store.draft.psCloudQuality {
        case .high:
            .mobilePictureQualityHigh
        case .stable:
            .mobilePictureQualityStable
        }
    }

    private var captureSaveTitle: LocalizedStringResource {
        #if os(macOS)
            .mobilePictureSaveCapturesMac
        #else
            .mobilePictureSaveCapturesDevice
        #endif
    }

    private var capturesFooter: LocalizedStringResource {
        #if os(macOS)
            switch store.draft.captureSaving {
            case .followPlayStation:
                .mobilePictureCapturesFollowFolder(folder: captureFolder)
            case .always:
                .mobilePictureCapturesAlwaysFolder(folder: captureFolder)
            case .never:
                .mobilePictureCapturesNever
            }
        #else
            switch store.draft.captureSaving {
            case .followPlayStation:
                .mobilePictureCapturesFollowPhotos
            case .always:
                .mobilePictureCapturesAlwaysPhotos
            case .never:
                .mobilePictureCapturesNever
            }
        #endif
    }

    #if os(macOS)
        private var captureFolder: String {
            store.draft.captureFolder.isEmpty
                ? CloudPictureSettings.defaultCaptureFolder.path
                : URL(fileURLWithPath: store.draft.captureFolder, isDirectory: true).path
        }
    #endif
}

/// The row choosing whether console or cloud stream settings are shown.
private struct MobileStreamKindRow: View {
    /// The stream kind whose settings are shown.
    @Binding var selection: PictureSettingsContainerView.StreamKind

    var body: some View {
        MobilePickerRow(
            .mobilePictureStreams,
            selection: $selection,
            choices: PictureSettingsContainerView.StreamKind.allCases
        ) { kind in
            kind.title
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
    var automaticCaption: LocalizedStringResource?

    /// The stream heights offered in the resolution menu.
    let resolutions: [Int]

    /// Whether the frame rate is fixed at 60 and shown as a value instead of a menu.
    var fixedFrameRate = false

    var body: some View {
        MobileSettingsGroup(.mobilePictureStream, footer: footer) {
            MobilePickerRow(.mobilePictureResolution, selection: $height, choices: resolutions) { value in
                .mobilePictureResolutionValue(height: String(value))
            }
            if fixedFrameRate {
                MobileValueRow(.mobilePictureFrameRate, value: .mobilePictureFrameRateValue(fps: 60))
            } else {
                MobilePickerRow(.mobilePictureFrameRate, selection: $fps, choices: [30, 60]) { rate in
                    .mobilePictureFrameRateValue(fps: rate)
                }
            }
            MobileToggleRow(.mobilePictureAutomaticBitrate, isOn: $automaticBitrate)
            if automaticBitrate {
                MobileValueRow(
                    .mobilePictureBitrate,
                    value: .mobilePictureBitrateValue(mbps: automaticBitrateMbps)
                )
            } else {
                MobileSliderRow(
                    title: .mobilePictureBitrate,
                    valueText: .mobilePictureBitrateValue(mbps: bitrate),
                    value: bitrateValue,
                    range: bitrateRange,
                    step: 1
                )
            }
        }
    }

    private var footer: LocalizedStringResource {
        automaticBitrate
            ? automaticCaption ?? .mobilePictureBitrateAutomaticFooter(
                mbps: automaticBitrateMbps,
                height: String(height)
            )
            : .mobilePictureBitrateManualFooter
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
        MobileSettingsGroup(.mobilePictureDisplay, footer: footer) {
            MobilePickerRow(
                .mobilePictureUpscaledOutput,
                selection: $output,
                choices: UpscaledOutput.available(for: height)
            ) { value in
                value.title
            }
            MobilePickerRow(
                .mobilePictureUpscalingMethod,
                selection: $upscaler,
                choices: [VideoUpscaler.metalFX, .advancedSpatial]
            ) { upscaler in
                upscaler == .metalFX
                    ? .mobilePictureUpscalerMetalFX
                    : .mobilePictureUpscalerAdvanced
            }
            .disabled(output == .disabled)
            MobilePickerRow(
                .mobilePicturePresentationFrameRate,
                selection: $presentation,
                choices: [720, 1080].contains(height) || presentation == .generated120
                    ? [PresentationFrameRate.source, .generated120]
                    : [.source]
            ) { rate in
                rate == .source
                    ? .mobilePicturePresentationNative(fps: fps)
                    : .mobilePicturePresentationGenerated(fps: fps * 2)
            }
            if let fullScreen {
                MobileToggleRow(
                    .mobilePictureFullScreen,
                    detail: .mobilePictureFullScreenDetail,
                    isOn: fullScreen
                )
                .accessibilityIdentifier("picture-full-screen")
            }
        }
    }

    private var footer: LocalizedStringResource? {
        if hdr {
            return .mobilePictureHdrFrameGenerationFooter
        }
        if presentation != .source {
            return .mobilePictureFrameGenerationFooter(rate: fps * 2)
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
            .mobilePictureColour,
            footer: .mobilePictureColourFooter
        ) {
            ForEach(StreamMenuColourControls.rows, id: \.control) { row in
                MobileSliderRow(
                    title: row.title,
                    verbatimValue: row.format.describe(adjustments[keyPath: row.value]),
                    value: value(row),
                    range: row.range,
                    step: PictureAdjustments.step
                )
            }
            MobileToggleRow(
                .mobilePictureReduceBanding,
                detail: .mobilePictureReduceBandingDetail,
                isOn: $reduceBanding
            )
            MobileButtonRow(.mobilePictureResetColour) {
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
