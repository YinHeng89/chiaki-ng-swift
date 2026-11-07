import ChiakiModels
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// A panel of the stream menu.
public enum StreamMenuPanel: String, CaseIterable, Sendable {
    /// Frame generation, upscaling and how the video fits the window.
    case picture = "Picture"
    /// Brightness, contrast, saturation, gamma and debanding adjustments.
    case colour = "Colour"
    /// Stream volume, 3D audio, spatial audio and the microphone.
    case sound = "Sound"
    /// The launch settings: resolution, frame rate, codec, HDR, quality and bitrate, applied by restarting.
    case stream = "Stream"
    /// The diagnostics overlay options, video analysis and frame counters.
    case statistics = "Statistics"
    /// Couch co-op seats and Kakusan guests.
    case players = "Players"
    /// Game invitations friends sent to the game being streamed, during a PS5 cloud or PS Now stream.
    case invitations = "Invitations"
    /// The trophies of the game being streamed, during a PS5 cloud or PS Now stream.
    case trophies = "Trophies"
    /// Going to the console home screen and ending the stream.
    case session = "Session"

    /// The name shown on the panel's tab.
    var title: LocalizedStringResource {
        switch self {
        case .picture:
            .playbackMenuPanelPicture
        case .colour:
            .playbackMenuPanelColour
        case .sound:
            .playbackMenuPanelSound
        case .stream:
            .playbackMenuPanelStream
        case .statistics:
            .playbackMenuPanelStatistics
        case .players:
            .playbackMenuPanelPlayers
        case .invitations:
            .playbackMenuPanelInvitations
        case .trophies:
            .playbackMenuPanelTrophies
        case .session:
            .playbackMenuPanelSession
        }
    }

    /// The SF Symbol name shown on the panel's tab.
    var symbol: String {
        switch self {
        case .picture:
            "display"
        case .stream:
            "antenna.radiowaves.left.and.right"
        case .colour:
            "slider.horizontal.3"
        case .sound:
            "speaker.wave.2"
        case .statistics:
            "chart.xyaxis.line"
        case .players:
            "person.2"
        case .invitations:
            "envelope"
        case .trophies:
            "trophy"
        case .session:
            "power"
        }
    }
}

