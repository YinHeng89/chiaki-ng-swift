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
    static let markerHint = LocalizedStringResource.playbackDiagnosticsMarkerHint

    /// The light levels the renderer measured.
    var light: StreamLightLevels {
        stats.light
    }

    /// The display's EDR headroom, with the headroom it could reach when macOS holds some back.
    var headroomValue: LocalizedStringResource {
        let current = stats.displayMaximumEDR
        let potential = stats.displayPotentialEDR
        guard potential > current + Self.headroomTolerance else {
            return .verbatim("\(oneDecimal(current))×")
        }
        return .playbackDiagnosticsHeadroomOf(current: oneDecimal(current), potential: oneDecimal(potential))
    }

    /// Why a stream that requested HDR arrived in SDR.
    var requestedHDRSentSDR: LocalizedStringResource {
        let route = Route(rawValue: stats.route) ?? .unknown
        let height = stats.sourceHeight
        if route == .psCloud, height > 0, height <= CloudPictureSettings.maximumSDRHeight {
            return .playbackDiagnosticsHdrCloudSentSdr
        }
        return .playbackDiagnosticsHdrConsoleSentSdr
    }

    /// Whether any frame has been measured.
    var lightReadings: Bool {
        light.measurements > 0
    }

    /// The legend note explaining why an SDR stream shows nothing above SDR white, or `nil` for HDR.
    var sdrLegendNote: LocalizedStringResource? {
        guard !stats.perceptualQuantizer else {
            return nil
        }
        if stats.requestedHDR {
            return .playbackDiagnosticsSdrArrivedNote
        }
        return .playbackDiagnosticsSdrStreamNote
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
    var sdrBrightnessLabel: LocalizedStringResource {
        let route = Route(rawValue: stats.route) ?? .unknown
        let console = RouteConsole(rawValue: stats.routeConsole) ?? .unknown
        if route == .local || route == .internet, console == .ps5 {
            return .playbackDiagnosticsSdrBrightnessConsole
        }
        return .playbackDiagnosticsSdrBrightnessGame
    }

    /// The HDR light section with peak, average, MaxCLL, MaxFALL and the share above SDR white.
    var lightSection: Section {
        Section(title: .playbackDiagnosticsSectionLight, rows: [
            Row(.playbackDiagnosticsLegendPeak, nits(light.peakNits)),
            Row(.playbackDiagnosticsRowAverage, nits(light.averageNits)),
            Row(.playbackDiagnosticsLegendMaxCll, nits(light.maxCLL)),
            Row(.playbackDiagnosticsRowMaxFall, nits(light.maxFALL)),
            Row(.playbackDiagnosticsLegendAboveSdrWhite, .verbatim(aboveWhite), aboveWhiteTone)
        ])
    }

    /// The title of the marker reading.
    var markerTitle: LocalizedStringResource {
        light.markerFollowsPointer
            ? .playbackDiagnosticsMarkerAtPointer
            : .playbackDiagnosticsMarkerAtMarker
    }

    /// Whether the brightness marker shows.
    var markerVisible: Bool {
        light.markerVisible
    }

    /// The hint for moving the marker, or `nil` while it shows.
    var markerHint: LocalizedStringResource? {
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
    func nits(_ value: Double) -> LocalizedStringResource {
        .playbackDiagnosticsNits(value: String(Int(value.rounded())))
    }
}
