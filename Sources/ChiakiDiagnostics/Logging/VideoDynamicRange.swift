/// The dynamic range a stream asked for, and why HDR was left off when it was.
public enum VideoDynamicRange: Equatable, Sendable {
    /// The console is a PS4, which cannot stream HDR.
    case unavailableOnPS4

    /// HEVC HDR was requested.
    case hdrRequested

    /// HDR was off because of the setting, the codec or the screen.
    case standard

    /// Chooses the dynamic range a request ends up with.
    ///
    /// - Parameters:
    ///   - ps5: Whether the console is a PS5.
    ///   - hdrCodec: Whether the chosen codec is HEVC HDR.
    public init(ps5: Bool, hdrCodec: Bool) {
        if !ps5 {
            self = .unavailableOnPS4
        } else if hdrCodec {
            self = .hdrRequested
        } else {
            self = .standard
        }
    }

    /// The text written to the log.
    public var summary: String {
        switch self {
        case .unavailableOnPS4:
            "HDR unavailable on PS4"
        case .hdrRequested:
            "HEVC HDR requested"
        case .standard:
            "HDR off (setting, codec or screen)"
        }
    }
}
