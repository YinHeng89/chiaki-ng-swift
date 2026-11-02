import ChiakiModels
import CoreGraphics
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The binding board: a controller drawing with a chip for every console control, joined by a line to the
/// button that drives it, and the controls with no place on the drawing in a row underneath.
///
/// For the keyboard the drawing is the console's own DualSense and each chip shows its key. For a
/// controller or a player the drawing is that controller's, and each chip's line follows its button, so a
/// rebind moves the line. Choosing a chip, or its spot on the drawing, starts listening for that control.
struct ControlsBindingBoard: View {
    /// The bindings shown.
    let preset: InputPreset

    /// What kind of input the chips show: keys for the keyboard, buttons for a controller.
    let source: InputSource

    /// The controller drawing; the console's DualSense for the keyboard.
    let artwork: ControllerArtwork

    /// The controller family whose button names are shown.
    let family: ControllerFamily

    /// The controller's button layout.
    let layout: ButtonLayout

    /// The control listening for an input, if any.
    let listening: PlayStationControl?

    /// The controls the latest undoable change touched.
    let changed: Set<PlayStationControl>

    /// Starts listening for a control.
    let select: (PlayStationControl) -> Void

    @Environment(\.screenLayout) private var screenLayout
    @MenuFocusState private var focus: PlayStationControl?
    @State private var origin: PlayStationControl?

    @State private var width: CGFloat = 0

