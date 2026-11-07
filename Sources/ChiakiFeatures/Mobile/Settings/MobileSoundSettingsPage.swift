import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// The Sound page in the touch library: stream media, the speaker and microphone, volumes, spatial sound and the
/// audio buffer.
struct MobileSoundSettingsPage: View {
    private let store: StoreOf<SoundSettingsFeature>
    @Bindable private var sound: StoreOf<PersistedSettingFeature<SoundSettings>>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings, scoped to the Sound tab feature.
    init(settings: StoreOf<SettingsFeature>) {
        let store = settings.scope(state: \.sound, action: \.sound)
        self.store = store
        sound = store.scope(state: \.sound, action: \.sound)
    }

    var body: some View {
        MobileSettingsForm {
            Group {
                mediaGroup
                outputGroup
                microphoneGroup
            }
            .disabled(!sound.isEditable)
        } trailing: {
            Group {
                spatialGroup
                latencyGroup
            }
            .disabled(!sound.isEditable)
            SettingsPersistenceBanner(sound.setting, subject: .mobileSoundPersistenceSubject) {
                store.send(.sound(.retry))
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    private var mediaGroup: some View {
        MobileSettingsGroup(footer: SoundSettingsForm.mediaDetail(sound.draft.media)) {
            MobilePickerRow(
                .mobileSoundStreamMedia,
                selection: $sound.draft.media,
                choices: StreamMedia.allCases
            ) { media in
                media.title
            }
        }
    }

    private var outputGroup: some View {
        MobileSettingsGroup(
            .mobileSoundOutput,
            footer: .mobileSoundOutputFooter
        ) {
            devicePicker(
                .mobileSoundSpeaker,
                selection: $sound.draft.outputDevice,
                connected: store.devices.outputs,
                choices: store.outputChoices
            )
            MobileSliderRow(
                title: .mobileSoundVolume,
                verbatimValue: sound.draft.volume.formatted(.percent.precision(.fractionLength(0))),
                value: $sound.draft.volume,
                range: SoundSettings.volumeRange,
                step: 0.05
            )
            MobileSliderRow(
                title: .mobileSoundPartyChatVolume,
                verbatimValue: sound.draft.chatVolume.formatted(.percent.precision(.fractionLength(0))),
                value: $sound.draft.chatVolume,
                range: SoundSettings.volumeRange,
                step: 0.05
            )
        }
    }

    private var microphoneGroup: some View {
        MobileSettingsGroup(.mobileSoundMicrophone, footer: SoundSettingsForm.microphoneNote) {
            devicePicker(
                .mobileSoundMicrophone,
                selection: $sound.draft.inputDevice,
                connected: store.devices.inputs,
                choices: store.inputChoices
            )
            MobileToggleRow(.mobileSoundStartWithMicrophone, isOn: $sound.draft.startWithMicrophone)
        }
    }

    private var spatialGroup: some View {
        MobileSettingsGroup(.mobileSoundSpatialSound) {
            MobileToggleRow(
                .mobileSoundHeadphoneAudio,
                detail: .mobileSoundHeadphoneAudioDetail,
                isOn: $sound.draft.spatialAudio.audio3D
            )
            MobileToggleRow(
                .mobileSoundSpatialAudio,
                detail: .mobileSoundSpatialAudioDetail,
                isOn: $sound.draft.spatialAudio.appleSpatial
            )
        }
    }

    private var latencyGroup: some View {
        MobileSettingsGroup(
            .mobileSoundLatency,
            footer: .mobileSoundLatencyFooter
        ) {
            MobileSliderRow(
                title: .mobileSoundAudioBuffer,
                valueText: .mobileSoundAudioBufferValue(ms: sound.draft.bufferMilliseconds),
                value: bufferMilliseconds,
                range: Self.bufferRange,
                step: Double(SoundSettings.bufferStep)
            )
            .accessibilityValue(
                Text(.mobileSoundAudioBufferAccessibility(ms: sound.draft.bufferMilliseconds))
            )
        }
    }

    private static let bufferRange = Double(SoundSettings.bufferRange.lowerBound)...Double(
        SoundSettings.bufferRange.upperBound
    )

    private var bufferMilliseconds: Binding<Double> {
        let milliseconds = $sound.draft.bufferMilliseconds
        return Binding(
            get: {
                Double(milliseconds.wrappedValue)
            },
            set: { value in
                milliseconds.wrappedValue = Int(value.rounded())
            }
        )
    }

    private func devicePicker(
        _ title: LocalizedStringResource,
        selection: Binding<String?>,
        connected: [String],
        choices: [String]
    ) -> some View {
        MobilePickerRow(
            title,
            detail: selection.wrappedValue.map(connected.contains) == false
                ? .mobileSoundDeviceNotConnected
                : nil,
            selection: selection,
            choices: [nil] + choices.map(Optional.init),
            verbatimLabel: { name in
                name ?? String(localized: .mobileSoundSystemDefault)
            }
        )
    }
}
