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
        let bandwidth = available > 0
            ? "\(oneDecimal(used)) of \(oneDecimal(available)) Mbps"
            : "\(oneDecimal(used)) Mbps"
        let corrupt = UInt64(max(0, server.corruptFrames))
        return Section(title: "Cloud server", rows: [
            Row("Bandwidth", bandwidth),
            Row("Upload", "\(oneDecimal(Double(server.usedUpKbps) / 1000)) Mbps"),
            Row("Round trip", millisecondsValue(Double(server.roundTripMilliseconds))),
            Row(
                "Loss",
                "\(percent(server.lossPercent)) down, "
                    + "\(percent(server.upstreamLossPercent)) up"
            ),
            Row("Picture sent", resolution(server.width, server.height)),
            Row("Audio channels", String(server.audioChannels)),
            Row("Corrupt frames", String(corrupt), countTone(corrupt))
        ])
    }
}