/// A control inside a stream menu panel that controller navigation can focus.
enum StreamMenuControl: Hashable {
    /// The picker for the resolution the stream launches at.
    case streamResolution
    /// The picker for the frame rate the stream launches at.
    case streamFrameRate
    /// The picker for the codec the stream launches with.
    case streamCodec
    /// The toggle that asks for HDR at launch.
    case streamHDR
    /// The picker that favours picture quality or a stable stream.
    case streamQuality
    /// The toggle that lets the bitrate follow the resolution and frame rate.
    case streamAutomaticBitrate
    /// The slider for the bitrate the stream launches with.
    case streamBitrate
    /// The button that restarts the stream with the changed launch settings.
    case streamRelaunch
    /// The toggle that doubles the frame rate with frame generation.
    case pictureGenerated
    /// The picker for the upscaled output resolution.
    case pictureOutput
    /// The picker that chooses the upscaling algorithm.
    case pictureUpscaler
    /// One video fit option, identified by its raw value.
    case pictureFit(String)
    /// The zoom slider shown for the zoomed fit mode.
    case pictureZoom
    /// The brightness slider.
    case colourBrightness
    /// The contrast slider.
    case colourContrast
    /// The saturation slider.
    case colourSaturation
    /// The gamma slider.
    case colourGamma
    /// The toggle that reduces colour banding.
    case colourDeband
    /// The button that restores the default colour adjustments.
    case colourReset
    /// The stream volume slider.
    case soundVolume
    /// The party chat volume slider.
    case soundChatVolume
    /// The toggle for 3D audio on headphones.
    case soundAudio3D
    /// The spatial audio picker.
    case soundSpatial
    /// The microphone mute control.
    case soundMicrophone
    /// One diagnostics overlay level, identified by its raw value.
    case statisticsOverlay(String)
    /// One diagnostics overlay glass style, identified by its raw value.
    case diagnosticsGlass(String)
    /// One diagnostics overlay layout, identified by its raw value.
    case diagnosticsLayout(String)
    /// One video analysis mode, identified by its raw value.
    case videoAnalysis(String)
    /// The button that moves the HDR heatmap's brightness marker by controller.
    case measureBrightness
    /// The Join button of one game invitation, identified by its session id.
    case invitationJoin(String)
    /// The button that reads the game invitations again.
    case invitationsRefresh
    /// The button that opens the friend picker to invite friends to the streamed game.
    case invitationsInvite
    /// The friend picker's Back button.
    case inviteBack
    /// The friend picker's button that sends the invitations.
    case inviteSend
    /// The friend picker's button that asks for a share link.
    case inviteShare
    /// One friend in the picker, identified by account id.
    case inviteFriend(String)
    /// The Trophies panel's button that reads the game's trophies again.
    case trophiesRefresh
    /// The Trophies panel's choice of which trophies are shown.
    case trophiesFilter
    /// The Trophies panel's choice of the trophies' order.
    case trophiesSort
    /// The Trophies panel's toggle that reverses the trophies' order.
    case trophiesReverse
    /// One trophy in the Trophies panel, identified by its number.
    case trophy(Int)
    /// One connection tips topic in the Statistics panel, identified by its raw value.
    case troubleshootTopic(String)
    /// The button that returns to the console home screen.
    case sessionHome
    /// The Session panel's Saved Data Management button, on a PS4 game streamed through PS Now.
    case sessionSavedData
    /// The button that ends the stream.
    case sessionStop
    /// The button that retries loading the menu settings after a failure.
    case retryLoad
    /// The button that opens the control settings of the couch player on the given pad.
    case playerControls(UInt8)
    /// The button that removes the couch player on the given pad.
    case playerRemove(UInt8)
    /// The button that reassigns the couch player on the given pad to another controller.
    case playerReassign(UInt8)
    /// The button that adds a couch player on the given pad.
    case playerAdd(UInt8)
    /// One controller offered while picking a player's controller, identified by its device id.
    case playerPick(UInt32)
    /// The button that cancels picking a player's controller.
    case playerCancelPick
    /// A Kakusan guest control in the Players panel.
    case remote(KakusanMenuControl)
}

extension StreamMenuControl {
    /// Whether the control is a slider, which Confirm starts and finishes adjusting.
    var isSlider: Bool {
        switch self {
        case .pictureZoom, .colourBrightness, .colourContrast, .colourSaturation, .colourGamma,
             .soundVolume, .soundChatVolume, .streamBitrate:
            return true
        default:
            return false
        }
    }
}

/// Which stream menu slider is being adjusted, with the configuration to restore if the adjustment is cancelled.
typealias StreamMenuSliderNavigationState = SliderAdjustment<StreamMenuControl, StreamTuningConfiguration>

/// Every element of the stream menu that controller navigation can move focus to.
enum StreamMenuFocusTarget: Hashable {
    /// The dock's Settings item after the divider, which opens the app settings.
    case settings
    /// The dock's developer log item after Settings, shown while the live log button is turned on.
    case log
    /// The tab that selects a panel.
    case tab(StreamMenuPanel)
    /// A control inside the open panel.
    case control(StreamMenuControl)
    /// The close button at the end of the tab bar, which hands input back to the game.
    case exit
    /// The Done button of the brightness measuring card.
    case measureDone
}

