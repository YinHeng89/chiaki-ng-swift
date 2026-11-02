import Foundation

/// The resolution, frame rate, bitrate and upscale a stream asks for.
public struct StreamProfile: Codable, Equatable, Sendable {
    /// The supported vertical resolutions.
    public static let heights = [720, 1080]

    /// The supported frame rates.
    public static let frameRates = [30, 60]

    /// The supported bitrates in megabits per second.
    public static let bitrateRange = 2...100

    /// The profile remote streams start with.
    public static let remoteDefault = StreamProfile(
        height: 720,
        fps: 60,
        bitrateMbps: 15,
        upscaledOutput: .fullHD
    )

    /// The bitrate chosen when ``automaticBitrate`` is on.
    ///
    /// - Parameter height: The vertical resolution.
    /// - Returns: The bitrate in megabits per second.
    public static func automaticBitrateMbps(height: Int) -> Int {
        height <= 720
            ? 10
            : 15
    }

    /// The vertical resolution.
    public var height: Int

    /// The frame rate.
    public var fps: Int

    /// The bitrate in megabits per second used when ``automaticBitrate`` is off.
    public var bitrateMbps: Int

    /// Whether the bitrate follows the resolution.
    public var automaticBitrate: Bool

    /// The resolution video is upscaled to.
    public var upscaledOutput: UpscaledOutput

    /// The bitrate the stream requests.
    public var effectiveBitrateMbps: Int {
        automaticBitrate
            ? Self.automaticBitrateMbps(height: height)
            : bitrateMbps
    }

    /// Creates a profile, raising retired heights to 720, capping the bitrate and fitting the upscale.
    ///
    /// - Parameters:
    ///   - height: The vertical resolution.
    ///   - fps: The frame rate.
    ///   - bitrateMbps: The manual bitrate.
    ///   - automaticBitrate: Whether the bitrate follows the resolution.
    ///   - upscaledOutput: The upscale.
    public init(
        height: Int = 1080,
        fps: Int = 60,
        bitrateMbps: Int = 30,
        automaticBitrate: Bool = true,
        upscaledOutput: UpscaledOutput = .fourK
    ) {
        self.height = [360, 540].contains(height)
            ? 720
            : height
        self.fps = fps
        self.bitrateMbps = min(bitrateMbps, Self.bitrateRange.upperBound)
        self.automaticBitrate = automaticBitrate
        self.upscaledOutput = upscaledOutput.compatible(with: self.height)
    }

    /// Decodes a profile, defaulting anything missing.
    ///
    /// - Parameter decoder: The decoder holding the stored profile.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            height: try values.decodeIfPresent(Int.self, forKey: .height) ?? 1080,
            fps: try values.decodeIfPresent(Int.self, forKey: .fps) ?? 60,
            bitrateMbps: try values.decodeIfPresent(Int.self, forKey: .bitrateMbps) ?? 30,
            automaticBitrate: try values.decodeIfPresent(Bool.self, forKey: .automaticBitrate) ?? true,
            upscaledOutput: try values.decodeIfPresent(UpscaledOutput.self, forKey: .upscaledOutput) ?? .fourK
        )
    }

    /// The profile with its upscale fitted to its height.
    ///
    /// - Returns: The normalised profile.
    public func normalized() -> Self {
        var value = self
        value.upscaledOutput = upscaledOutput.compatible(with: height)
        return value
    }

    /// Checks every value against what streams support.
    ///
    /// - Returns: The profile unchanged.
    /// - Throws: ``PictureSettingsError/invalid`` when a value is unsupported.
    public func validated() throws -> Self {
        guard Self.heights.contains(height), Self.frameRates.contains(fps),
              Self.bitrateRange.contains(bitrateMbps),
              UpscaledOutput.available(for: height).contains(upscaledOutput)
        else {
            throw PictureSettingsError.invalid
        }
        return self
    }
}
