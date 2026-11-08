import ChiakiModels
import SwiftUI
import DesignSystem
import MenuFocus

/// The Colour panel, with brightness, contrast, saturation and gamma sliders, a colour banding toggle and a
/// reset button, all reachable by controller.
struct StreamMenuColourControls: View {
    /// How a colour adjustment value is written beside its slider.
    enum Format {
        /// A signed whole percentage offset, such as +5 or -10.
        case signedPercent
        /// A whole percentage, such as 110%.
        case percent
        /// A number with two decimal places.
        case decimal

        /// Writes an adjustment value in this format.
        func describe(_ value: Double) -> String {
            switch self {
            case .signedPercent:
                let points = Int((value * 100).rounded())
                return points > 0
                    ? "+\(points)"
                    : "\(points)"
            case .percent:
                return "\(Int((value * 100).rounded()))%"
            case .decimal:
                return value.formatted(.number.precision(.fractionLength(2)))
            }
        }
    }

    /// One colour adjustment slider and the picture setting it edits.
    struct Row {
        /// The label shown above the slider and used as its accessibility label.
        let title: LocalizedStringResource
        /// The stream menu control that identifies the slider for focus.
        let control: StreamMenuControl
        /// The range the slider covers.
        let range: ClosedRange<Double>
        /// The adjustment field the slider reads and writes.
        let value: WritableKeyPath<PictureAdjustments, Double>
        /// How the value is written beside the slider.
        let format: Format
    }

    /// The adjustment sliders in display order.
    static let rows = [
        Row(title: .playbackMenuColourBrightness, control: .colourBrightness,
            range: PictureAdjustments.brightnessRange,
            value: \.brightness, format: .signedPercent),
        Row(title: .playbackMenuColourContrast, control: .colourContrast,
            range: PictureAdjustments.contrastRange,
            value: \.contrast, format: .percent),
        Row(title: .playbackMenuColourSaturation, control: .colourSaturation,
            range: PictureAdjustments.saturationRange,
            value: \.saturation, format: .percent),
        Row(title: .playbackMenuColourGamma, control: .colourGamma,
            range: PictureAdjustments.gammaRange,
            value: \.gamma, format: .decimal)
    ]

    /// The panel's controls in navigation order: the sliders, then the banding toggle and the reset button.
    static let controls = rows.map(\.control) + [.colourDeband, .colourReset]

    /// The picture adjustments the sliders edit, normalised on every change.
    @Binding var adjustments: PictureAdjustments
    /// Whether colour banding reduction is on.
    @Binding var reduceBanding: Bool
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    var focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus, used to draw a control as focused.
    var focusedControl: StreamMenuControl?

    /// Moves one adjustment slider by whole steps for controller input and normalises the result.
    /// - Parameters:
    ///   - adjustments: The adjustments to start from.
    ///   - control: The slider control to move.
    ///   - offset: The number of steps to move, negative to decrease.
    /// - Returns: The adjusted values, or `nil` when the control is not a colour slider.
    static func adjusted(_ adjustments: PictureAdjustments, _ control: StreamMenuControl,
                         by offset: Int) -> PictureAdjustments? {
        guard let row = rows.first(where: { $0.control == control }) else {
            return nil
        }
        var next = adjustments
        next[keyPath: row.value] += Double(offset) * PictureAdjustments.step
        return next.normalized()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(.playbackMenuColourTitle).font(.title2.weight(.semibold))
            ForEach(Self.rows, id: \.control) { row in
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(row.title) {
                        Text(row.format.describe(adjustments[keyPath: row.value])).monospacedDigit()
                    }
                    slider(row)
                }
            }
            debandToggle
            FocusButton {
                adjustments = PictureAdjustments()
            } label: {
                Label(.playbackMenuColourReset, systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: .colourReset,
                focused: focusedControl == .colourReset
            ))
            .glassControlStyle()
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func slider(_ row: Row) -> some View {
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
        let slider = Slider(value: value, in: row.range, step: PictureAdjustments.step)
            .accessibilityLabel(row.title)
            .accessibilityValue(row.format.describe(adjustments[keyPath: row.value]))
        if let focus {
            slider
                .modifier(StreamMenuControlFocus(
                    focus: focus,
                    target: row.control,
                    focused: focusedControl == row.control
                ))
                .focusHighlightShape(.capsule)
        } else {
            slider
        }
    }

    @ViewBuilder
    private var debandToggle: some View {
        let toggle = Toggle(.playbackMenuColourReduceBanding, isOn: $reduceBanding)
        if let focus {
            toggle.modifier(StreamMenuControlFocus(
                focus: focus,
                target: .colourDeband,
                focused: focusedControl == .colourDeband,
                highlight: false
            ))
        } else {
            toggle
        }
    }
}