/// Shows the controls of one stream menu panel, bound to the menu's draft tuning and diagnostics settings.
///
/// With a `focus` binding the controls join controller navigation; without one they behave as plain controls.
struct StreamMenuPanelContent: View {
    /// The panel to show.
    let panel: StreamMenuPanel
    /// The stream tuning draft that the picture, colour and sound controls edit.
    @Binding var configuration: StreamTuningConfiguration
    /// The renderer counters shown in the Statistics panel.
    let statistics: RenderStatistics
    /// The diagnostics overlay level chosen in the Statistics panel.
    @Binding var diagnosticsLevel: StreamDiagnosticsAppearance.Level
    /// The diagnostics overlay glass style chosen in the Statistics panel.
    @Binding var diagnosticsGlass: StreamDiagnosticsAppearance.Glass
    /// The diagnostics overlay layout chosen in the Statistics panel.
    @Binding var diagnosticsLayout: StreamDiagnosticsAppearance.Layout
    /// The video analysis mode chosen in the Statistics panel.
    @Binding var videoAnalysis: StreamVideoAnalysisMode
    /// The connection tips topic chosen in the Statistics panel.
    @Binding var troubleshootTopic: StreamTroubleshootTopic
    /// Whether frame generation can be turned on; when false the toggle is disabled with a note saying why.
    let frameGenerationEligible: Bool
    /// Why 3D audio is unavailable for this stream, or `nil` when it can be turned on.
    var audio3DDisabledReason: LocalizedStringResource?
    /// The title of the button that ends the stream.
    let stopTitle: LocalizedStringResource
    /// Ends the stream.
    let stop: () -> Void
    /// Returns to the console home screen, or `nil` when the stream cannot do that.
    var goHome: (() -> Void)?
    /// Opens PS Now's Application Saved Data Management screen, or `nil` when the stream does not offer it.
    var openSavedData: (() -> Void)?
    /// Restarts the stream with the changed launch settings, or `nil` when the stream cannot restart.
    var restart: (() -> Void)?
    /// Starts measuring brightness with the heatmap marker, or `nil` while the heatmap is off.
    var measureBrightness: (() -> Void)?
    /// The cloud datacenter the stream uses, shown in the Statistics panel when present.
    var datacenter: CloudDatacenterSelection?
    /// The cloud bandwidth measurement, shown in the Statistics panel when present.
    var bandwidth: CloudBandwidthReport?
    /// The menu's controller focus, or `nil` when the panel is used without controller navigation.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The control that currently holds controller focus, used to draw its highlight.
    var focusedControl: StreamMenuControl?
    /// The couch co-op store that drives the Players panel, when couch play is available.
    var couch: StoreOf<CouchReducer>?
    /// The Kakusan host store whose guests appear in the Players panel, when hosting.
    var kakusan: StoreOf<KakusanHostFeature>?
    /// The microphone store behind the Sound panel's microphone control, when a microphone is available.
    var microphone: StoreOf<MicrophoneReducer>?
    /// The Invitations panel's store, during a PS5 cloud or PS Now stream.
    var invitations: StoreOf<CloudInvitationsFeature>?
    /// The Trophies panel's store, during a PS5 cloud or PS Now stream.
    var trophies: StoreOf<StreamTrophiesFeature>?
    /// Which page of the Trophies panel shows.
    var trophiesPaging = StreamTrophiesPaging()

    var body: some View {
        Group {
            switch panel {
            case .picture:
                picturePanel
            case .stream:
                StreamMenuLaunchControls(
                    configuration: $configuration,
                    relaunch: restart,
                    focus: focus,
                    focusedControl: focusedControl
                )
            case .colour:
                StreamMenuColourControls(
                    adjustments: binding(\.adjustments),
                    reduceBanding: binding(\.reduceBanding),
                    focus: focus,
                    focusedControl: focusedControl
                )
            case .sound:
                StreamMenuSoundControls(
                    volume: binding(\.volume),
                    chatVolume: binding(\.chatVolume),
                    spatialAudio: binding(\.spatialAudio),
                    audio3DDisabledReason: audio3DDisabledReason,
                    microphone: microphone,
                    focus: focus,
                    focusedControl: focusedControl
                )
            case .statistics:
                statisticsPanel
            case .players:
                playersPanel
            case .invitations:
                if let invitations {
                    StreamMenuInvitationsControls(
                        store: invitations,
                        focus: focus,
                        focusedControl: focusedControl
                    )
                }
            case .trophies:
                if let trophies {
                    StreamMenuTrophiesControls(
                        store: trophies,
                        focus: focus,
                        focusedControl: focusedControl,
                        paging: trophiesPaging
                    )
                }
            case .session:
                sessionPanel
            }
        }
        .toggleStyle(AccentCheckboxToggleStyle(focusable: focus == nil))
    }

