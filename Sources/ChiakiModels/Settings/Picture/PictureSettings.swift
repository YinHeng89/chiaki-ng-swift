import Foundation

/// The persisted console stream picture preferences: a profile per route, codec and HDR choices, upscaling,
/// placement and colour adjustments.
///
/// Decoding upgrades the single-profile layout older versions stored and defaults anything missing.
public struct PictureSettings: Codable, Equatable, Sendable {
    /// A video codec a stream can request.
    public enum Codec: String, Codable, CaseIterable, Sendable {
        /// H.264, the only codec a PS4 streams.
        case h264

        /// HEVC.
        case hevc = "h265"

        /// HEVC with HDR, chosen at launch when the route allows HDR and the screen supports it.
        case hevcHDR = "h265_hdr"

        /// The label shown for the codec.
        public var title: LocalizedStringResource {
            switch self {
            case .h264:
                return .settingsPictureCodecH264
            case .hevc:
                return .settingsPictureCodecHevc
            case .hevcHDR:
                return .settingsPictureCodecHevcHdr
            }
        }

        /// The codecs offered as a setting; HDR is a separate switch.
        public static let choices: [Codec] = [.h264, .hevc]

        /// The setting this codec corresponds to, folding HDR into HEVC.
        public var choice: Codec {
            switch self {
            case .h264:
                return .h264
            case .hevc, .hevcHDR:
                return .hevc
            }
        }
    }

    /// Whether a stream reaches the console on the local network or over the internet.
    public enum Route: Sendable {
        /// On the local network.
        case local

        /// Over the internet.
        case remote

        /// Chooses the route.
        ///
        /// - Parameter remote: Whether the stream goes over the internet.
        public init(remote: Bool) {
            self = remote
                ? .remote
                : .local
        }
    }

    /// The tallest stream a PS4 accepts.
    public static let ps4Height = 720

    /// The profile for local streams.
    public var local = StreamProfile()

    /// The profile for remote streams.
    public var remote = StreamProfile.remoteDefault

    /// The upscaling method.
    public var upscaler: VideoUpscaler = .metalFX

    /// The presentation frame rate.
    public var presentationFrameRate: PresentationFrameRate = .source

    /// The codec a PS5 streams locally.
    public var localPS5Codec = Codec.hevc

    /// The codec a PS5 streams remotely.
    public var remotePS5Codec = Codec.hevc

    /// Whether local PS5 streams use HDR when the screen supports it.
    public var localPS5HDR = true

    /// Whether remote PS5 streams use HDR when the screen supports it.
    public var remotePS5HDR = true

    /// How video is placed in the window.
    public var videoFit = VideoFit()

    /// The colour adjustments.
    public var adjustments = PictureAdjustments()

    /// Whether a debanding pass is applied.
    public var reduceBanding = true

    /// Whether streams open full screen.
    public var fullScreenStreams = false

    private enum CodingKeys: String, CodingKey {
        case local, remote, upscaler, presentationFrameRate, localPS5Codec, remotePS5Codec, localPS5HDR,
             remotePS5HDR, videoFit, adjustments, reduceBanding, fullScreenStreams
    }

    private enum LegacyKeys: String, CodingKey {
        case height, fps, bitrateMbps, upscaledOutput, upscaler
    }

    /// Creates the default settings.
    public init() {
    }

