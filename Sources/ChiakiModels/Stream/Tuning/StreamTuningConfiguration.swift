/// The picture and sound settings the stream menu edits while a stream plays.
public struct StreamTuningConfiguration: Equatable, Sendable {
    /// How often frames are presented.
    public var presentationFrameRate: PresentationFrameRate

    /// The size the picture is upscaled to.
    public var upscaledOutput: UpscaledOutput

    /// The upscaler used.
    public var upscaler: VideoUpscaler

    /// The stream's frame rate.
    public var sourceFPS: Int

    /// The stream's picture height.
    public var nativeHeight: Int

    /// Whether generated in-between frames can be offered for this stream.
    public var frameGenerationAvailable: Bool

    /// Whether the stream asked for HDR, which rules out generated frames.
    public var hdrRequested: Bool

    /// How the picture fits the window.
    public var videoFit: VideoFit

    /// Brightness, contrast, saturation and gamma.
    public var adjustments: PictureAdjustments

    /// Whether colour banding is smoothed.
    public var reduceBanding: Bool

    /// The stream's volume, from 0 to 1.
    public var volume: Double

    /// The party voice chat level, from 0 to 1, or `nil` when the stream mixes voice chat into its sound.
    public var chatVolume: Double?

    /// How sound is placed around the listener.
    public var spatialAudio: SpatialAudio

    /// Whether the console's 3D audio can play on this stream.
    public var audio3DAvailable: Bool

    /// The launch settings the next start uses, as the stream menu edits them.
    public var launch: StreamLaunchSettings

    /// The launch settings the running stream started with.
    public var running: StreamLaunchSettings

    /// The launch settings the stream can change.
    public var launchOptions: StreamLaunchOptions

    /// Whether the edited launch settings differ from the running ones, so the stream must start again for
    /// them to apply.
    public var restartNeeded: Bool {
        !launchOptions.isEmpty && launch != running
    }

    /// Creates a configuration; generated frames are never available with HDR.
    ///
    /// - Parameters:
    ///   - presentationFrameRate: How often frames are presented.
    ///   - upscaledOutput: The upscaled size.
    ///   - upscaler: The upscaler.
    ///   - nativeHeight: The picture height.
    ///   - sourceFPS: The stream's frame rate.
    ///   - frameGenerationAvailable: Whether generated frames can be offered.
    ///   - hdrRequested: Whether the stream asked for HDR.
    ///   - videoFit: How the picture fits.
    ///   - adjustments: The picture adjustments.
    ///   - reduceBanding: Whether banding is smoothed.
    ///   - volume: The volume.
    ///   - chatVolume: The party voice chat level, or `nil` when the stream mixes voice chat into its sound.
    ///   - spatialAudio: The spatial audio setting.
    ///   - audio3DAvailable: Whether the console's 3D audio can play on this stream.
    ///   - launch: The launch settings the stream started with, or `nil` for its height and frame rate.
    ///   - launchOptions: The launch settings the stream can change.
    public init(
        presentationFrameRate: PresentationFrameRate = .source,
        upscaledOutput: UpscaledOutput = .disabled,
        upscaler: VideoUpscaler = .metalFX,
        nativeHeight: Int = 1080,
        sourceFPS: Int = 60,
        frameGenerationAvailable: Bool = false,
        hdrRequested: Bool = false,
        videoFit: VideoFit = .init(),
        adjustments: PictureAdjustments = .init(),
        reduceBanding: Bool = true,
        volume: Double = 1,
        chatVolume: Double? = nil,
        spatialAudio: SpatialAudio = .init(),
        audio3DAvailable: Bool = true,
        launch: StreamLaunchSettings? = nil,
        launchOptions: StreamLaunchOptions = .unavailable
    ) {
        self.presentationFrameRate = presentationFrameRate
        self.upscaledOutput = upscaledOutput
        self.upscaler = upscaler
        self.nativeHeight = nativeHeight
        self.sourceFPS = sourceFPS
        self.frameGenerationAvailable = frameGenerationAvailable && !hdrRequested
        self.hdrRequested = hdrRequested
        self.videoFit = videoFit
        self.adjustments = adjustments
        self.reduceBanding = reduceBanding
        self.volume = volume
        self.chatVolume = chatVolume
        self.spatialAudio = spatialAudio
        self.audio3DAvailable = audio3DAvailable
        let running = launch ?? StreamLaunchSettings(height: nativeHeight, frameRate: sourceFPS)
        self.launch = running
        self.running = running
        self.launchOptions = launchOptions
    }
}

/// The settings a stream starts with, which the stream menu can change for the next start.
///
/// Changing them needs a new start: a console stream reconnects and a cloud stream restarts.
public struct StreamLaunchSettings: Equatable, Sendable {
    /// The picture height.
    public var height: Int

