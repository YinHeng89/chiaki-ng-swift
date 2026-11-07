import ChiakiModels
import SwiftUI
import DesignSystem
import MenuFocus
import PlatformUI

/// A settings card for stream resolution, frame rate and bitrate, with an automatic bitrate toggle that
/// replaces the bitrate slider when on.
public struct PictureStreamGroup: View {
    /// The stream height in lines chosen from the offered resolutions.
    @Binding public var height: Int
    /// The stream frame rate, 30 or 60.
    @Binding public var fps: Int
    /// The manual bitrate in megabits per second, edited by the slider.
    @Binding public var bitrate: Int
    /// Whether the bitrate is chosen automatically instead of by the slider.
    @Binding public var automaticBitrate: Bool
    /// The automatic bitrate in megabits per second, shown when automatic bitrate is on.
    public var automaticBitrateMbps: Int
    /// A caption shown under the automatic bitrate toggle in place of the default one.
    public var automaticCaption: LocalizedStringResource?
    /// The stream heights offered in the resolution picker.
    public var resolutions: [Int]
    @Environment(\.menuNavigator) private var navigator
    @State private var hostWindow: PlatformWindow?

    /// Creates a picture stream group.
    ///
    /// - Parameters:
    ///   - height: The stream height in lines chosen from the offered resolutions.
    ///   - fps: The stream frame rate, 30 or 60.
    ///   - bitrate: The manual bitrate in megabits per second, edited by the slider.
    ///   - automaticBitrate: Whether the bitrate is chosen automatically instead of by the slider.
    ///   - automaticBitrateMbps: The automatic bitrate in megabits per second, shown when automatic bitrate is on.
    ///   - automaticCaption: A caption shown under the automatic bitrate toggle in place of the default one.
    ///   - resolutions: The stream heights offered in the resolution picker.
    ///   - fixedFrameRate: Whether the frame rate is fixed at 60 and shown as text instead of a picker.
    public init(
        height: Binding<Int>,
        fps: Binding<Int>,
        bitrate: Binding<Int>,
        automaticBitrate: Binding<Bool>,
        automaticBitrateMbps: Int,
        automaticCaption: LocalizedStringResource? = nil,
        resolutions: [Int],
        fixedFrameRate: Bool = false
    ) {
        _height = height
        _fps = fps
        _bitrate = bitrate
        _automaticBitrate = automaticBitrate
        self.automaticBitrateMbps = automaticBitrateMbps
        self.automaticCaption = automaticCaption
        self.resolutions = resolutions
        self.fixedFrameRate = fixedFrameRate
    }

    /// Whether the frame rate is fixed at 60 and shown as text instead of a picker.
    public var fixedFrameRate: Bool