    private var picturePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelTitle(.playbackMenuPanelPicture)
            focused(
                Toggle(
                    .playbackMenuPictureGenerateFrames(fps: configuration.sourceFPS * 2),
                    isOn: generated120
                ),
                target: .pictureGenerated,
                highlight: false
            )
            .disabled(!frameGenerationEligible)
            if !frameGenerationEligible {
                Text(frameGenerationNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            StreamMenuDropdown(
                title: .playbackMenuPictureUpscaledOutput,
                options: UpscaledOutput.available(for: configuration.nativeHeight),
                optionTitle: { $0.title },
                selection: binding(\.upscaledOutput),
                target: .pictureOutput,
                focus: focus,
                focused: focusedControl == .pictureOutput
            )
            StreamMenuDropdown(
                title: .playbackMenuPictureUpscaling,
                options: VideoUpscaler.allCases,
                optionTitle: {
                    $0 == .metalFX
                        ? .playbackMenuPictureUpscalerMetalFX
                        : .playbackMenuPictureUpscalerAdvanced
                },
                selection: binding(\.upscaler),
                target: .pictureUpscaler,
                focus: focus,
                focused: focusedControl == .pictureUpscaler
            )
            .disabled(configuration.upscaledOutput == .disabled)
            StreamMenuDisplayControls(
                videoFit: binding(\.videoFit),
                focus: focus,
                focusedControl: focusedControl
            )
        }
    }

    private var frameGenerationNote: LocalizedStringResource {
        configuration.hdrRequested
            ? .playbackMenuPictureFrameGenerationHdr
            : .playbackMenuPictureFrameGenerationRequirements(rate: configuration.sourceFPS * 2)
    }

