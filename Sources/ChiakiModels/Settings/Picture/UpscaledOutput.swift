/// The resolution stream video is upscaled to before it is shown.
public enum UpscaledOutput: String, Codable, CaseIterable, Sendable {
    /// Video is shown at the stream's own resolution.
    case disabled

    /// 1080 lines.
    case fullHD

    /// 1440 lines.
    case quadHD

    /// 2160 lines.
    case fourK

    /// The outputs that make sense for a stream height, ``disabled`` first.
    ///
    /// - Parameter height: The stream's vertical resolution.
    /// - Returns: The outputs offered for that height.
    public static func available(for height: Int) -> [Self] {
        switch height {
        case 720:
            return [.disabled, .fullHD]
        case 1080:
            return [.disabled, .quadHD, .fourK]
        default:
            return [.disabled]
        }
    }

    /// This output when it suits `height`, otherwise the first real upscale offered for it.
    ///
    /// - Parameter height: The stream's vertical resolution.
    /// - Returns: An output from ``available(for:)``.
    public func compatible(with height: Int) -> Self {
        let options = Self.available(for: height)
        return options.contains(self)
            ? self
            : (options.dropFirst().first ?? .disabled)
    }

    /// The vertical resolution shown for a stream of height `source`.
    ///
    /// - Parameter source: The stream's vertical resolution.
    /// - Returns: The output height, or `source` when upscaling is off.
    public func height(source: Int) -> Int {
        switch compatible(with: source) {
        case .disabled:
            return source
        case .fullHD:
            return 1080
        case .quadHD:
            return 1440
        case .fourK:
            return 2160
        }
    }

    /// The label shown for the output.
    public var title: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .fullHD:
            return "1080p"
        case .quadHD:
            return "1440p"
        case .fourK:
            return "4K (2160p)"
        }
    }
}

/// The method used to scale stream video up to the output resolution.
public enum VideoUpscaler: String, Codable, CaseIterable, Sendable {
    /// Apple's MetalFX spatial scaler.
    case metalFX

    /// The app's own shader-based spatial scaler.
    case advancedSpatial
}
