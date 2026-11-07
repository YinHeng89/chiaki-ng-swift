import ChiakiModels
import SwiftUI

/// Diagnostics content, either a single compact row of health figures or the detailed card with pipeline
/// stages, event strip, optional full sections and HDR line.
struct StreamDiagnosticsPanel: View {
    /// Health tone used to colour figures.
    typealias Tone = StreamDiagnosticsReport.Tone

    /// Width of each pipeline stage card.
    static let stageWidth: CGFloat = 132
    /// Spacing between stage cards.
    static let stageSpacing: CGFloat = 6
    /// Padding around the detailed panel when it is drawn on a sheet.
    static let panelPadding: CGFloat = 12
    /// Width of the detailed panel, sized to fit five stage cards.
    static let panelWidth = stageWidth * 5 + stageSpacing * 4 + panelPadding * 2
    /// Width of each card of the full statistics.
    static let fullCardWidth: CGFloat = 196

    /// Report whose figures and tones the panel shows.
    let report: StreamDiagnosticsReport
    /// Detail level that selects the compact or detailed layout and whether full sections appear.
    let level: StreamDiagnosticsAppearance.Level
    /// Glass style for separately floating blocks, or `nil` when the panel is drawn on one sheet.
    let floating: StreamDiagnosticsAppearance.Glass?
    /// Controls for changing level, layout and glass, shown in the compact row or the header.
    let controls: StreamDiagnosticsControls
    /// The most cards the pipeline stages and the full sections lay side by side, so a narrow screen can stack
    /// them in fewer columns.
    var columns = 5
    @Environment(\.screenLayout) private var layout

    var body: some View {
        if level == .compact {
            compactPanel
        } else {
            detailedPanel
        }
    }

    private var compactPanel: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(report.compactTone.color)
                .frame(width: 8, height: 8)
                .accessibilityLabel(toneDescription(report.compactTone))
            if report.stats.rttPresent {
                compactValue(report.rttValue, unit: nil, tone: .neutral)
            }
            compactValue(
                .verbatim(report.percent(report.packetLossPercent)),
                unit: .playbackDiagnosticsCompactLoss,
                tone: report.lossTone(report.packetLossPercent)
            )
            compactValue(
                .verbatim(report.networkStage.headline),
                unit: .playbackDiagnosticsCompactMbps,
                tone: .neutral
            )
            if let alert = report.compactAlert {
                Text(alert.value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(alert.tone.headlineColor)
            }
            controls
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .fixedSize()
    }

    private var detailedPanel: some View {
        VStack(alignment: .leading, spacing: stackSpacing) {
            header
                .modifier(StreamDiagnosticsBlock(
                    floating: floating,
                    tone: report.overallTone,
                    padding: blockPadding
                ))
            LazyVGrid(
                columns: columns(stageColumns, width: stageCardWidth),
                alignment: .leading,
                spacing: Self.stageSpacing
            ) {
                ForEach(report.stages) { stage in
                    StreamDiagnosticsStageCard(stage: stage, floating: floating, width: stageCardWidth)
                }
            }
            eventStrip
                .modifier(StreamDiagnosticsBlock(floating: floating, tone: .neutral, padding: blockPadding))
            if level == .full {
                fullSections
            }
            hdrLine
                .modifier(StreamDiagnosticsBlock(
                    floating: floating,
                    tone: report.hdrTone,
                    padding: blockPadding
                ))
        }
        .padding(outerPadding)
        .frame(width: contentWidth + outerPadding * 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var contentWidth: CGFloat {
        let stageRow = Self.rowWidth(cards: stageColumns, width: Self.stageWidth)
        guard level == .full else {
            return stageRow
        }
        return max(stageRow, Self.rowWidth(cards: sectionColumns, width: Self.fullCardWidth))
    }

    private static func rowWidth(cards: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(cards) + stageSpacing * CGFloat(cards - 1)
    }

    private var stageColumns: Int {
        max(1, min(report.stages.count, columns))
    }

    private var stageCardWidth: CGFloat {
        cardWidth(columns: stageColumns)
    }

    private var sectionColumns: Int {
        max(1, min(report.fullSections.count, columns))
    }

    private func cardWidth(columns: Int) -> CGFloat {
        let count = CGFloat(columns)
        return (contentWidth - Self.stageSpacing * (count - 1)) / count
    }

    private func columns(_ count: Int, width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.fixed(width), spacing: Self.stageSpacing, alignment: .top), count: count)
    }

    private var stackSpacing: CGFloat {
        if floating == nil {
            return 8
        }
        return Self.stageSpacing
    }