    private var statisticsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelTitle(.playbackMenuStatisticsTitle)
            if let datacenter {
                LabeledContent(.playbackMenuStatisticsDatacenter) {
                    Text(datacenter.statisticsDescription)
                }
            }
            if let bandwidth {
                LabeledContent(.playbackMenuStatisticsBandwidth) {
                    Text(bandwidth.statisticsDescription)
                }
            }
            StreamMenuChoiceRow(
                options: StreamDiagnosticsAppearance.Level.allCases,
                title: { $0.title },
                selection: $diagnosticsLevel,
                focus: focus,
                focusedControl: focusedControl,
                control: { .statisticsOverlay($0.rawValue) }
            )
            StreamMenuChoiceRow(
                options: StreamDiagnosticsAppearance.Glass.allCases,
                title: { $0.title },
                selection: $diagnosticsGlass,
                focus: focus,
                focusedControl: focusedControl,
                control: { .diagnosticsGlass($0.rawValue) }
            )
            StreamMenuChoiceRow(
                options: StreamDiagnosticsAppearance.Layout.allCases,
                title: { $0.title },
                selection: $diagnosticsLayout,
                focus: focus,
                focusedControl: focusedControl,
                control: { .diagnosticsLayout($0.rawValue) }
            )
            StreamMenuChoiceRow(
                options: StreamVideoAnalysisMode.allCases,
                title: { $0.title },
                selection: $videoAnalysis,
                focus: focus,
                focusedControl: focusedControl,
                control: { .videoAnalysis($0.rawValue) }
            )
            if videoAnalysis != .off {
                Text(.playbackMenuStatisticsAnalysisDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let measureBrightness {
                FocusButton(action: measureBrightness) {
                    Label(.playbackMenuMeasureTitle, systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .modifier(OptionalStreamMenuButtonFocus(
                    focus: focus,
                    target: .measureBrightness,
                    focused: focusedControl == .measureBrightness
                ))
                .glassControlStyle()
                .controlSize(.large)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                statistic(.playbackMenuStatisticsSourceFrames, value: statistics.surfaces)
                statistic(.playbackMenuStatisticsRenderedFrames, value: statistics.completed)
                statistic(.playbackMenuStatisticsGeneratedFrames, value: statistics.frameGenerationGenerated)
                statistic(.playbackMenuStatisticsFrameGenerationDrops, value: statistics.generatedDrops)
                statistic(.playbackMenuStatisticsPresentationMisses, value: statistics.deadlineMisses)
                statistic(.playbackMenuStatisticsFramesLost, value: statistics.lost)
                statistic(.playbackMenuStatisticsGpuErrors, value: statistics.gpuError)
            }
            StreamMenuTroubleshootControls(
                topic: $troubleshootTopic,
                focus: focus,
                focusedControl: focusedControl
            )
        }
    }

    private var sessionPanel: some View {
        StreamMenuSessionControls(
            stopTitle: stopTitle,
            stop: stop,
            goHome: goHome,
            openSavedData: openSavedData,
            focus: focus,
            focusedControl: focusedControl
        )
    }

    private func panelTitle(_ title: LocalizedStringResource) -> some View {
        Text(title).font(.title2.weight(.semibold))
    }

    @ViewBuilder
    private func focused<Content: View>(
        _ content: Content,
        target: StreamMenuControl,
        title: LocalizedStringResource? = nil,
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

    private func statistic(_ label: LocalizedStringResource, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(value ?? 0))
                .font(.title3.monospacedDigit().weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
    }
}

extension StreamMenuPanelContent {
    private var generated120: Binding<Bool> {
        Binding(
            get: {
                configuration.presentationFrameRate == .generated120
            },
            set: { enabled in
                var value = configuration
                if enabled {
                    value.presentationFrameRate = .generated120
                } else {
                    value.presentationFrameRate = .source
                }
                configuration = value
            }
        )
    }

    private func binding<T>(_ key: WritableKeyPath<StreamTuningConfiguration, T>) -> Binding<T> {
        Binding(
            get: {
                configuration[keyPath: key]
            },
            set: { updated in
                var value = configuration
                value[keyPath: key] = updated
                configuration = value
            }
        )
    }
}

/// The Session panel, with a button that sends the console to its Home screen when available, a button that
/// opens PS Now's Application Saved Data Management for a PS4 game, and a button that ends the stream.
private struct StreamMenuSessionControls: View {
    /// The title of the button that ends the stream.
    let stopTitle: LocalizedStringResource
    /// Ends the stream.
    let stop: () -> Void
    /// Sends the console to its Home screen, or `nil` to hide the Home button.
    var goHome: (() -> Void)?
    /// Opens PS Now's Application Saved Data Management screen, or `nil` to hide its button.
    var openSavedData: (() -> Void)?
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus, used to draw a button as focused.
    var focusedControl: StreamMenuControl?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(.playbackMenuSessionTitle).font(.title2.weight(.semibold))
            if let goHome {
                FocusButton(action: goHome) {
                    Label(.playbackMenuSessionGoHome, systemImage: "house")
                        .frame(maxWidth: .infinity)
                }
                .modifier(OptionalStreamMenuButtonFocus(
                    focus: focus,
                    target: .sessionHome,
                    focused: focusedControl == .sessionHome
                ))
                .glassControlStyle()
                .controlSize(.large)
            }
            if let openSavedData {
                FocusButton(action: openSavedData) {
                    Label(.playbackMenuSessionSavedData, systemImage: "externaldrive.badge.icloud")
                        .frame(maxWidth: .infinity)
                }
                .modifier(OptionalStreamMenuButtonFocus(
                    focus: focus,
                    target: .sessionSavedData,
                    focused: focusedControl == .sessionSavedData
                ))
                .glassControlStyle()
                .controlSize(.large)
            }
            FocusButton(role: .destructive, action: stop) {
                Label(stopTitle, systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: .sessionStop,
                focused: focusedControl == .sessionStop
            ))
            .glassProminentControlStyle()
            .tint(.red)
            .controlSize(.large)
        }
    }
}

/// The picture fit choices of the Picture panel, with a zoom slider that appears when Zoom is chosen.
struct StreamMenuDisplayControls: View {
    /// The fit mode and zoom the controls edit.
    @Binding var videoFit: VideoFit
    /// The stream menu focus binding, or `nil` when the controls are shown outside controller navigation.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus, used to draw a control as focused.
    var focusedControl: StreamMenuControl?

    /// The fit controls in navigation order: one per fit mode, then the zoom slider when Zoom is chosen.
    static func controls(for videoFit: VideoFit) -> [StreamMenuControl] {
        var controls = VideoFitMode.allCases.map {
            StreamMenuControl.pictureFit($0.rawValue)
        }
        if videoFit.mode == .zoom {
            controls.append(.pictureZoom)
        }
        return controls
    }

    /// Whether two controls are options in the same fit row, so vertical moves skip from one to the other.
    static func sharesRow(_ first: StreamMenuControl, _ second: StreamMenuControl) -> Bool {
        if case .pictureFit = first, case .pictureFit = second {
            return true
        }
        return false
    }