    /// Draws the board.
    var body: some View {
        let placement = ControlsBoardPlacement(
            width: width,
            aspectRatio: artwork.aspectRatio,
            points: placedPoints
        )
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topLeading) {
                drawing(placement)
                lines(placement)
                ForEach(placement.chips, id: \.control) { chip in
                    self.chip(chip.control, leading: chip.leading)
                        .frame(width: chip.frame.width)
                        .position(x: chip.frame.midX, y: chip.frame.midY)
                }
            }
            .frame(maxWidth: .infinity, minHeight: placement.height, maxHeight: placement.height,
                   alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
            let row = placement.isStacked
                ? controls
                : rowControls
            if !row.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(placement.isStacked
                        ? "Controls"
                        : "Not on the picture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(row, id: \.self) { control in
                            chip(control, leading: false)
                        }
                    }
                }
            }
        }
        .onChange(of: listening) { previous, current in
            guard current == nil, let previous, previous == origin else {
                return
            }
            origin = nil
            focus = previous
        }
    }

    private var controls: [PlayStationControl] {
        PlayStationControl.allCases.filter {
            source == .gamepadButton || $0 != .gyroHold
        }
    }

    private var placedPoints: [(PlayStationControl, CGPoint)] {
        controls.compactMap { control in
            position(of: control).map { (control, $0) }
        }
    }

    private var rowControls: [PlayStationControl] {
        controls.filter {
            position(of: $0) == nil
        }
    }

    private func position(of control: PlayStationControl) -> CGPoint? {
        guard source == .gamepadButton else {
            return artwork.consolePosition(of: control)
        }
        return artwork.position(of: control, code: binding(control)?.code, family: family, layout: layout)
    }

    private func binding(_ control: PlayStationControl) -> InputBinding? {
        preset.bindings.first {
            $0.source == source && $0.target == control
        }
    }

    private func input(_ control: PlayStationControl) -> ControlsBindingChip.Input {
        if let binding = binding(control) {
            switch binding.source {
            case .gamepadButton:
                return .button(ControllerGlyphs.button(binding.code, family: family, layout: layout))
            case .macKey, .mouseButton:
                return .key(binding.label)
            }
        }
        guard source == .gamepadButton else {
            return .none
        }
        switch control {
        case .leftTrigger:
            return .analog(ControllerGlyphs.leftTrigger(family: family).name)
        case .rightTrigger:
            return .analog(ControllerGlyphs.rightTrigger(family: family).name)
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight:
            return .analog("Left stick")
        case .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight:
            return .analog("Right stick")
        default:
            return .none
        }
    }

    private func chip(_ control: PlayStationControl, leading: Bool) -> some View {
        ControlsBindingChip(
            control: control,
            input: input(control),
            leading: leading,
            listening: listening == control,
            changed: changed.contains(control)
        ) {
            origin = control
            select(control)
        }
        .menuFocused($focus, equals: control)
    }

    private func drawing(_ placement: ControlsBoardPlacement) -> some View {
        ZStack(alignment: .topLeading) {
            if let image = artwork.image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityHidden(true)
            }
            ForEach(placedPoints, id: \.0) { entry in
                Button {
                    select(entry.0)
                } label: {
                    Circle()
                        .fill(listening == entry.0
                            ? Palette.accent.opacity(0.35)
                            : Color.clear)
                            .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(width: hotspotSide, height: hotspotSide)
                .position(x: entry.1.x * placement.artFrame.width, y: entry.1.y * placement.artFrame.height)
                .help(entry.0.label)
                .accessibilityHidden(true)
            }
        }
        .frame(width: placement.artFrame.width, height: placement.artFrame.height)
        .offset(x: placement.artFrame.minX, y: placement.artFrame.minY)
    }

    private var hotspotSide: CGFloat {
        max(30, screenLayout.controlSize)
    }

    private func lines(_ placement: ControlsBoardPlacement) -> some View {
        Canvas { context, _ in
            for chip in placement.chips {
                let start = CGPoint(
                    x: chip.leading
                        ? chip.frame.maxX
                        : chip.frame.minX,
                    y: chip.frame.midY
                )
                let elbow = CGPoint(
                    x: start.x + (chip.leading
                        ? 16
                        : -16),
                    y: start.y
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: elbow)
                path.addLine(to: chip.anchor)
                let active = listening == chip.control
                context.stroke(path, with: .color(active
                                   ? Palette.accent
                                   : Color.primary.opacity(0.35)),
                lineWidth: active
                    ? 2
                    : 1)
                let dot = CGRect(x: chip.anchor.x - 3.5, y: chip.anchor.y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: dot), with: .color(active
                        ? Palette.accent
                        : Color.primary.opacity(0.6)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One console control's chip on the binding board: the control, what drives it, and whether it is
/// listening for a new input or has just changed.
private struct ControlsBindingChip: View {
    /// What drives a control, as the chip shows it.
    enum Input: Equatable {
        /// A key or mouse button, by label.
        case key(String)

        /// A controller button.
        case button(ControllerGlyph)

        /// The controller's own trigger or stick, with nothing bound.
        case analog(String)

        /// Nothing.
        case none
    }

    /// The control.
    let control: PlayStationControl

    /// What drives it.
    let input: Input

    /// Whether the chip sits left of the drawing, which mirrors its contents.
    var leading = false

    /// Whether it is listening for a new input.
    let listening: Bool

    /// Whether it changed in the latest undoable change.
    let changed: Bool

    /// Starts listening for this control.
    let select: () -> Void

    /// Draws the chip.
    var body: some View {
        FocusButton(action: select) {
            HStack(spacing: 8) {
                action
                Spacer(minLength: 6)
                value
            }
            .environment(\.layoutDirection, leading
                ? .rightToLeft
                : .leftToRight)
                .padding(.horizontal, 10)
                .frame(height: ControlsBoardPlacement.chipHeight)
                .background(.background.opacity(0.7), in: .rect(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11).strokeBorder(border, lineWidth: listening || changed
                        ? 2
                        : 1)
                }
                .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(11))
        .help(listening
            ? "Listening for \(control.label)"
            : "Change \(control.label)")
            .accessibilityLabel("\(control.label), \(spoken)")
            .accessibilityHint("Starts listening for a new input")
            .accessibilityAddTraits(listening
                ? .isSelected
                : [])
    }

    private var action: some View {
        HStack(spacing: 6) {
            if let symbol = ControllerGlyphs.action(control).symbol {
                Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(control.label).font(.callout.weight(.medium)).lineLimit(1)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    @ViewBuilder private var value: some View {
        Group {
            if listening {
                Text("Listening").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
            } else {
                switch input {
                case .key(let label):
                    Text(label)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: .rect(cornerRadius: 5))
                case .button(let glyph):
                    ControllerGlyphLabel(glyph: glyph, showsName: glyph.symbol == nil)
                        .font(.callout)
                case .analog(let name):
                    Text(name).font(.caption).foregroundStyle(.secondary)
                case .none:
                    Text("Unbound").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .lineLimit(1)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var border: Color {
        if listening {
            return Palette.accent
        }
        return changed
            ? Palette.accent.opacity(0.55)
            : Color.primary.opacity(0.12)
    }

    private var spoken: String {
        switch input {
        case .key(let label):
            label
        case .button(let glyph):
            glyph.name
        case .analog(let name):
            name
        case .none:
            "unbound"
        }
    }
}

/// Where the binding board draws its controller and each control's chip, and where each chip's line ends.
///
/// Chips sit in a column on the side of the drawing their button is on, ordered top to bottom by where the
/// button is, so the lines from chip to button cross as little as possible. Below
/// ``ControlsBoardPlacement/sideBySideWidth`` there is no room for columns and ``isStacked`` is `true`: the
/// view then shows the drawing above a grid of chips without lines.
struct ControlsBoardPlacement: Equatable {
    /// One chip on the drawing.
    struct Chip: Equatable {
        /// The control the chip binds.
        let control: PlayStationControl

        /// The chip's frame.
        let frame: CGRect

        /// Where the chip's line ends on the drawing.
        let anchor: CGPoint

        /// Whether the chip sits left of the drawing.
        let leading: Bool
    }

    /// The narrowest board that fits chip columns beside the drawing.
    static let sideBySideWidth: CGFloat = 760

    /// A chip's height.
    static let chipHeight: CGFloat = 38

    /// The space between chips in a column.
    static let chipSpacing: CGFloat = 8

    /// The drawing's frame.
    let artFrame: CGRect

    /// The chips beside the drawing; empty when ``isStacked``.
    let chips: [Chip]

    /// The board's height.
    let height: CGFloat

    /// Whether the board is too narrow for chip columns.
    let isStacked: Bool

    /// Places the drawing and the chips of the controls that have a place on it.
    ///
    /// - Parameters:
    ///   - width: The board's width.
    ///   - aspectRatio: The drawing's width divided by its height.
    ///   - points: Each placed control and where it sits, as fractions of the drawing.
    init(width: CGFloat, aspectRatio: CGFloat, points: [(PlayStationControl, CGPoint)]) {
        guard width >= Self.sideBySideWidth else {
            let artWidth = min(width, 460)
            let artHeight = artWidth / aspectRatio
            artFrame = CGRect(x: (width - artWidth) / 2, y: 0, width: artWidth, height: artHeight)
            chips = []
            height = artHeight
            isStacked = true
            return
        }
        isStacked = false
        let artWidth = min(width * 0.44, 540)
        let artHeight = artWidth / aspectRatio
        let chipWidth = min(230, (width - artWidth) / 2 - 44)
        let sides = Dictionary(grouping: points) { $0.1.x < 0.5 }
        let tallest = max(sides[true]?.count ?? 0, sides[false]?.count ?? 0)
        let columnHeight = CGFloat(tallest) * (Self.chipHeight + Self.chipSpacing) - Self.chipSpacing
        height = max(artHeight + 32, columnHeight + 16)
        let art = CGRect(x: (width - artWidth) / 2, y: (height - artHeight) / 2, width: artWidth,
                         height: artHeight)
        artFrame = art
        var placed: [Chip] = []
        for leading in [true, false] {
            let column = (sides[leading] ?? []).sorted { first, second in
                guard first.1.y == second.1.y else {
                    return first.1.y < second.1.y
                }
                return leading == (first.1.x < second.1.x)
            }
            guard !column.isEmpty else {
                continue
            }
            let step = column.count > 1
                ? (height - Self.chipHeight) / CGFloat(column.count - 1)
                : 0
            let top = column.count > 1
                ? 0
                : (height - Self.chipHeight) / 2
            let x = leading
                ? art.minX - 36 - chipWidth
                : art.maxX + 36
            for (index, entry) in column.enumerated() {
                let frame = CGRect(
                    x: x,
                    y: top + CGFloat(index) * step,
                    width: chipWidth,
                    height: Self.chipHeight
                )
                let anchor = CGPoint(
                    x: art.minX + entry.1.x * art.width,
                    y: art.minY + entry.1.y * art.height
                )
                placed.append(Chip(control: entry.0, frame: frame, anchor: anchor, leading: leading))
            }
        }
        chips = placed
    }
}