    /// Decodes settings, upgrading the older single-profile layout and defaulting anything missing.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let savedUpscaler = try legacy.decodeIfPresent(String.self, forKey: .upscaler)
        upscaler = savedUpscaler.flatMap(VideoUpscaler.init(rawValue:)) ?? .metalFX
        if let local = try values.decodeIfPresent(StreamProfile.self, forKey: .local) {
            self.local = local
            remote = try values.decodeIfPresent(StreamProfile.self, forKey: .remote) ?? local
        } else {
            let profile = StreamProfile(
                height: try legacy.decodeIfPresent(Int.self, forKey: .height) ?? 1080,
                fps: try legacy.decodeIfPresent(Int.self, forKey: .fps) ?? 60,
                bitrateMbps: try legacy.decodeIfPresent(Int.self, forKey: .bitrateMbps) ?? 30,
                upscaledOutput: savedUpscaler == "disabled"
                    ? .disabled
                    : try legacy.decodeIfPresent(UpscaledOutput.self, forKey: .upscaledOutput) ?? .fourK
            )
            local = profile
            remote = profile
        }
        presentationFrameRate = try values
            .decodeIfPresent(PresentationFrameRate.self, forKey: .presentationFrameRate) ?? .source
        localPS5Codec = try values.decodeIfPresent(Codec.self, forKey: .localPS5Codec)?.choice ?? .hevc
        remotePS5Codec = try values.decodeIfPresent(Codec.self, forKey: .remotePS5Codec)?.choice ?? .hevc
        localPS5HDR = try values.decodeIfPresent(Bool.self, forKey: .localPS5HDR) ?? true
        remotePS5HDR = try values.decodeIfPresent(Bool.self, forKey: .remotePS5HDR) ?? true
        videoFit = try values.decodeIfPresent(VideoFit.self, forKey: .videoFit) ?? .init()
        adjustments = try values.decodeIfPresent(PictureAdjustments.self, forKey: .adjustments) ?? .init()
        reduceBanding = try values.decodeIfPresent(Bool.self, forKey: .reduceBanding) ?? true
        fullScreenStreams = try values.decodeIfPresent(Bool.self, forKey: .fullScreenStreams) ?? false
    }

    /// The settings with every profile and adjustment brought back within range.
    ///
    /// - Returns: The normalised settings.
    public func normalized() -> Self {
        var value = self
        value.local = local.normalized()
        value.remote = remote.normalized()
        value.adjustments = adjustments.normalized()
        return value
    }

    /// Checks both profiles.
    ///
    /// - Returns: The settings unchanged.
    /// - Throws: ``PictureSettingsError/invalid`` when either profile is out of range.
    public func validated() throws -> Self {
        _ = try local.validated()
        _ = try remote.validated()
        return self
    }

    /// The codec setting for a console and route, before HDR is considered.
    ///
    /// - Parameters:
    ///   - ps5: Whether the console is a PS5.
    ///   - route: The route.
    /// - Returns: ``Codec/h264`` for a PS4, otherwise the route's chosen codec.
    public func codec(forPS5 ps5: Bool, route: Route) -> Codec {
        guard ps5 else {
            return .h264
        }
        switch route {
        case .local:
            return localPS5Codec.choice
        case .remote:
            return remotePS5Codec.choice
        }
    }

    /// Whether the route asks for HDR when the screen supports it.
    ///
    /// - Parameter route: The route.
    /// - Returns: The route's HDR switch.
    public func hdrWhenSupported(route: Route) -> Bool {
        switch route {
        case .local:
            return localPS5HDR
        case .remote:
            return remotePS5HDR
        }
    }

    /// The codec a stream actually requests, upgrading HEVC to HDR when the route and screen allow it.
    ///
    /// - Parameters:
    ///   - ps5: Whether the console is a PS5.
    ///   - route: The route.
    ///   - displaySupportsHDR: Whether the screen can show HDR.
    /// - Returns: The codec to request.
    public func launchCodec(forPS5 ps5: Bool, route: Route, displaySupportsHDR: Bool) -> Codec {
        let codec = codec(forPS5: ps5, route: route)
        guard codec == .hevc, hdrWhenSupported(route: route), displaySupportsHDR else {
            return codec
        }
        return .hevcHDR
    }

    /// The profile a stream uses, capped at ``ps4Height`` for a PS4.
    ///
    /// - Parameters:
    ///   - route: The route.
    ///   - ps5: Whether the console is a PS5.
    /// - Returns: The normalised profile.
    public func profile(for route: Route, ps5: Bool = true) -> StreamProfile {
        let profile: StreamProfile
        switch route {
        case .local:
            profile = local
        case .remote:
            profile = remote
        }
        guard !ps5, profile.height > Self.ps4Height else {
            return profile.normalized()
        }
        var capped = profile
        capped.height = Self.ps4Height
        return capped.normalized()
    }

    /// The stored profile for a route; setting it normalises the new profile.
    ///
    /// - Parameter route: The route.
    public subscript(route: Route) -> StreamProfile {
        get {
            switch route {
            case .local:
                local
            case .remote:
                remote
            }
        }
        set {
            switch route {
            case .local:
                local = newValue.normalized()
            case .remote:
                remote = newValue.normalized()
            }
        }
    }

    /// Whether frames are generated up to 120 per second for a route.
    ///
    /// - Parameter route: The route.
    /// - Returns: `true` when generation is on and the route's height supports it.
    public func usesGenerated120(for route: Route) -> Bool {
        presentationFrameRate == .generated120 && [720, 1080].contains(self[route].height)
    }
}

extension PictureSettings: PersistedSettingValue {
    /// The key the console picture settings are stored under.
    public static var settingKey: SettingKey<PictureSettings> {
        SettingKeys.picture
    }
}

/// Why picture settings were refused.
public enum PictureSettingsError: Error {
    /// A resolution, frame rate, bitrate or upscale is outside what the stream supports.
    case invalid
}
