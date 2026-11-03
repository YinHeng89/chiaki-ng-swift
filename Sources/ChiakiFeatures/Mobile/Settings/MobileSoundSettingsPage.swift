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
            SettingsPersistenceBanner(sound.setting, subject: "sound settings") {
                store.send(.sound(.retry))
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    private var mediaGroup: some View {
        MobileSettingsGroup(footer: SoundSettingsForm.mediaDetail(sound.draft.media)) {
            MobilePickerRow("Stream Media", selection: $sound.draft.media) {
                ForEach(StreamMedia.allCases, id: \.self) { media in
                    Text(media.title).tag(media)
                }
            }
        }
    }

    private var outputGroup: some View {
        MobileSettingsGroup(
            "Output",
            footer: "Party chat volume is only for PS4 games streamed from the cloud."
        ) {
            devicePicker(
                "Speaker",
                selection: $sound.draft.outputDevice,
                connected: store.devices.outputs,
                choices: store.outputChoices
            )
            MobileSliderRow(
                title: "Volume",
                valueText: sound.draft.volume.formatted(.percent.precision(.fractionLength(0))),
                value: $sound.draft.volume,
                range: SoundSettings.volumeRange,
                step: 0.05
            )
            MobileSliderRow(
                title: "Party Chat Volume",
                valueText: sound.draft.chatVolume.formatted(.percent.precision(.fractionLength(0))),
                value: $sound.draft.chatVolume,
                range: SoundSettings.volumeRange,
                step: 0.05
            )
        }
    }

    private var microphoneGroup: some View {
        MobileSettingsGroup("Microphone", footer: SoundSettingsForm.microphoneNote) {
            devicePicker(
                "Microphone",
                selection: $sound.draft.inputDevice,
                connected: store.devices.inputs,
                choices: store.inputChoices
            )
            MobileToggleRow("Start Streams With the Microphone On", isOn: $sound.draft.startWithMicrophone)
        }
    }

    private var spatialGroup: some View {
        MobileSettingsGroup("Spatial Sound") {
            MobileToggleRow(
                "3D Audio on Headphones",
                detail: "On headphones and earbuds, PS5 and PS5 cloud streams play the console’s 3D audio. "
                    + "Other streams play stereo.",
                isOn: $sound.draft.spatialAudio.audio3D
            )
            MobileToggleRow(
                "Spatial Audio",
                detail: "Speakers, and headphones without 3D audio, play stereo through Apple spatial audio.",
                isOn: $sound.draft.spatialAudio.appleSpatial
            )
        }
    }

    private var latencyGroup: some View {
        MobileSettingsGroup(
            "Latency",
            footer: "A smaller buffer lowers audio delay. Raise it if the sound crackles or drops out.\n\n"
                + "Changes apply to the next stream. Adjust volume during a stream from the stream controls."
        ) {
            MobileSliderRow(
                title: "Audio Buffer",
                valueText: "\(sound.draft.bufferMilliseconds) ms",
                value: bufferMilliseconds,
                range: Self.bufferRange,
                step: Double(SoundSettings.bufferStep)
            )
            .accessibilityValue("\(sound.draft.bufferMilliseconds) milliseconds")
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
        _ title: String,
        selection: Binding<String?>,
        connected: [String],
        choices: [String]
    ) -> some View {
        MobilePickerRow(
            title,
            detail: selection.wrappedValue.map(connected.contains) == false
                ? "Not connected. The system default is used until it returns."
                : nil,
            selection: selection
        ) {
            Text("System default").tag(String?.none)
            ForEach(choices, id: \.self) { name in
                Text(name).tag(Optional(name))
            }
        }
    }
}
