import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// The Stream panel: the resolution, frame rate, codec, HDR, quality and bitrate the stream launches with,
/// and the button that restarts or reconnects the stream once one of them changed.
struct StreamMenuLaunchControls: View {
    /// The stream tuning draft whose launch settings the controls edit.
    @Binding var configuration: StreamTuningConfiguration
    /// Restarts the stream with the changed launch settings, or `nil` when it cannot.
    var relaunch: (() -> Void)?
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus, used to draw a control as focused.
    var focusedControl: StreamMenuControl?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Stream").font(.title2.weight(.semibold))
            if options.heights.count > 1 {
                dropdown("Resolution", options: options.heights, selection: $configuration.launch.height,
                         target: .streamResolution) { "\($0)p" }
            }
            if options.frameRates.count > 1 {
                dropdown(
                    "Frame rate",
                    options: options.frameRates,
                    selection: $configuration.launch.frameRate,
                    target: .streamFrameRate
                ) { "\($0) fps" }
            }
            if options.codecs.count > 1 {
                dropdown("Codec", options: options.codecs, selection: $configuration.launch.codec,
                         target: .streamCodec) { $0.title }
            }
            if options.offersHDR(for: configuration.launch) {
                focused(Toggle("HDR", isOn: $configuration.launch.hdr), target: .streamHDR, highlight: false)
                Text(hdrDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if options.quality {
                dropdown(
                    "Quality",
                    options: CloudStreamQuality.allCases,
                    selection: $configuration.launch.quality,
                    target: .streamQuality
                ) { $0.title }
            }
            if options.bitrates != nil {
                bitrateControls
            }
            if configuration.restartNeeded {
                relaunchButton
            }
        }
    }

    /// The panel's focusable controls, from top to bottom, for a tuning.
    ///
    /// - Parameter configuration: The tuning draft.
    /// - Returns: The controls the panel shows.
    static func controls(for configuration: StreamTuningConfiguration) -> [StreamMenuControl] {
        let options = configuration.launchOptions
        var controls = [StreamMenuControl]()
        if options.heights.count > 1 {
            controls.append(.streamResolution)
        }
        if options.frameRates.count > 1 {
            controls.append(.streamFrameRate)
        }
        if options.codecs.count > 1 {
            controls.append(.streamCodec)
        }
        if options.offersHDR(for: configuration.launch) {
            controls.append(.streamHDR)
        }
        if options.quality {
            controls.append(.streamQuality)
        }
        if options.bitrates != nil {
            controls.append(.streamAutomaticBitrate)
            if !configuration.launch.automaticBitrate {
                controls.append(.streamBitrate)
            }
        }
        if configuration.restartNeeded {
            controls.append(.streamRelaunch)
        }
        return controls
    }

    private var options: StreamLaunchOptions {
        configuration.launchOptions
    }

    private func dropdown<Option: Hashable>(
        _ title: String,
        options: [Option],
        selection: Binding<Option>,
        target: StreamMenuControl,
        optionTitle: @escaping (Option) -> String
    ) -> some View {
        StreamMenuDropdown(title: title, options: options, optionTitle: optionTitle, selection: selection,
                           target: target, focus: focus, focused: focusedControl == target)
    }

    @ViewBuilder private var bitrateControls: some View {
        LabeledContent("Bitrate") {
            Text(verbatim: "\(shownBitrate) Mbps").monospacedDigit()
        }
        focused(
            Toggle("Automatic bitrate", isOn: $configuration.launch.automaticBitrate),
            target: .streamAutomaticBitrate,
            highlight: false
        )
        if configuration.launch.automaticBitrate {
            Text(automaticDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            bitrateSlider
        }
    }

    @ViewBuilder private var bitrateSlider: some View {
        let slider = Slider(
            value: Binding(
                get: {
                    Double(configuration.launch.bitrateMbps)
                },
                set: { value in
                    configuration.launch.bitrateMbps = Int(value)
                }
            ),
            in: Double(StreamProfile.bitrateRange.lowerBound)...Double(StreamProfile.bitrateRange.upperBound),
            step: 1
        )
        .accessibilityLabel("Bitrate")
        .accessibilityValue("\(configuration.launch.bitrateMbps) megabits per second")
        if let focus {
            slider
                .modifier(StreamMenuControlFocus(
                    focus: focus,
                    target: .streamBitrate,
                    focused: focusedControl == .streamBitrate
                ))
                .focusHighlightShape(.capsule)
        } else {
            slider
        }
    }

    private var relaunchButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            FocusButton {
                relaunch?()
            } label: {
                Label(relaunchTitle, systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: .streamRelaunch,
                focused: focusedControl == .streamRelaunch
            ))
            .glassControlStyle()
            .controlSize(.large)
            Text(relaunchDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shownBitrate: Int {
        configuration.launch.automaticBitrate
            ? options.automaticBitrateMbps(height: configuration.launch.height)
            : configuration.launch.bitrateMbps
    }

    private var automaticDetail: String {
        let fallback = options.automaticBitrateMbps(height: configuration.launch.height)
        if options.bitrates == .measuredCloud {
            return "Measures your connection at launch, or uses \(fallback) Mbps if it cannot."
        }
        return "Uses \(fallback) Mbps for \(configuration.launch.height)p."
    }

    private var hdrDetail: String {
        switch options.relaunch {
        case .restart:
            configuration.launch.height > CloudPictureSettings.maximumSDRHeight
                ? "Streams in HDR when the display supports it."
                : "PS5 cloud streams HDR only at 1440p and 4K. At \(configuration.launch.height)p the stream "
                    + "stays in SDR."
        case .reconnect:
            "Streams in HDR when the screen supports it. Bright highlights also need an HDR TV connected to "
                + "the PS5."
        }
    }

    private var relaunchTitle: String {
        switch options.relaunch {
        case .reconnect:
            "Apply and reconnect"
        case .restart:
            "Apply and restart"
        }
    }

    private var relaunchDetail: String {
        switch options.relaunch {
        case .reconnect:
            "The stream reconnects with the new settings. The game keeps running on the console."
        case .restart:
            "The game restarts with the new settings. Unsaved progress is lost."
        }
    }

    @ViewBuilder
    private func focused<Content: View>(
        _ content: Content,
        target: StreamMenuControl,
        title: String? = nil,
        highlight: Bool = true
    ) -> some View {
        if let focus {
            let control = StreamMenuControlFocus(
                focus: focus,
                target: target,
                focused: focusedControl == target,
                highlight: highlight
            )
            if let title {
                HStack(spacing: 8) {
                    Text(title)
                    content.labelsHidden().modifier(control)
                }
            } else {
                content.modifier(control)
            }
        } else {
            content
        }
    }
}
