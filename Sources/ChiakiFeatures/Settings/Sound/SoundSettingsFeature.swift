import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI

/// The Sound tab: the saved sound settings and the devices that can be chosen.
@Reducer
public struct SoundSettingsFeature {
    /// The tab's state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The saved sound settings.
        public var sound = PersistedSettingFeature<SoundSettings>.State()

        /// The devices listed by the last listing.
        public internal(set) var devices = SoundDevices()

        /// The listing that is running, if any.
        public internal(set) var listing: OperationID?

        /// Creates the tab with nothing loaded.
        public init() {
        }

        /// The speakers a picker offers.
        public var outputChoices: [String] {
            SoundDevices.choices(devices.outputs, selected: sound.draft.outputDevice)
        }

        /// The microphones a picker offers.
        public var inputChoices: [String] {
            SoundDevices.choices(devices.inputs, selected: sound.draft.inputDevice)
        }
    }

    /// Everything the Sound tab reacts to.
    public enum Action: Equatable, Sendable {
        /// The saved settings.
        case sound(PersistedSettingFeature<SoundSettings>.Action)

        /// The tab appeared; loads the settings and lists the devices.
        case appeared

        /// A device listing finished.
        case listed(OperationID, SoundDevices)
    }

    @Dependency(\.settings) private var settings
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Scope(state: \.sound, action: \.sound) {
            PersistedSettingFeature<SoundSettings>()
        }
        Reduce { state, action in
            switch action {
            case .sound:
                return .none
            case .appeared:
                let id = OperationID(uuid: uuid())
                state.listing = id
                return .merge(
                    .send(.sound(.appeared)),
                    .run { [settings] send in
                        await send(.listed(id, settings.soundDevices()))
                    }
                )
            case let .listed(id, devices):
                guard state.listing == id else {
                    return .none
                }
                state.listing = nil
                state.devices = devices
                return .none
            }
        }
    }
}

/// The Sound tab.
public struct SoundSettingsView: View {
    /// The Sound tab feature holding the saved sound settings and the connected audio devices.
    public let store: StoreOf<SoundSettingsFeature>

    /// Creates a sound settings view.
    ///
    /// - Parameter store: The Sound tab feature holding the saved sound settings and the connected audio devices.
    public init(store: StoreOf<SoundSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SoundSettingsForm(
                store: store.scope(state: \.sound, action: \.sound),
                outputs: store.devices.outputs,
                outputChoices: store.outputChoices,
                inputs: store.devices.inputs,
                inputChoices: store.inputChoices
            )
            SettingsPersistenceBanner(store.sound.setting, subject: "sound settings") {
                store.send(.sound(.retry))
            }
        }
        .frame(maxWidth: 660)
        .frame(maxWidth: .infinity)
        .onAppear {
            store.send(.appeared)
        }
    }
}

