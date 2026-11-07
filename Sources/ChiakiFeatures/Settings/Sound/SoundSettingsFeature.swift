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
            SettingsPersistenceBanner(store.sound.setting, subject: .settingsSoundPersistenceSubject) {
                store.send(.sound(.retry))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            SettingsCard(.settingsSoundStreamMedia) {
                FocusableSegments(
                    options: StreamMedia.allCases,
                    title: \.title,
                    selection: $store.draft.media
                )
                .accessibilityLabel(.settingsSoundStreamMedia)
                Text(Self.mediaDetail(store.draft.media))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsCard(.settingsSoundOutput) {
                devicePicker(
                    .settingsSoundSpeaker,
                    selection: $store.draft.outputDevice,
                    connected: outputs,
                    choices: outputChoices
                )
                Divider()
                VStack(spacing: 9) {
                    HStack {
                        Text(.settingsSoundVolume)
                        Spacer()
                        Text(store.draft.volume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    Slider(value: $store.draft.volume, in: SoundSettings.volumeRange, step: 0.05)
                        .nativeFocusHighlight()
                        .focusHighlightShape(.capsule)
                        .accessibilityLabel(.settingsSoundVolume)
                        .settingsSliderController(value: $store.draft.volume)
                }
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(.settingsSoundPartyChatVolume)
                        Spacer()
                        Text(store.draft.chatVolume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    Slider(value: $store.draft.chatVolume, in: SoundSettings.volumeRange, step: 0.05)
                        .nativeFocusHighlight()
                        .focusHighlightShape(.capsule)
                        .accessibilityLabel(.settingsSoundPartyChatVolume)
                        .settingsSliderController(value: $store.draft.chatVolume)
                    Text(.settingsSoundPartyChatFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsCard(.settingsSoundMicrophone) {
                devicePicker(
                    .settingsSoundMicrophone,
                    selection: $store.draft.inputDevice,
                    connected: inputs,
                    choices: inputChoices
                )
                Divider()
                Toggle(.settingsSoundStartWithMicrophone, isOn: $store.draft.startWithMicrophone)
                Text(Self.microphoneNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsCard(.settingsSoundSpatialSound) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(.settingsSoundHeadphoneAudio, isOn: $store.draft.spatialAudio.audio3D)
                    Text(.settingsSoundHeadphoneAudioFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(.settingsSoundSpatialAudio, isOn: $store.draft.spatialAudio.appleSpatial)
                    Text(.settingsSoundSpatialAudioFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsCard(.settingsSoundLatency) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(.settingsSoundAudioBuffer)
                        Spacer()
                        Text(.settingsSoundBufferMilliseconds(milliseconds: store.draft.bufferMilliseconds))
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
                    .accessibilityLabel(.settingsSoundAudioBuffer)
                    .accessibilityValue(
                        .settingsSoundBufferMillisecondsSpoken(milliseconds: store.draft.bufferMilliseconds)
                    )
                    .settingsSliderController(value: $store.draft.bufferSliderValue)
                    Text(.settingsSoundBufferFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(.settingsSoundNextStreamFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!store.isEditable)
    }

    /// How the microphone is switched during a stream, naming the keyboard shortcut only where one exists.
    public static var microphoneNote: LocalizedStringResource {
        #if os(macOS)
            .settingsSoundMicrophoneNoteMac
        #else
            .settingsSoundMicrophoneNote
        #endif
    }

    /// What a stream media choice does.
    ///
    /// - Parameter media: The choice.
    /// - Returns: One or two sentences describing it.
    public static func mediaDetail(_ media: StreamMedia) -> LocalizedStringResource {
        switch media {
        case .pictureAndSound:
            .settingsSoundMediaPictureAndSound
        case .soundOnly:
            .settingsSoundMediaSoundOnly
        case .pictureOnly:
            .settingsSoundMediaPictureOnly
        case .controlsOnly:
            .settingsSoundMediaControlsOnly
        }
    }

    private func devicePicker(
        _ title: LocalizedStringResource,
        selection: Binding<String?>,
        connected: [String],
        choices: [String]
    ) -> some View {
        let detail: LocalizedStringResource? = selection.wrappedValue.map(connected.contains) == false
            ? .settingsSoundDeviceDisconnected
            : nil
        return SettingsRow(title, detail: detail) {
            Picker(title, selection: selection) {
                Text(.settingsSoundSystemDefault).tag(String?.none)
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