    /// The frame rate.
    public var frameRate: Int

    /// The codec a PS5 streams with.
    public var codec: PictureSettings.Codec

    /// Whether HDR is asked for where the display and codec allow it.
    public var hdr: Bool

    /// Whether the bitrate follows the resolution or the measured bandwidth.
    public var automaticBitrate: Bool

    /// The manual bitrate in megabits per second.
    public var bitrateMbps: Int

    /// Whether PS5 cloud favours the highest picture or a steadier one.
    public var quality: CloudStreamQuality

    /// Describes the settings a stream starts with.
    ///
    /// - Parameters:
    ///   - height: The picture height.
    ///   - frameRate: The frame rate.
    ///   - codec: The PS5 codec.
    ///   - hdr: Whether HDR is asked for.
    ///   - automaticBitrate: Whether the bitrate is automatic.
    ///   - bitrateMbps: The manual bitrate in megabits per second.
    ///   - quality: The PS5 cloud stream quality.
    public init(
        height: Int = 1080,
        frameRate: Int = 60,
        codec: PictureSettings.Codec = .hevc,
        hdr: Bool = true,
        automaticBitrate: Bool = true,
        bitrateMbps: Int = 15,
        quality: CloudStreamQuality = .high
    ) {
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.hdr = hdr
        self.automaticBitrate = automaticBitrate
        self.bitrateMbps = bitrateMbps
        self.quality = quality
    }

    /// The settings a console stream starts with, from the saved picture settings.
    ///
    /// - Parameters:
    ///   - settings: The saved console picture settings.
    ///   - route: The picture route the stream uses.
    ///   - ps5: Whether the console is a PS5.
    /// - Returns: The launch settings.
    public static func console(_ settings: PictureSettings, route: PictureSettings.Route, ps5: Bool) -> Self {
        let profile = settings.profile(for: route, ps5: ps5)
        return Self(
            height: profile.height,
            frameRate: profile.fps,
            codec: settings.codec(forPS5: ps5, route: route),
            hdr: settings.hdrWhenSupported(route: route),
            automaticBitrate: profile.automaticBitrate,
            bitrateMbps: profile.bitrateMbps
        )
    }

    /// The settings a cloud stream starts with, from the saved cloud picture settings.
    ///
    /// - Parameters:
    ///   - settings: The saved cloud picture settings.
    ///   - service: `pscloud` or `psnow`.
    /// - Returns: The launch settings.
    public static func cloud(_ settings: CloudPictureSettings, service: String) -> Self {
        let psCloud = service == "pscloud"
        return Self(
            height: settings.height(for: service),
            hdr: settings.hdr,
            automaticBitrate: psCloud
                ? settings.psCloudAutomaticBitrate
                : settings.psNowAutomaticBitrate,
            bitrateMbps: psCloud
                ? settings.psCloudBitrateMbps
                : settings.psNowBitrateMbps,
            quality: settings.psCloudQuality
        )
    }

    /// The console picture settings with these launch settings saved for a route.
    ///
    /// A PS4 saves only its frame rate and bitrate, leaving the shared resolution and the PS5 codec as they
    /// are.
    ///
    /// - Parameters:
    ///   - settings: The saved console picture settings.
    ///   - route: The picture route the stream uses.
    ///   - ps5: Whether the console is a PS5.
    /// - Returns: The settings to save.
    public func applied(to settings: PictureSettings, route: PictureSettings.Route,
                        ps5: Bool) -> PictureSettings {
        var value = settings
        var profile = value[route]
        if ps5 {
            profile.height = height
        }
        profile.fps = frameRate
        profile.automaticBitrate = automaticBitrate
        profile.bitrateMbps = bitrateMbps
        value[route] = profile
        guard ps5 else {
            return value
        }
        switch route {
        case .local:
            value.localPS5Codec = codec.choice
            value.localPS5HDR = hdr
        case .remote:
            value.remotePS5Codec = codec.choice
            value.remotePS5HDR = hdr
        }
        return value
    }

    /// The cloud picture settings with these launch settings saved for a service; each service saves only
    /// its own settings.
    ///
    /// - Parameters:
    ///   - settings: The saved cloud picture settings.
    ///   - service: `pscloud` or `psnow`.
    /// - Returns: The settings to save.
    public func applied(to settings: CloudPictureSettings, service: String) -> CloudPictureSettings {
        var value = settings
        value.setHeight(height, for: service)
        if service == "pscloud" {
            value.hdr = hdr
            value.psCloudQuality = quality
            value.psCloudAutomaticBitrate = automaticBitrate
            value.psCloudBitrateMbps = bitrateMbps
        } else {
            value.psNowAutomaticBitrate = automaticBitrate
            value.psNowBitrateMbps = bitrateMbps
        }
        return value
    }
}
