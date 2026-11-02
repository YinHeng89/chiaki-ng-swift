import Foundation

/// The persisted cloud stream picture preferences, separately for PS Cloud and PS Now.
///
/// Services are named by their stored text, `pscloud` or `psnow`. Decoding upgrades the older "disabled"
/// upscaler value, fits each upscale to its height and caps the bitrates.
public struct CloudPictureSettings: Codable, Equatable, Sendable {
    /// The heights PS Cloud offers.
    public static let psCloudHeights = [720, 1080, 1440, 2160]

    /// The heights PS Now offers.
    public static let psNowHeights = [720, 1080]

    /// The tallest height streamed without HDR.
    public static let maximumSDRHeight = 1080

    /// The PS Cloud height.
    public var psCloudHeight = 2160

    /// The PS Cloud manual bitrate in megabits per second.
    public var psCloudBitrateMbps = 20

    /// Whether the PS Cloud bitrate follows the height and measured bandwidth.
    public var psCloudAutomaticBitrate = true

    /// The PS Now height.
    public var psNowHeight = 1080

    /// The PS Now manual bitrate in megabits per second.
    public var psNowBitrateMbps = 20

    /// Whether the PS Now bitrate follows the height.
    public var psNowAutomaticBitrate = true

    /// Whether PS Cloud asks for HDR above ``maximumSDRHeight``.
    public var hdr = true

    /// Whether PS Cloud favours the highest picture or a steadier one.
    public var psCloudQuality = CloudStreamQuality.high

    /// The PS Cloud upscale.
    public var upscaledOutput: UpscaledOutput = .fourK

    /// The PS Now upscale.
    public var psNowUpscaledOutput: UpscaledOutput = .fourK

    /// The upscaling method.
    public var upscaler: VideoUpscaler = .metalFX

    /// The presentation frame rate.
    public var presentationFrameRate: PresentationFrameRate = .source

    /// How video is placed in the window.
    public var videoFit = VideoFit()

    /// The colour adjustments.
    public var adjustments = PictureAdjustments()

    /// Whether a debanding pass is applied.
    public var reduceBanding = true

    /// When screenshots and clips taken in a PS5 cloud game are saved to this Mac.
    public var captureSaving = CloudCaptureSaving.followPlayStation

    /// The folder captures are saved to, or empty for ``defaultCaptureFolder``.
    public var captureFolder = ""

    /// The security-scoped bookmark saved when the user chose ``captureFolder``, or `nil` for the default
    /// folder; ``FolderAccess`` uses it to reach the folder again after a relaunch.
    public var captureFolderBookmark: Data?

    /// Creates the default settings.
    public init() {
        upscaledOutput = upscaledOutput.compatible(with: psCloudHeight)
    }

