import ChiakiModels
import Foundation

extension StreamDiagnosticsReport {
    /// Whether a PS5 cloud server reports measurements.
    var serverMeasured: Bool {
        stats.server != nil
    }

    /// The cloud server section with bandwidth, upload, round trip, loss, picture, audio and corrupt frames.
    var serverSection: Section {
        let server = stats.server ?? CloudServerStatistics()
        let used = Double(server.usedDownKbps) / 1000
        let available = Double(server.availableDownKbps) / 1000
        let bandwidth: LocalizedStringResource = available > 0
            ? .playbackDiagnosticsMegabitsOf(value: oneDecimal(used), total: oneDecimal(available))
            : .playbackDiagnosticsMegabits(value: oneDecimal(used))
        let corrupt = UInt64(max(0, server.corruptFrames))
        return Section(title: .playbackDiagnosticsSectionServer, rows: [
            Row(.playbackDiagnosticsRowServerBandwidth, bandwidth),
            Row(
                .playbackDiagnosticsRowUpload,
                .playbackDiagnosticsMegabits(value: oneDecimal(Double(server.usedUpKbps) / 1000))
            ),
            Row(.playbackDiagnosticsRowRoundTrip, millisecondsValue(Double(server.roundTripMilliseconds))),
            Row(
                .playbackDiagnosticsRowLoss,
                .playbackDiagnosticsServerLoss(
                    down: percent(server.lossPercent),
                    up: percent(server.upstreamLossPercent)
                )
            ),
            Row(.playbackDiagnosticsRowPictureSent, resolution(server.width, server.height)),
            Row(.playbackDiagnosticsRowAudioChannels, .verbatim(String(server.audioChannels))),
            Row(.playbackDiagnosticsRowCorruptFrames, .verbatim(String(corrupt)), countTone(corrupt))
        ])
    }
}