    /// The control vertical navigation should land on, which for the fit row is the selected fit option.
    static func entry(_ control: StreamMenuControl, videoFit: VideoFit) -> StreamMenuControl {
        guard case .pictureFit = control else {
            return control
        }
        return .pictureFit(videoFit.mode.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StreamMenuChoiceRow(
                options: VideoFitMode.allCases,
                title: \.title,
                selection: $videoFit.mode,
                focus: focus,
                focusedControl: focusedControl,
                control: { .pictureFit($0.rawValue) }
            )
            if videoFit.mode == .zoom {
                LabeledContent(.playbackMenuPictureZoom) {
                    zoomDescription.monospacedDigit()
                }
                zoomSlider
            }
        }
    }

    private var zoomDescription: Text {
        guard videoFit.zoom > VideoFit.zoomRange.lowerBound else {
            return Text(.playbackMenuPictureZoomNoBlackBars)
        }
        return Text(verbatim: videoFit.zoom.formatted(.number.precision(.fractionLength(2))) + "×")
    }

    @ViewBuilder
    private var zoomSlider: some View {
        let slider = Slider(value: $videoFit.zoom, in: VideoFit.zoomRange, step: 0.05)
        if let focus {
            slider
                .modifier(StreamMenuControlFocus(
                    focus: focus,
                    target: .pictureZoom,
                    focused: focusedControl == .pictureZoom
                ))
                .focusHighlightShape(.capsule)
        } else {
            slider
        }
    }
}

/// The Sound panel, with volume sliders, the 3D audio and spatial audio toggles and the microphone button.
private struct StreamMenuSoundControls: View {
    /// The stream volume.
    @Binding var volume: Double
    /// The party voice chat level, or `nil` when the stream mixes voice chat into its sound.
    @Binding var chatVolume: Double?
    /// The 3D audio and Apple spatial audio settings.
    @Binding var spatialAudio: SpatialAudio
    /// Why 3D audio is unavailable for this stream, which disables its toggle, or `nil` when it is available.
    var audio3DDisabledReason: LocalizedStringResource?
    /// The microphone store, or `nil` when the stream has no microphone.
    var microphone: StoreOf<MicrophoneReducer>?
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus, used to draw a control as focused.
    var focusedControl: StreamMenuControl?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(.playbackMenuSoundTitle).font(.title2.weight(.semibold))
            LabeledContent(.playbackMenuSoundVolume) {
                Text(volume, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
            volumeSlider
            if let level = chatVolume {
                LabeledContent(.playbackMenuSoundPartyChatVolume) {
                    Text(level, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                chatVolumeSlider
            }
            focused(
                Toggle(.playbackMenuSoundHeadphoneAudio, isOn: audio3D),
                target: .soundAudio3D,
                highlight: false
            )
            .disabled(audio3DDisabledReason != nil)
            Text(audio3DDisabledReason ?? .playbackMenuSoundHeadphoneAudioDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
            focused(
                Toggle(.playbackMenuSoundSpatialAudio, isOn: $spatialAudio.appleSpatial),
                target: .soundSpatial,
                highlight: false
            )
            Text(.playbackMenuSoundSpatialAudioDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let microphone, microphone.available {
                StreamMenuMicrophoneControl(
                    phase: microphone.phase,
                    toggle: {
                        microphone.send(.toggle)
                    },
                    focus: focus,
                    focused: focusedControl == .soundMicrophone
                )
            }
        }
    }

    private var audio3D: Binding<Bool> {
        Binding(
            get: {
                audio3DDisabledReason == nil && spatialAudio.audio3D
            },
            set: { enabled in
                spatialAudio.audio3D = enabled
            }
        )
    }

    @ViewBuilder
    private func focused<Content: View>(
        _ content: Content,
        target: StreamMenuControl,
        title: LocalizedStringResource? = nil,
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

    private var chatLevel: Binding<Double> {
        Binding(
            get: {
                chatVolume ?? 1
            },
            set: { level in
                chatVolume = level
            }
        )
    }

    @ViewBuilder
    private var chatVolumeSlider: some View {
        let slider = Slider(value: chatLevel, in: SoundSettings.volumeRange, step: 0.05)
            .accessibilityLabel(.playbackMenuSoundPartyChatVolume)
        if let focus {
            slider
                .modifier(StreamMenuControlFocus(
                    focus: focus,
                    target: .soundChatVolume,
                    focused: focusedControl == .soundChatVolume
                ))
                .focusHighlightShape(.capsule)
        } else {
            slider
        }
    }

    @ViewBuilder
    private var volumeSlider: some View {
        let slider = Slider(value: $volume, in: SoundSettings.volumeRange, step: 0.05)
            .accessibilityLabel(.playbackMenuSoundVolume)
        if let focus {
            slider
                .modifier(StreamMenuControlFocus(
                    focus: focus,
                    target: .soundVolume,
                    focused: focusedControl == .soundVolume
                ))
                .focusHighlightShape(.capsule)
        } else {
            slider
        }
    }
}

/// The microphone button and its status line, which turns the microphone on, cancels it or mutes it
/// according to its phase.
struct StreamMenuMicrophoneControl: View {
    /// The microphone's phase, which sets the button's title, symbol and status.
    let phase: MicrophoneMachine.Phase
    /// Advances the microphone, the same as the microphone shortcut or the controller's mic button.
    let toggle: () -> Void
    /// The stream menu focus binding, or `nil` when the button is shown outside controller navigation.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// Whether the button holds controller focus.
    var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FocusButton(action: toggle) {
                Label(title, systemImage: symbol)
                    .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: .soundMicrophone,
                focused: focused
            ))
            .glassControlStyle()
            .controlSize(.large)
            .help(Self.help)
            .accessibilityValue(status)
            status
                .font(.caption)
                .foregroundStyle(statusIsProblem
                    ? Color.red
                    : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: LocalizedStringResource {
        switch phase {
        case .off, .denied, .failed:
            .playbackMenuMicrophoneTurnOn
        case .requestingPermission, .connecting:
            .playbackMenuMicrophoneCancel
        case .live(_, muted: true):
            .playbackMenuMicrophoneUnmute
        case .live(_, muted: false):
            .playbackMenuMicrophoneMute
        }
    }

    private var symbol: String {
        switch phase {
        case .off, .denied, .failed, .requestingPermission, .connecting:
            "mic"
        case .live(_, muted: true):
            "mic.slash"
        case .live(_, muted: false):
            "mic.fill"
        }
    }

    private var status: Text {
        switch phase {
        case .off:
            Text(Self.offStatus)
        case .requestingPermission:
            Text(.playbackMenuMicrophoneWaitingForAccess)
        case .denied:
            Text(Self.deniedStatus)
        case .connecting:
            Text(.playbackMenuMicrophoneConnecting)
        case .live(_, muted: true):
            Text(.playbackMenuMicrophoneMuted)
        case .live(_, muted: false):
            Text(.playbackMenuMicrophoneLive)
        case .failed(let failure):
            Self.message(failure)
        }
    }

    private var statusIsProblem: Bool {
        switch phase {
        case .denied, .failed:
            true
        case .off, .requestingPermission, .connecting, .live:
            false
        }
    }

    /// The button's help, naming the shortcuts this platform has.
    static var help: LocalizedStringResource {
        #if os(macOS)
            return .playbackMenuMicrophoneHelpMac
        #else
            return .playbackMenuMicrophoneHelp
        #endif
    }

    /// The status while the microphone is off, naming the shortcuts this platform has.
    static var offStatus: LocalizedStringResource {
        #if os(macOS)
            return .playbackMenuMicrophoneOffMac
        #else
            return .playbackMenuMicrophoneOff
        #endif
    }

    /// The status while microphone access is denied, naming where this platform grants it.
    static var deniedStatus: LocalizedStringResource {
        #if os(macOS)
            return .playbackMenuMicrophoneDeniedMac
        #else
            return .playbackMenuMicrophoneDenied
        #endif
    }

    /// Explains a microphone failure to the user.
    static func message(_ failure: MicrophoneFailure) -> Text {
        switch failure {
        case .streamUnavailable:
            Text(.playbackMenuMicrophoneStreamUnavailable)
        case .consoleRejected:
            Text(.playbackMenuMicrophoneConsoleRejected)
        case .captureUnavailable(let detail), .interrupted(let detail):
            Text(detail)
        }
    }
}
