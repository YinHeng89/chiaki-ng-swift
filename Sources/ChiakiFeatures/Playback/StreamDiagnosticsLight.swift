import ChiakiModels
import Foundation

extension StreamDiagnosticsReport {
    /// How far the potential EDR headroom must exceed the current one before both are shown.
    static let headroomTolerance = 0.05
    /// How long light must be measured before an HDR stream can be judged to carry SDR brightness.
    static let sdrBrightnessSeconds = 20.0
    /// The share of a frame above SDR white below which an HDR stream reads as SDR brightness, in percent.
    static let sdrBrightnessAbovePercent = 0.05
    /// The share of a frame near SDR white above which an HDR stream reads as SDR brightness, in percent.
    static let sdrBrightnessNearWhitePercent = 1.0
    /// The hint shown while the brightness marker is hidden.
    static let markerHint = "Point at the picture, or choose Measure brightness in the stream menu, "
        + "to move the marker"

    /// The light levels the renderer measured.
    var light: StreamLightLevels {
        stats.light
    }

    /// The display's EDR headroom, with the headroom it could reach when macOS holds some back.
    var headroomValue: String {
        let current = stats.displayMaximumEDR
        let potential = stats.displayPotentialEDR
        guard potential > current + Self.headroomTolerance else {
            return "\(oneDecimal(current))×"
        }
        return "\(oneDecimal(current))× of \(oneDecimal(potential))×"
    }

    /// Why a stream that requested HDR arrived in SDR.
    var requestedHDRSentSDR: String {
        let route = Route(rawValue: stats.route) ?? .unknown
        let height = stats.sourceHeight
        if route == .psCloud, height > 0, height <= CloudPictureSettings.maximumSDRHeight {
            return "SDR transfer detected; PS5 cloud sends HDR only at 1440p and 4K"
        }
        return "SDR transfer detected; check console HDR"
    }

    /// Whether any frame has been measured.
    var lightReadings: Bool {
        light.measurements > 0
    }

    /// The legend note explaining why an SDR stream shows nothing above SDR white, or `nil` for HDR.
    var sdrLegendNote: String? {
        guard !stats.perceptualQuantizer else {
            return nil
        }
        if stats.requestedHDR {
            return "This stream arrived in SDR, so nothing goes above SDR white."
        }
        return "This stream is SDR, so nothing goes above SDR white. Choose HEVC HDR in the Stream panel "
            + "for an HDR stream."
    }

    /// Whether an HDR stream has measured light.
    var lightMeasured: Bool {
        stats.perceptualQuantizer && light.measurements > 0
    }

    /// Whether an HDR stream has long carried only SDR brightness.
    var sendsSDRBrightness: Bool {
        lightMeasured
            && light.seconds >= Self.sdrBrightnessSeconds
            && light.sessionAbovePercent < Self.sdrBrightnessAbovePercent
            && light.sessionNearWhitePercent >= Self.sdrBrightnessNearWhitePercent
    }

    /// Why an HDR stream carries only SDR brightness.
    var sdrBrightnessLabel: String {
        let route = Route(rawValue: stats.route) ?? .unknown
        let console = RouteConsole(rawValue: stats.routeConsole) ?? .unknown
        if route == .local || route == .internet, console == .ps5 {
            return "PQ input, but bright areas stop at SDR white; the PS5's TV may be off or in SDR, "
                + "or the game may not use HDR"
        }
        return "PQ input, but bright areas stop at SDR white; the game may not use HDR"
    }

    /// The HDR light section with peak, average, MaxCLL, MaxFALL and the share above SDR white.
    var lightSection: Section {
        Section(title: "HDR light", rows: [
            Row("Peak", nits(light.peakNits)),
            Row("Average", nits(light.averageNits)),
            Row("MaxCLL", nits(light.maxCLL)),
            Row("MaxFALL", nits(light.maxFALL)),
            Row("Above SDR white", aboveWhite, aboveWhiteTone)
        ])
    }

    /// The title of the marker reading.
    var markerTitle: String {
        light.markerFollowsPointer
            ? "At the pointer"
            : "At the marker"
    }

    /// Whether the brightness marker shows.
    var markerVisible: Bool {
        light.markerVisible
    }

    /// The hint for moving the marker, or `nil` while it shows.
    var markerHint: String? {
        markerVisible
            ? nil
            : Self.markerHint
    }

    /// The share of the last frame above SDR white.
    var aboveWhite: String {
        percent(light.abovePercent)
    }

    /// The tone of the share above SDR white, a warning when the stream carries only SDR brightness.
    var aboveWhiteTone: Tone {
        sendsSDRBrightness
            ? .warning
            : .neutral
    }

    /// Formats a brightness.
    ///
    /// - Parameter value: The brightness in nits.
    /// - Returns: The rounded brightness with its unit.
    func nits(_ value: Double) -> String {
        "\(Int(value.rounded())) nits"
    }
}
