import ChiakiModels
import PlatformUI
import SwiftUI
import DesignSystem

/// Draggable diagnostics panel positioned at the top leading corner of the stream, plus the legend for an
/// active video analysis mode.
struct StreamDiagnosticsOverlay: View {
    /// Detail level of the diagnostics panel.
    typealias Level = StreamDiagnosticsAppearance.Level
    /// Glass style of the diagnostics surfaces.
    typealias Glass = StreamDiagnosticsAppearance.Glass
    /// How many cards the detailed panel lays side by side when the room allows.
    static let wideColumns = 5
    /// How many cards the detailed panel lays side by side when five do not fit.
    static let mediumColumns = 3
    /// How many cards the detailed panel lays side by side on the narrowest screens.
    static let narrowColumns = 1
    /// The margin between the overlay's surfaces and the screen edge, before the screen's own side inset.
    static let edgeMargin: CGFloat = 28
    /// The height of the stream's top controls row below the top chrome inset, which the panel starts under.
    static let topControlsRow: CGFloat = 56

    /// Report the panel shows.
    let report: StreamDiagnosticsReport
    /// Detail level, glass and layout the overlay is drawn with.
    let appearance: StreamDiagnosticsAppearance
    /// Active video analysis mode, which shows its legend when not off.
    let analysisMode: StreamVideoAnalysisMode
    /// Called when a detail level is picked.
    var selectLevel: (Level) -> Void = { _ in }
    /// Called when a glass style is picked.
    var selectGlass: (Glass) -> Void = { _ in }
    /// Called when a layout is picked.
    var selectLayout: (StreamDiagnosticsAppearance.Layout) -> Void = { _ in }
    @State private var dragOffset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    @Environment(\.screenLayout) private var layout
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if appearance.level.visible {
                fittedPanel
                    .environment(\.colorScheme, .dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Self.edgeMargin + layout.sideInset)
                    .padding(.top, layout.topChromeInset + Self.topControlsRow)
                    .padding(.bottom, Self.edgeMargin)
                    .offset(
                        x: settledOffset.width + dragOffset.width,
                        y: settledOffset.height + dragOffset.height
                    )
            }
            if analysisMode != .off {
                StreamVideoAnalysisLegend(mode: analysisMode, report: report)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, Self.edgeMargin + layout.sideInset)
                    .padding(.bottom, Self.edgeMargin)
            }
        }
        .allowsHitTesting(appearance.level.visible)
    }

    private var fittedPanel: some View {
        ViewThatFits(in: .vertical) {
            columnFittedPanel
                .contentShape(.rect)
                .highPriorityGesture(dragGesture)
            ScrollView(.vertical) {
                columnFittedPanel
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var columnFittedPanel: some View {
        ViewThatFits(in: .horizontal) {
            panel(columns: Self.wideColumns)
            panel(columns: Self.mediumColumns)
            panel(columns: Self.narrowColumns)
        }
    }

    /// Glass style to draw with, forced to solid when Reduce Transparency is on.
    var glass: Glass {
        if reduceTransparency {
            return .solid
        }
        return appearance.glass
    }

    @ViewBuilder private func panel(columns: Int) -> some View {
        let floating = appearance.layout == .floating && appearance.level != .compact
        let content = StreamDiagnosticsPanel(
            report: report,
            level: appearance.level,
            floating: floating
                ? glass
                : nil,
            controls: StreamDiagnosticsControls(
                appearance: appearance,
                selectLevel: selectLevel,
                selectGlass: selectGlass,
                selectLayout: selectLayout
            ),
            columns: columns
        )
        switch appearance.level {
        case .off:
            EmptyView()
        case .compact:
            content
                .modifier(StreamDiagnosticsSurface(glass: glass, tone: report.overallTone, shape: .capsule))
        case .standard, .full:
            if floating {
                GlassEffectContainer(spacing: 8) {
                    content
                }
            } else {
                content
                    .modifier(StreamDiagnosticsSurface(
                        glass: glass,
                        tone: report.overallTone,
                        shape: .rect(cornerRadius: 20)
                    ))
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged {
                dragOffset = $0.translation
            }
            .onEnded {
                settledOffset.width += $0.translation.width
                settledOffset.height += $0.translation.height
                dragOffset = .zero
            }
    }
}

/// Legend for the active video analysis mode, with the HDR state and colour description of the stream.
struct StreamVideoAnalysisLegend: View {
    /// Analysis mode the legend explains.
    let mode: StreamVideoAnalysisMode
    /// Report supplying the HDR label and colour description.
    let report: StreamDiagnosticsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                Text(report.hdrLongLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(report.hdrTone.color)
            }
            if mode == .hdrHeatmap {
                LinearGradient(
                    colors: [.blue, .cyan, .green, .yellow, .red, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 12)
                .clipShape(.capsule)
                HStack {
                    legendValue(Text(verbatim: "0"))
                    Spacer()
                    legendValue(Text(verbatim: "100"))
                    Spacer()
                    legendValue(Text(verbatim: "203"))
                    Spacer()
                    legendValue(Text(verbatim: "400"))
                    Spacer()
                    legendValue(Text(.playbackDiagnosticsLegendNitsMaximum))
                }
                if report.lightReadings {
                    HStack(alignment: .top, spacing: 18) {
                        if report.markerVisible {
                            legendStat(report.markerTitle, value: report.nits(report.light.markerNits))
                        }
                        legendStat(.playbackDiagnosticsLegendPeak, value: report.nits(report.light.peakNits))
                        if report.lightMeasured {
                            legendStat(
                                .playbackDiagnosticsLegendMaxCll,
                                value: report.nits(report.light.maxCLL)
                            )
                            legendStat(
                                .playbackDiagnosticsLegendAboveSdrWhite,
                                value: .verbatim(report.aboveWhite),
                                tone: report.aboveWhiteTone
                            )
                        }
                    }
                    if let note = report.sdrLegendNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let hint = report.markerHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 18) {
                    legendSwatch(.cyan, label: .playbackDiagnosticsLegendAboveReferenceWhite)
                    legendSwatch(.purple, label: .playbackDiagnosticsLegendNearPeak)
                }
            }
            Text(report.colourDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: 430)
        .glassPanel(.medium)
    }

    private func legendStat(
        _ label: LocalizedStringResource,
        value: LocalizedStringResource,
        tone: StreamDiagnosticsReport.Tone = .neutral
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(tone.color)
        }
    }

    private func legendValue(_ value: Text) -> some View {
        value
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func legendSwatch(_ color: Color, label: LocalizedStringResource) -> some View {
        Label {
            Text(label)
        } icon: {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 18, height: 12)
        }
        .font(.caption)
    }
}

/// Draws content on the diagnostics surface for a glass style, tinting it by health tone when that style is
/// chosen.
struct StreamDiagnosticsSurface<S: Shape>: ViewModifier {
    /// Glass style of the surface.
    let glass: StreamDiagnosticsAppearance.Glass
    /// Health tone used by the health-tint style.
    let tone: StreamDiagnosticsReport.Tone
    /// Shape of the surface.
    let shape: S

    /// Applies the glass effect or solid background for the glass style.
    func body(content: Content) -> some View {
        switch glass {
        case .regular:
            content
                .glassEffect(AppGlass.panel, in: shape)
        case .clear:
            content
                .glassEffect(.clear, in: shape)
        case .clearDimmed:
            content
                .background(.black.opacity(0.32), in: shape)
                .glassEffect(.clear, in: shape)
        case .healthTint:
            content
                .glassEffect(.regular.tint(tint), in: shape)
        case .solid:
            content
                .background(Color(white: 0.1), in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    private var tint: Color {
        switch tone {
        case .neutral, .good:
            .black.opacity(0.2)
        case .warning:
            .orange.opacity(0.26)
        case .bad:
            .red.opacity(0.3)
        }
    }
}

/// Line chart of recent values, right-aligned within the history window and scaled to their range.
struct StreamDiagnosticsSparkline: View {
    /// Values to plot, oldest first.
    let values: [Double]
    /// Stroke colour of the line.
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else {
                return
            }
            let low = values.min() ?? 0
            let high = values.max() ?? 0
            let span = max(high - low, max(abs(high) * 0.1, 0.001))
            let step = size.width / CGFloat(StreamDiagnosticsHistory.capacity - 1)
            let start = CGFloat(StreamDiagnosticsHistory.capacity - values.count) * step
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: start + CGFloat(index) * step,
                    y: size.height - 1 - CGFloat((value - low) / span) * (size.height - 2)
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(color), lineWidth: 1.3)
        }
        .accessibilityHidden(true)
    }
}

/// Timeline of the diagnostics history window with coloured marks where each event occurred.
struct StreamDiagnosticsEventStrip: View {
    /// History whose event marks are drawn.
    let history: StreamDiagnosticsHistory

    var body: some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(StreamDiagnosticsHistory.capacity)
            context.fill(
                Path(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)),
                with: .color(.white.opacity(0.18))
            )
            for event in StreamDiagnosticsHistory.Event.allCases {
                for index in history.marks(event) {
                    let rect = CGRect(
                        x: CGFloat(index) * slot,
                        y: 0,
                        width: max(slot, 2),
                        height: size.height
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(event.color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Colours for drawing figures in each health tone.
extension StreamDiagnosticsReport.Tone {
    /// Indicator colour for the tone, used for dots, icons and outlines.
    var color: Color {
        switch self {
        case .neutral:
            .white
        case .good:
            .green
        case .warning:
            .yellow
        case .bad:
            .red
        }
    }

    /// Softer colour for headline values in the tone, using the primary style when neutral.
    var headlineColor: Color {
        switch self {
        case .neutral:
            .primary
        case .good:
            Color(red: 0.49, green: 0.88, blue: 0.75)
        case .warning:
            Color(red: 0.97, green: 0.73, blue: 0.33)
        case .bad:
            Color(red: 1, green: 0.66, blue: 0.66)
        }
    }

    /// Sparkline colour for the tone, a pale blue when neutral.
    var sparklineColor: Color {
        switch self {
        case .neutral:
            Color(red: 0.61, green: 0.78, blue: 0.94)
        case .good, .warning, .bad:
            headlineColor
        }
    }
}

/// Legend titles and colours for diagnostics history events.
extension StreamDiagnosticsHistory.Event {
    /// Short legend title for the event.
    var title: LocalizedStringResource {
        switch self {
        case .networkLoss:
            .playbackDiagnosticsEventFramesLost
        case .audioUnderrun:
            .playbackDiagnosticsEventAudioUnderrun
        case .renderOverBudget:
            .playbackDiagnosticsEventRenderOverBudget
        case .decodeError:
            .playbackDiagnosticsEventDecodeError
        }
    }

    /// Colour of the event's marks in the event strip and legend.
    var color: Color {
        switch self {
        case .networkLoss:
            Color(red: 0.61, green: 0.78, blue: 0.94)
        case .audioUnderrun:
            Color(red: 0.97, green: 0.73, blue: 0.33)
        case .renderOverBudget:
            Color(red: 0.89, green: 0.29, blue: 0.29)
        case .decodeError:
            Color(red: 0.69, green: 0.55, blue: 0.95)
        }
    }
}