/// The controls of the Sound tab, bound to the saved sound settings.
public struct SoundSettingsForm: View {
    /// The persisted sound settings the form edits and saves.
    @Bindable public var store: StoreOf<PersistedSettingFeature<SoundSettings>>
    /// The names of the connected speakers, used to flag a saved speaker that is not connected.
    public let outputs: [String]
    /// The speakers offered in the picker, including a saved one that is not connected.
    public let outputChoices: [String]
    /// The names of the connected microphones, used to flag a saved microphone that is not connected.
    public let inputs: [String]
    /// The microphones offered in the picker, including a saved one that is not connected.
    public let inputChoices: [String]

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Stream media") {
                FocusableSegments(
                    options: StreamMedia.allCases,
                    title: \.title,
                    selection: $store.draft.media
                )
                .accessibilityLabel("Stream media")
                Text(Self.mediaDetail(store.draft.media))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsCard("Output") {
                devicePicker(
                    "Speaker",
                    selection: $store.draft.outputDevice,
                    connected: outputs,
                    choices: outputChoices
                )
                Divider()
                VStack(spacing: 9) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text(store.draft.volume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    Slider(value: $store.draft.volume, in: SoundSettings.volumeRange, step: 0.05)
                        .nativeFocusHighlight()
                        .focusHighlightShape(.capsule)
                        .accessibilityLabel("Volume")
                        .settingsSliderController(value: $store.draft.volume)
                }
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Party chat volume")
                        Spacer()
                        Text(store.draft.chatVolume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    Slider(value: $store.draft.chatVolume, in: SoundSettings.volumeRange, step: 0.05)
                        .nativeFocusHighlight()
                        .focusHighlightShape(.capsule)
                        .accessibilityLabel("Party chat volume")
                        .settingsSliderController(value: $store.draft.chatVolume)
                    Text(
                        "Only for PS4 games streamed from the cloud."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            SettingsCard("Microphone") {
                devicePicker(
                    "Microphone",
                    selection: $store.draft.inputDevice,
                    connected: inputs,
                    choices: inputChoices
                )
                Divider()
                Toggle("Start streams with the microphone on", isOn: $store.draft.startWithMicrophone)
                Text(Self.microphoneNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsCard("Spatial sound") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("3D audio on headphones", isOn: $store.draft.spatialAudio.audio3D)
                    Text(
                        "On headphones and earbuds, PS5 and PS5 cloud streams play the console’s 3D audio. "
                            + "Other streams play stereo."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Spatial audio", isOn: $store.draft.spatialAudio.appleSpatial)
                    Text(
                        "Speakers, and headphones without 3D audio, play stereo through Apple spatial audio."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            SettingsCard("Latency") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Audio buffer")
                        Spacer()
                        Text("\(store.draft.bufferMilliseconds) ms")
                            .monospacedDigit()
                    }
                    Slider(
                        value: $store.draft.bufferSliderValue,
                        in: Double(SoundSettings.bufferRange.lowerBound)...Double(SoundSettings.bufferRange
                            .upperBound),
                        step: Double(SoundSettings.bufferStep)
                    )
                    .nativeFocusHighlight()
                    .focusHighlightShape(.capsule)
                    .accessibilityLabel("Audio buffer")
                    .accessibilityValue("\(store.draft.bufferMilliseconds) milliseconds")
                    .settingsSliderController(value: $store.draft.bufferSliderValue)
                    Text("A smaller buffer lowers audio delay. Raise it if the sound crackles or drops out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Changes apply to the next stream. Adjust volume during a stream from the stream controls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!store.isEditable)
    }

    /// How the microphone is switched during a stream, naming the keyboard shortcut only where one exists.
    public static var microphoneNote: String {
        #if os(macOS)
            "Turn the microphone on or off during a console or cloud stream with Command-M, the DualSense mic "
                + "button or the Sound panel of the stream controls."
        #else
            "Turn the microphone on or off during a console or cloud stream with the DualSense mic button or "
                + "the Sound panel of the stream controls."
        #endif
    }

    /// What a stream media choice does.
    ///
    /// - Parameter media: The choice.
    /// - Returns: One or two sentences describing it.
    public static func mediaDetail(_ media: StreamMedia) -> String {
        switch media {
        case .pictureAndSound:
            "Console and cloud streams send both picture and sound."
        case .soundOnly:
            "This device plays sound but shows no picture. The console sends a minimal 360p picture that is "
                + "discarded, to save bandwidth."
        case .pictureOnly:
            "This device shows the picture but plays no game sound. Haptics still play."
        case .controlsOnly:
            "This device shows no picture and plays no game sound, acting only as controller and microphone. "
                + "Haptics still play."
        }
    }

    private func devicePicker(
        _ title: String,
        selection: Binding<String?>,
        connected: [String],
        choices: [String]
    ) -> some View {
        let detail = selection.wrappedValue.map(connected.contains) == false
            ? "Not connected. The system default is used until it returns."
            : nil
        return SettingsRow(title, detail: detail) {
            Picker(title, selection: selection) {
                Text("System default").tag(String?.none)
                ForEach(choices, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
        }
    }
}

private extension SoundSettings {
    var bufferSliderValue: Double {
        get {
            Double(bufferMilliseconds)
        }
        set {
            bufferMilliseconds = Int(newValue.rounded())
        }
    }
}