    /// Decodes settings, upgrading older values and defaulting anything missing.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        psCloudHeight = try values.decodeIfPresent(Int.self, forKey: .psCloudHeight) ?? 2160
        psCloudBitrateMbps = try values.decodeIfPresent(Int.self, forKey: .psCloudBitrateMbps) ?? 20
        psCloudAutomaticBitrate = try values
            .decodeIfPresent(Bool.self, forKey: .psCloudAutomaticBitrate) ?? true
        psNowHeight = try values.decodeIfPresent(Int.self, forKey: .psNowHeight) ?? 1080
        psNowBitrateMbps = try values.decodeIfPresent(Int.self, forKey: .psNowBitrateMbps) ?? 20
        psNowAutomaticBitrate = try values.decodeIfPresent(Bool.self, forKey: .psNowAutomaticBitrate) ?? true
        hdr = try values.decodeIfPresent(Bool.self, forKey: .hdr) ?? true
        psCloudQuality = (try? values.decodeIfPresent(CloudStreamQuality.self, forKey: .psCloudQuality))
            ?? .high
        let savedUpscaler = try values.decodeIfPresent(String.self, forKey: .upscaler)
        if savedUpscaler == "disabled" {
            upscaledOutput = .disabled
            upscaler = .metalFX
        } else {
            upscaledOutput = try values
                .decodeIfPresent(UpscaledOutput.self, forKey: .upscaledOutput) ?? .fourK
            upscaler = savedUpscaler.flatMap(VideoUpscaler.init(rawValue:)) ?? .metalFX
        }
        psNowUpscaledOutput = try values
            .decodeIfPresent(UpscaledOutput.self, forKey: .psNowUpscaledOutput) ?? upscaledOutput
        upscaledOutput = upscaledOutput.compatible(with: psCloudHeight)
        psNowUpscaledOutput = psNowUpscaledOutput.compatible(with: psNowHeight)
        psCloudBitrateMbps = min(psCloudBitrateMbps, StreamProfile.bitrateRange.upperBound)
        psNowBitrateMbps = min(psNowBitrateMbps, StreamProfile.bitrateRange.upperBound)
        videoFit = try values.decodeIfPresent(VideoFit.self, forKey: .videoFit) ?? .init()
        adjustments = try values.decodeIfPresent(PictureAdjustments.self, forKey: .adjustments) ?? .init()
        reduceBanding = try values.decodeIfPresent(Bool.self, forKey: .reduceBanding) ?? true
        presentationFrameRate = try values
            .decodeIfPresent(PresentationFrameRate.self, forKey: .presentationFrameRate) ?? .source
        if let saving = try? values.decodeIfPresent(CloudCaptureSaving.self, forKey: .captureSaving) {
            captureSaving = saving
        } else if let saves = try decoder.container(keyedBy: LegacyKeys.self)
            .decodeIfPresent(Bool.self, forKey: .savesCaptures) {
            captureSaving = saves
                ? .followPlayStation
                : .never
        }
        captureFolder = try values.decodeIfPresent(String.self, forKey: .captureFolder) ?? ""
        captureFolderBookmark = try values.decodeIfPresent(Data.self, forKey: .captureFolderBookmark)
    }

    private enum LegacyKeys: String, CodingKey {
        case savesCaptures
    }

    /// The folder captures are saved to when none was chosen: `chiaki-ng` in the user's Pictures folder.
    public static var defaultCaptureFolder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return pictures.appendingPathComponent("chiaki-ng", isDirectory: true)
    }

    /// The folder captures are saved to: the chosen one, else ``defaultCaptureFolder``.
    public var captureDirectory: URL {
        captureFolder.isEmpty
            ? Self.defaultCaptureFolder
            : URL(fileURLWithPath: captureFolder, isDirectory: true)
    }

    /// The settings with each upscale fitted to its height and the adjustments in range.
    ///
    /// - Returns: The normalised settings.
    public func normalized() -> Self {
        var value = self
        value.upscaledOutput = upscaledOutput.compatible(with: psCloudHeight)
        value.psNowUpscaledOutput = psNowUpscaledOutput.compatible(with: psNowHeight)
        value.adjustments = adjustments.normalized()
        return value
    }

    /// The upscale for a service.
    ///
    /// - Parameter service: `pscloud` or `psnow`.
    /// - Returns: The service's upscale.
    public func output(for service: String) -> UpscaledOutput {
        service == "pscloud"
            ? upscaledOutput
            : psNowUpscaledOutput
    }

    /// Checks every height, bitrate and upscale.
    ///
    /// - Returns: The settings unchanged.
    /// - Throws: ``PictureSettingsError/invalid`` when a value is unsupported.
    public func validated() throws -> Self {
        guard Self.psCloudHeights.contains(psCloudHeight),
              Self.psNowHeights.contains(psNowHeight),
              StreamProfile.bitrateRange.contains(psCloudBitrateMbps),
              StreamProfile.bitrateRange.contains(psNowBitrateMbps),
              UpscaledOutput.available(for: psCloudHeight).contains(upscaledOutput),
              UpscaledOutput.available(for: psNowHeight).contains(psNowUpscaledOutput) else {
            throw PictureSettingsError.invalid
        }
        return self
    }

    /// The height for a service.
    ///
    /// - Parameter service: `pscloud` or `psnow`.
    /// - Returns: The service's height.
    public func height(for service: String) -> Int {
        if service == "pscloud" {
            return psCloudHeight
        }
        return psNowHeight
    }

    /// The heights a service offers.
    ///
    /// - Parameter service: `pscloud` or `psnow`.
    /// - Returns: The heights, shortest first.
    public static func heights(for service: String) -> [Int] {
        service == "pscloud"
            ? psCloudHeights
            : psNowHeights
    }

    /// Chooses the height a service streams at; a height the service does not offer is ignored.
    ///
    /// - Parameters:
    ///   - height: The vertical resolution.
    ///   - service: `pscloud` or `psnow`.
    public mutating func setHeight(_ height: Int, for service: String) {
        guard Self.heights(for: service).contains(height) else {
            return
        }
        if service == "pscloud" {
            psCloudHeight = height
        } else {
            psNowHeight = height
        }
    }

    /// The bitrate chosen automatically for a cloud height.
    ///
    /// - Parameter height: The vertical resolution.
    /// - Returns: The bitrate in megabits per second.
    public static func automaticBitrateMbps(height: Int) -> Int {
        switch height {
        case ...720:
            return 10
        case ...1080:
            return 15
        case ...1440:
            return 35
        default:
            return 50
        }
    }

    /// The bitrate a service requests.
    ///
    /// - Parameter service: `pscloud` or `psnow`.
    /// - Returns: The automatic or manual bitrate in megabits per second.
    public func bitrateMbps(for service: String) -> Int {
        if service == "pscloud" {
            return psCloudAutomaticBitrate
                ? Self.automaticBitrateMbps(height: psCloudHeight)
                : psCloudBitrateMbps
        }
        return psNowAutomaticBitrate
            ? Self.automaticBitrateMbps(height: psNowHeight)
            : psNowBitrateMbps
    }

    /// Whether bandwidth is measured before a stream of the service starts.
    ///
    /// - Parameter service: `pscloud` or `psnow`.
    /// - Returns: `true` for PS Cloud with an automatic bitrate.
    public func measuresBandwidth(for service: String) -> Bool {
        service == "pscloud" && psCloudAutomaticBitrate
    }

    /// Whether a stream of the service asks for HDR.
    ///
    /// - Parameters:
    ///   - service: `pscloud` or `psnow`.
    ///   - displaySupportsHDR: Whether the screen can show HDR.
    /// - Returns: `true` for PS Cloud above ``maximumSDRHeight`` with HDR on and supported.
    public func requestsHDR(for service: String, displaySupportsHDR: Bool) -> Bool {
        service == "pscloud" && hdr && displaySupportsHDR && psCloudHeight > Self.maximumSDRHeight
    }

    /// Whether frames are generated up to 120 per second for a service.
    ///
    /// - Parameter service: `pscloud` or `psnow`.
    /// - Returns: `true` when generation is on and the service's height supports it.
    public func usesGenerated120(for service: String) -> Bool {
        presentationFrameRate == .generated120 && [720, 1080].contains(height(for: service))
    }
}

extension CloudPictureSettings: PersistedSettingValue {
    /// The key the cloud picture settings are stored under.
    public static var settingKey: SettingKey<CloudPictureSettings> {
        SettingKeys.cloudPicture
    }
}

/// When screenshots and clips taken in a PS5 cloud game are saved to this Mac.
public enum CloudCaptureSaving: String, Codable, CaseIterable, Equatable, Sendable {
    /// Whenever the PS5's own capture setting downloads them.
    case followPlayStation

    /// Always.
    case always

    /// Never.
    case never
}

/// Whether a PS5 cloud stream favours the highest picture or a steadier one.
public enum CloudStreamQuality: String, Codable, CaseIterable, Equatable, Sendable {
    /// The highest picture the connection allows.
    case high

    /// A steadier picture that adapts less often.
    case stable
}