    private var outerPadding: CGFloat {
        if floating == nil {
            return Self.panelPadding
        }
        return 0
    }

    private var blockPadding: CGFloat {
        if floating == nil {
            return 0
        }
        return 10
    }

    private var hdrLine: some View {
        HStack(spacing: 12) {
            Label(report.hdrLongLabel, systemImage: hdrSystemImage)
                .foregroundStyle(report.hdrTone.color)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(report.gamutDescription)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(.playbackDiagnosticsTitle)
                    .font(.headline)
                Text(report.uptime)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                controls
                    .fixedSize()
            }
            HStack(spacing: 6) {
                ForEach(Array(report.headerChips.enumerated()), id: \.offset) { _, chip in
                    StreamDiagnosticsChip(chip: chip)
                }
            }
        }
    }

    private var eventStrip: some View {
        HStack(spacing: 10) {
            Text(.playbackDiagnosticsHistoryWindow)
                .font(.caption2)
                .foregroundStyle(.secondary)
            StreamDiagnosticsEventStrip(history: report.history)
                .frame(height: 10)
            let present = StreamDiagnosticsHistory.Event.allCases.filter {
                !report.history.marks($0).isEmpty
            }
            ForEach(present, id: \.self) { event in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(event.color)
                        .frame(width: 8, height: 8)
                    Text(event.title)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Text(report.audioSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(report.audioUnderrunsSummary.value)
                .font(.caption)
                .foregroundStyle(report.audioUnderrunsSummary.tone.headlineColor)
                .lineLimit(1)
        }
    }

    private var fullSections: some View {
        LazyVGrid(
            columns: columns(sectionColumns, width: cardWidth(columns: sectionColumns)),
            alignment: .leading,
            spacing: Self.stageSpacing
        ) {
            ForEach(report.fullSections) { section in
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        StreamDiagnosticsRowView(row: row)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(StreamDiagnosticsBlock(floating: floating, tone: .neutral, padding: 0, fill: 0.05))
            }
        }
    }

    private func compactValue(
        _ value: LocalizedStringResource,
        unit: LocalizedStringResource?,
        tone: Tone
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(tone.headlineColor)
            if let unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toneDescription(_ tone: Tone) -> LocalizedStringResource {
        switch tone {
        case .neutral, .good:
            .playbackDiagnosticsStreamHealthy
        case .warning:
            .playbackDiagnosticsStreamDegraded
        case .bad:
            .playbackDiagnosticsStreamStruggling
        }
    }

    private var hdrSystemImage: String {
        if report.stats.perceptualQuantizer {
            return "sun.max.fill"
        }
        return "sun.max"
    }
}

/// Capsule controls for picking the diagnostics detail level, toggling the layout and choosing the glass
/// style.
struct StreamDiagnosticsControls: View {
    /// Appearance whose current selections the controls show.
    let appearance: StreamDiagnosticsAppearance
    /// Called when a detail level is picked.
    let selectLevel: (StreamDiagnosticsAppearance.Level) -> Void
    /// Called when a glass style is picked.
    let selectGlass: (StreamDiagnosticsAppearance.Glass) -> Void
    /// Called when the layout is toggled or picked.
    let selectLayout: (StreamDiagnosticsAppearance.Layout) -> Void
    @Environment(\.screenLayout) private var layout

    private var iconSide: CGSize {
        CGSize(width: max(26, layout.controlSize), height: max(22, layout.controlSize))
    }

    var body: some View {
        HStack(spacing: 6) {
            levelSwitcher
            if appearance.level != .compact {
                layoutToggle
            }
            glassPicker
        }
    }

    private var layoutToggle: some View {
        Button {
            selectLayout(
                appearance.layout == .sheet
                    ? .floating
                    : .sheet
            )
        } label: {
            Image(systemName: layoutSymbol)
                .font(.caption.weight(.semibold))
                .frame(width: iconSide.width, height: iconSide.height)
                .background(.white.opacity(0.1), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(.playbackDiagnosticsLayoutHelp(layout: String(localized: appearance.layout.title)))
        .accessibilityLabel(.playbackDiagnosticsLayoutAccessibility)
        .accessibilityValue(appearance.layout.title)
    }

    private var layoutSymbol: String {
        switch appearance.layout {
        case .sheet:
            "rectangle"
        case .floating:
            "rectangle.split.3x1"
        }
    }

    private var levelSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(StreamDiagnosticsAppearance.Level.allCases.filter(\.visible), id: \.self) { level in
                Button {
                    selectLevel(level)
                } label: {
                    Text(level.title)
                        .font(.caption.weight(
                            appearance.level == level
                                ? .semibold
                                : .regular
                        ))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .frame(minHeight: layout.controlSize)
                        .background(levelBackground(level), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityAddTraits(
                    appearance.level == level
                        ? .isSelected
                        : []
                )
            }
        }
        .padding(2)
        .background(.white.opacity(0.1), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(.playbackDiagnosticsDetailAccessibility)
    }

    private var glassPicker: some View {
        Menu {
            Picker(.playbackDiagnosticsGlassPicker, selection: Binding(get: {
                appearance.glass
            }, set: { glass in
                selectGlass(glass)
            })) {
                ForEach(StreamDiagnosticsAppearance.Glass.allCases, id: \.self) { glass in
                    Text(glass.title).tag(glass)
                }
            }
            .pickerStyle(.inline)
            Picker(.playbackDiagnosticsLayoutPicker, selection: Binding(get: {
                appearance.layout
            }, set: { layout in
                selectLayout(layout)
            })) {
                ForEach(StreamDiagnosticsAppearance.Layout.allCases, id: \.self) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(appearance.glass.title, systemImage: "drop")
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .frame(width: iconSide.width, height: iconSide.height)
                .background(.white.opacity(0.1), in: .capsule)
                .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help(.playbackDiagnosticsGlassHelp(glass: String(localized: appearance.glass.title)))
        .accessibilityLabel(.playbackDiagnosticsGlassAccessibility)
        .accessibilityValue(appearance.glass.title)
    }

    private func levelBackground(_ level: StreamDiagnosticsAppearance.Level) -> Color {
        if appearance.level == level {
            return .white.opacity(0.24)
        }
        return .clear
    }
}

/// Pads a diagnostics block and draws it either as its own glass surface or as a faint fill on the shared
/// sheet.
struct StreamDiagnosticsBlock: ViewModifier {
    /// Glass style for a floating block, or `nil` to draw it on the sheet.
    let floating: StreamDiagnosticsAppearance.Glass?
    /// Health tone that tints the floating surface.
    let tone: StreamDiagnosticsReport.Tone
    /// Padding inside the block.
    let padding: CGFloat
    /// Opacity of the white fill used when the block is on the sheet.
    var fill = 0.0

    /// Wraps the content in the floating surface or the sheet fill.
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        if let floating {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(StreamDiagnosticsSurface(glass: floating, tone: tone, shape: shape))
        } else {
            content
                .padding(padding)
                .background(.white.opacity(fill), in: shape)
        }
    }
}

/// Card for one pipeline stage showing its headline value, sparkline and detail rows, outlined in red when
/// the stage is bad.
struct StreamDiagnosticsStageCard: View {
    /// Stage whose figures the card shows.
    let stage: StreamDiagnosticsReport.Stage
    /// Glass style when the card floats on its own, or `nil` on the sheet.
    let floating: StreamDiagnosticsAppearance.Glass?
    /// The card's width.
    var width = StreamDiagnosticsPanel.stageWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stage.kind.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    stage.tone == .bad
                        ? stage.tone.color
                        : .secondary
                )
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(stage.headline)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(stage.tone.headlineColor)
                Text(stage.unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            StreamDiagnosticsSparkline(values: stage.series, color: stage.tone.sparklineColor)
                .frame(height: 14)
            ForEach(Array(stage.rows.enumerated()), id: \.offset) { _, row in
                StreamDiagnosticsRowView(row: row)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: width, alignment: .leading)
        .modifier(StreamDiagnosticsBlock(floating: floating, tone: stage.tone, padding: 0, fill: 0.07))
        .frame(width: width)
        .overlay {
            if stage.tone == .bad {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(StreamDiagnosticsReport.Tone.bad.color, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One label and value row coloured by the row's health tone.
struct StreamDiagnosticsRowView: View {
    /// Row to show.
    let row: StreamDiagnosticsReport.Row

    var body: some View {
        HStack(spacing: 6) {
            Text(row.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(row.value)
                .monospacedDigit()
                .foregroundStyle(row.tone.headlineColor)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

/// One chip in the diagnostics header: its segments in a capsule, divided by thin rules and coloured by the
/// chip's health tone.
private struct StreamDiagnosticsChip: View {
    /// The chip to show.
    let chip: StreamDiagnosticsReport.Chip

    /// The capsule with the chip's segments.
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(chip.segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 1, height: 10)
                }
                Text(segment)
                    .monospacedDigit()
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(chip.tone.headlineColor)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }
}
