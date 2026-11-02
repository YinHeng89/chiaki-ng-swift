import ChiakiModels
import SwiftUI
import MenuFocus

/// A settings card with a slider for each colour adjustment, a banding reduction toggle and a button that
/// resets the adjustments.
struct PictureColourGroup: View {
    /// The colour adjustments the sliders edit, normalised after every change.
    @Binding var adjustments: PictureAdjustments
    /// Whether colour banding reduction is turned on.
    @Binding var reduceBanding: Bool

    var body: some View {
        SettingsCard("Colour") {
            ForEach(Array(StreamMenuColourControls.rows.enumerated()), id: \.element.title) { index, row in
                if index > 0 {
                    Divider()
                }
                slider(row)
            }
            Divider()
            Toggle("Reduce colour banding", isOn: $reduceBanding)
            Text("Smooths visible steps in skies and dark gradients, which low bitrates make worse.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(
                    "Applies to new streams. During a stream, adjust it live in the stream menu’s Colour panel."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                FocusButton("Reset") {
                    adjustments = PictureAdjustments()
                }
                .accessibilityLabel("Reset colour")
            }
        }
    }

    private func slider(_ row: StreamMenuColourControls.Row) -> some View {
        let current = adjustments[keyPath: row.value]
        let value = Binding(
            get: {
                adjustments[keyPath: row.value]
            },
            set: { next in
                var updated = adjustments
                updated[keyPath: row.value] = next
                adjustments = updated.normalized()
            }
        )
        return VStack(spacing: 9) {
            HStack {
                Text(row.title)
                Spacer()
                Text(row.format.describe(current)).monospacedDigit()
            }
            Slider(value: value, in: row.range, step: PictureAdjustments.step)
                .nativeFocusHighlight()
                .focusHighlightShape(.capsule)
                .accessibilityLabel(row.title)
                .accessibilityValue(row.format.describe(current))
                .settingsSliderController(value: value)
        }
    }
}