    public var body: some View {
        SettingsCard(.settingsPictureStream) {
            SettingsRow(.settingsPictureResolution) {
                Picker(.settingsPictureStreamResolution, selection: $height) {
                    ForEach(resolutions, id: \.self) { value in
                        Text(verbatim: "\(value)p").tag(value)
                    }
                }
            }
            Divider()
            SettingsRow(.settingsPictureFrameRate) {
                if fixedFrameRate {
                    Text(.settingsPictureFpsValue(fps: 60)).frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Picker(.settingsPictureFrameRate, selection: $fps) {
                        Text(.settingsPictureFpsValue(fps: 30)).tag(30)
                        Text(.settingsPictureFpsValue(fps: 60)).tag(60)
                    }
                }
            }
            Divider()
            VStack(spacing: 9) {
                HStack {
                    Text(.settingsPictureBitrate)
                    Spacer()
                    Text(.settingsPictureBitrateValue(mbps: shownBitrate)).monospacedDigit()
                }
                Toggle(.settingsPictureAutomaticBitrate, isOn: $automaticBitrate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WindowAccessor { hostWindow = $0 })
                    .onChange(of: automaticBitrate) { _, automatic in
                        if !automatic {
                            focusBitrateSlider()
                        }
                    }
                if automaticBitrate {
                    Text(automaticBitrateCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Slider(value: bitrateValue,
                           in: Double(StreamProfile.bitrateRange.lowerBound)...Double(StreamProfile
                               .bitrateRange.upperBound),
                           step: 1)
                        .nativeFocusHighlight()
                        .focusHighlightShape(.capsule)
                        .accessibilityLabel(.settingsPictureBitrate)
                        .accessibilityValue(.settingsPictureBitrateSpoken(mbps: bitrate))
                        .settingsSliderController(value: bitrateValue)
                    HStack {
                        Text(.settingsPictureLessBandwidth)
                        Spacer()
                        Text(.settingsPictureHigherQuality)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension PictureStreamGroup {
    /// Moves controller focus from the automatic bitrate toggle down to the bitrate slider it just revealed,
    /// trying again for a few turns while the slider is still appearing.
    private func focusBitrateSlider() {
        guard let navigator, navigator.inputMode.mode == .controller, let window = hostWindow else {
            return
        }
        Task { @MainActor in
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(40))
                if navigator.moveGeometric(
                    .down, in: window, belowGlobalY: nil, allowUnaligned: true, horizontalWeight: 0.3
                ) {
                    return
                }
            }
        }
    }

    private var bitrateValue: Binding<Double> {
        Binding {
            Double(bitrate)
        } set: {
            bitrate = Int($0)
        }
    }

    private var automaticBitrateCaption: LocalizedStringResource {
        automaticCaption ?? .settingsPictureBitrateUses(mbps: automaticBitrateMbps, height: String(height))
    }

    private var shownBitrate: Int {
        automaticBitrate
            ? automaticBitrateMbps
            : bitrate
    }
}

/// A settings card with the PS5 cloud HDR toggle and a caption explaining whether HDR applies at the chosen
/// height.
public struct PictureDynamicRangeGroup: View {
    /// Whether HDR is requested for PS5 cloud streams.
    @Binding public var hdr: Bool
    /// The chosen stream height, which decides whether HDR can apply.
    public let height: Int

    /// Creates a picture dynamic range group.
    ///
    /// - Parameters:
    ///   - hdr: Whether HDR is requested for PS5 cloud streams.
    ///   - height: The chosen stream height, which decides whether HDR can apply.
    public init(hdr: Binding<Bool>, height: Int) {
        _hdr = hdr
        self.height = height
    }

    public var body: some View {
        SettingsCard(.settingsPictureDynamicRange) {
            Toggle(.settingsPictureHdr, isOn: $hdr)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: LocalizedStringResource {
        height > CloudPictureSettings.maximumSDRHeight
            ? .settingsPictureHdrSupported
            : .settingsPictureHdrHeightTooLow(height: String(height))
    }
}

/// A settings card for the PS5 codec, the HDR toggle that HEVC enables, and the fixed PS4 codec.
public struct PictureCodecGroup: View {
    /// The codec requested from PS5 consoles.
    @Binding public var ps5: PictureSettings.Codec
    /// Whether HDR is used when the screen supports it.
    @Binding public var hdr: Bool

    /// Creates a picture codec group.
    ///
    /// - Parameters:
    ///   - ps5: The codec requested from PS5 consoles.
    ///   - hdr: Whether HDR is used when the screen supports it.
    public init(ps5: Binding<PictureSettings.Codec>, hdr: Binding<Bool>) {
        _ps5 = ps5
        _hdr = hdr
    }

    public var body: some View {
        SettingsCard(.settingsPictureCodec) {
            SettingsRow(.settingsPictureCodecPS5) {
                Self.picker(.settingsPictureCodecPicker, selection: $ps5)
            }
            Divider()
            SettingsRow(.settingsPictureCodecHdr, detail: Self.detail(for: ps5)) {
                Toggle(.settingsPictureCodecHdr, isOn: $hdr)
                    .disabled(ps5 != .hevc)
            }
            Divider()
            Text(.settingsPictureCodecPS4(codec: String(localized: PictureSettings.Codec.h264.title)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Returns the caption under the HDR toggle explaining what the given codec means for HDR.
    public static func detail(for codec: PictureSettings.Codec) -> LocalizedStringResource {
        switch codec {
        case .hevc, .hevcHDR:
            return .settingsPictureCodecHevcDetail
        case .h264:
            return .settingsPictureCodecAvcDetail
        }
    }

    private static func picker(
        _ title: LocalizedStringResource,
        selection: Binding<PictureSettings.Codec>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(PictureSettings.Codec.choices, id: \.self) { codec in
                Text(codec.title).tag(codec)
            }
        }
    }
}

/// A settings card for upscaled output, upscaling method, presentation frame rate and, when offered, full
/// screen streaming.
public struct PictureDisplayGroup: View {
    /// The stream height, which decides which upscaled outputs and frame generation are available.
    public let height: Int
    /// The stream frame rate, used to label the presentation frame rate choices.
    public let fps: Int
    /// The upscaled output size.
    @Binding public var output: UpscaledOutput
    /// The upscaling method used when output is upscaled.
    @Binding public var upscaler: VideoUpscaler
    /// Whether frames are presented at the native rate or doubled by frame generation.
    @Binding public var presentation: PresentationFrameRate
    /// Whether the stream is HDR, which shows that frame generation does not apply.
    public var hdr: Bool
    /// The full screen streaming toggle's binding, or `nil` to hide the toggle.
    public var fullScreen: Binding<Bool>?

    /// Creates a picture display group.
    ///
    /// - Parameters:
    ///   - height: The stream height, which decides which upscaled outputs and frame generation are available.
    ///   - fps: The stream frame rate, used to label the presentation frame rate choices.
    ///   - output: The upscaled output size.
    ///   - upscaler: The upscaling method used when output is upscaled.
    ///   - presentation: Whether frames are presented at the native rate or doubled by frame generation.
    ///   - hdr: Whether the stream is HDR, which shows that frame generation does not apply.
    ///   - fullScreen: The full screen streaming toggle's binding, or `nil` to hide the toggle.
    public init(
        height: Int,
        fps: Int,
        output: Binding<UpscaledOutput>,
        upscaler: Binding<VideoUpscaler>,
        presentation: Binding<PresentationFrameRate>,
        hdr: Bool = false,
        fullScreen: Binding<Bool>? = nil
    ) {
        self.height = height
        self.fps = fps
        _output = output
        _upscaler = upscaler
        _presentation = presentation
        self.hdr = hdr
        self.fullScreen = fullScreen
    }

    public var body: some View {
        SettingsCard(.settingsPictureDisplay) {
            SettingsRow(.settingsPictureUpscaledOutput) {
                Picker(.settingsPictureUpscaledOutput, selection: $output) {
                    ForEach(UpscaledOutput.available(for: height), id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
            }
            Divider()
            SettingsRow(.settingsPictureUpscalingMethod) {
                Picker(.settingsPictureUpscalingMethod, selection: $upscaler) {
                    Text(.settingsPictureUpscalerMetalFX).tag(VideoUpscaler.metalFX)
                    Text(.settingsPictureUpscalerAdvancedSpatial).tag(VideoUpscaler.advancedSpatial)
                }.disabled(output == .disabled)
            }
            Divider()
            SettingsRow(.settingsPicturePresentationFrameRate) {
                Picker(.settingsPicturePresentationFrameRate, selection: $presentation) {
                    Text(.settingsPicturePresentationNative(fps: fps)).tag(PresentationFrameRate.source)
                    Text(.settingsPicturePresentationGenerated(fps: fps * 2))
                        .tag(PresentationFrameRate.generated120)
                        .disabled(![720, 1080].contains(height))
                }
            }
            if hdr {
                Text(.settingsPicturePresentationHdrFooter)
                    .font(.caption).foregroundStyle(.secondary)
            } else if presentation != .source {
                Text(.settingsPictureFrameGenerationFooter(refreshRate: fps * 2))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let fullScreen {
                Divider()
                Toggle(.settingsPictureFullScreen, isOn: fullScreen)
                    .accessibilityIdentifier("picture-full-screen")
                Text(.settingsPictureFullScreenFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A disclosure group style with a focusable header button that rotates its chevron and collapses the content
/// without animating its layout.
public struct PictureDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a picture disclosure style.
    public init() {
    }

    /// Builds the focusable header and the content, which is hidden, disabled and removed from accessibility
    /// while collapsed.
    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(configuration)
            VStack(alignment: .leading, spacing: 12) {
                configuration.content
            }
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(
                height: configuration.isExpanded
                    ? nil
                    : 0,
                alignment: .top
            )
            .clipped()
            .opacity(
                configuration.isExpanded
                    ? 1
                    : 0
            )
            .disabled(!configuration.isExpanded)
            .allowsHitTesting(configuration.isExpanded)
            .accessibilityHidden(!configuration.isExpanded)
        }
    }

    private func header(_ configuration: Configuration) -> some View {
        FocusButton {
            withAnimation(AppMotion.animation(reduced: reduceMotion)) {
                configuration.isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                AppIcon.expand.image
                    .font(.caption.weight(.medium))
                    .rotationEffect(
                        .degrees(
                            configuration.isExpanded
                                ? 90
                                : 0
                        )
                    )
                    .accessibilityHidden(true)
                configuration.label
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            configuration.isExpanded
                ? .settingsPictureDisclosureExpanded
                : .settingsPictureDisclosureCollapsed
        )
    }
}
