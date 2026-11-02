import Foundation

/// Colour corrections applied to stream video, each clamped to its range and rounded to ``step``.
public struct PictureAdjustments: Codable, Equatable, Sendable {
    /// The allowed brightness offset.
    public static let brightnessRange = -0.25...0.25

    /// The allowed contrast factor.
    public static let contrastRange = 0.5...1.5

    /// The allowed saturation factor.
    public static let saturationRange = 0.0...2.0

    /// The allowed gamma.
    public static let gammaRange = 0.5...2.0

    /// The increment every value is rounded to.
    public static let step = 0.05

    /// The brightness offset; 0 is unchanged.
    public var brightness: Double

    /// The contrast factor; 1 is unchanged.
    public var contrast: Double

    /// The saturation factor; 1 is unchanged.
    public var saturation: Double

    /// The gamma; 1 is unchanged.
    public var gamma: Double

    /// Creates adjustments, clamping and rounding every value.
    ///
    /// - Parameters:
    ///   - brightness: The brightness offset.
    ///   - contrast: The contrast factor.
    ///   - saturation: The saturation factor.
    ///   - gamma: The gamma.
    public init(brightness: Double = 0, contrast: Double = 1, saturation: Double = 1, gamma: Double = 1) {
        self.brightness = Self.clamp(brightness, to: Self.brightnessRange)
        self.contrast = Self.clamp(contrast, to: Self.contrastRange)
        self.saturation = Self.clamp(saturation, to: Self.saturationRange)
        self.gamma = Self.clamp(gamma, to: Self.gammaRange)
    }

    /// Decodes adjustments, defaulting missing values to neutral and clamping the rest.
    ///
    /// - Parameter decoder: The decoder holding the stored adjustments.
    /// - Throws: `DecodingError` when a stored value is not a number.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            brightness: try values.decodeIfPresent(Double.self, forKey: .brightness) ?? 0,
            contrast: try values.decodeIfPresent(Double.self, forKey: .contrast) ?? 1,
            saturation: try values.decodeIfPresent(Double.self, forKey: .saturation) ?? 1,
            gamma: try values.decodeIfPresent(Double.self, forKey: .gamma) ?? 1
        )
    }

    /// Whether every value leaves the picture unchanged.
    public var isNeutral: Bool {
        self == Self()
    }

    /// The adjustments clamped and rounded again, after direct edits to the properties.
    ///
    /// - Returns: Valid adjustments.
    public func normalized() -> Self {
        Self(brightness: brightness, contrast: contrast, saturation: saturation, gamma: gamma)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else {
            return min(range.upperBound, max(range.lowerBound, 0))
        }
        let stepped = (value / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }
}
