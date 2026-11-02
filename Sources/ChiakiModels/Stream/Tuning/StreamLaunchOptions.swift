/// The launch settings a stream can change, and how it starts again with them.
public struct StreamLaunchOptions: Equatable, Sendable {
    /// The picture heights offered; fewer than two means the height is fixed.
    public var heights: [Int]

    /// The frame rates offered; fewer than two means the frame rate is fixed.
    public var frameRates: [Int]

    /// The codecs offered; fewer than two means the codec is fixed.
    public var codecs: [PictureSettings.Codec]

    /// Whether HDR can be switched.
    public var hdr: Bool

    /// Whether the PS5 cloud stream quality can be chosen.
    public var quality: Bool

    /// The automatic bitrate offered, or `nil` when the bitrate cannot be changed.
    public var bitrates: StreamBitrates?

    /// How the stream starts again with changed settings.
    public var relaunch: StreamRelaunch

    /// The options of a stream whose launch settings cannot be changed.
    public static let unavailable = Self(relaunch: .reconnect)

    /// Describes what a stream can change.
    ///
    /// - Parameters:
    ///   - heights: The heights offered.
    ///   - frameRates: The frame rates offered.
    ///   - codecs: The codecs offered.
    ///   - hdr: Whether HDR can be switched.
    ///   - quality: Whether the stream quality can be chosen.
    ///   - bitrates: The automatic bitrate offered.
    ///   - relaunch: How the stream starts again.
    public init(
        heights: [Int] = [],
        frameRates: [Int] = [],
        codecs: [PictureSettings.Codec] = [],
        hdr: Bool = false,
        quality: Bool = false,
        bitrates: StreamBitrates? = nil,
        relaunch: StreamRelaunch
    ) {
        self.heights = heights
        self.frameRates = frameRates
        self.codecs = codecs
        self.hdr = hdr
        self.quality = quality
        self.bitrates = bitrates
        self.relaunch = relaunch
    }

    /// Whether nothing can be changed.
    public var isEmpty: Bool {
        heights.count < 2 && frameRates.count < 2 && codecs.count < 2 && !hdr && !quality && bitrates == nil
    }

    /// The automatic bitrate for a height.
    ///
    /// - Parameter height: The picture height.
    /// - Returns: The bitrate in megabits per second, or zero when the bitrate cannot be changed.
    public func automaticBitrateMbps(height: Int) -> Int {
        switch bitrates {
        case .console:
            StreamProfile.automaticBitrateMbps(height: height)
        case .cloud, .measuredCloud:
            CloudPictureSettings.automaticBitrateMbps(height: height)
        case nil:
            0
        }
    }

    /// Whether HDR can be switched for launch settings: only with HEVC where a codec is offered.
    ///
    /// - Parameter launch: The launch settings.
    /// - Returns: Whether the HDR switch is offered.
    public func offersHDR(for launch: StreamLaunchSettings) -> Bool {
        hdr && (codecs.isEmpty || launch.codec == .hevc)
    }

    /// The options of a console stream: a PS5 offers every resolution, codec and HDR, a PS4 only its frame
    /// rate and bitrate; both reconnect.
    ///
    /// - Parameter ps5: Whether the console is a PS5.
    /// - Returns: The options.
    public static func console(ps5: Bool) -> Self {
        Self(
            heights: ps5
                ? StreamProfile.heights
                : [],
            frameRates: StreamProfile.frameRates,
            codecs: ps5
                ? PictureSettings.Codec.choices
                : [],
            hdr: ps5,
            bitrates: .console,
            relaunch: .reconnect
        )
    }

    /// The options of a cloud stream: the service's resolutions, and HDR and quality on PS5 cloud; both
    /// restart.
    ///
    /// - Parameter service: `pscloud` or `psnow`.
    /// - Returns: The options.
    public static func cloud(_ service: String) -> Self {
        let psCloud = service == "pscloud"
        return Self(
            heights: CloudPictureSettings.heights(for: service),
            hdr: psCloud,
            quality: psCloud,
            bitrates: psCloud
                ? .measuredCloud
                : .cloud,
            relaunch: .restart
        )
    }
}

/// Which automatic bitrate a stream's launch settings offer.
public enum StreamBitrates: Equatable, Sendable {
    /// The console bitrate for the resolution.
    case console

    /// The cloud bitrate for the resolution.
    case cloud

    /// The bandwidth PS5 cloud measures at launch.
    case measuredCloud
}

/// How a stream starts again with changed launch settings.
public enum StreamRelaunch: Equatable, Sendable {
    /// The console session closes and the same console starts again under a new session.
    case reconnect

    /// The cloud game closes and starts again; unsaved progress is lost.
    case restart
}
