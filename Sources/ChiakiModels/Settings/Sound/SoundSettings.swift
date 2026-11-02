import Foundation

/// The persisted stream sound preferences: volume, devices, buffering, microphone, spatial audio, controller
/// speaker sounds and media.
///
/// The buffer bounds mirror the native audio path's; a bridge test asserts they stay equal. Decoding defaults
/// anything missing.
public struct SoundSettings: Codable, Equatable, Sendable {
    /// The allowed volume.
    public static let volumeRange = 0.0...1.0

    /// The allowed playback buffer in milliseconds.
    public static let bufferRange = 20...100

    /// The increment the buffer moves in.
    public static let bufferStep = 10

    /// The native audio path's default buffer.
    public static let defaultBufferMilliseconds = 40

    /// The playback volume.
    public var volume = 1.0

    /// The level party voice chat is mixed at on PS Now, where the service sends it apart from the game's sound.
    public var chatVolume = 1.0

    /// The output device's identifier, or `nil` for the system default.
    public var outputDevice: String?

    /// The playback buffer.
    public var bufferMilliseconds = Self.defaultBufferMilliseconds

    /// Whether the microphone is on when a stream starts.
    public var startWithMicrophone = false

    /// The input device's identifier, or `nil` for the system default.
    public var inputDevice: String?

    /// The spatial audio switches.
    public var spatialAudio = SpatialAudio()

    /// Whether PS5 cloud streams ask for the sounds games play through the controller speaker.
    public var controllerSpeaker = false

    /// Which media streams carry.
    public var media = StreamMedia.pictureAndSound

    private enum CodingKeys: String, CodingKey {
        case volume
        case chatVolume
        case outputDevice
        case bufferMilliseconds
        case startWithMicrophone
        case inputDevice
        case audio3D = "audio3DOnHeadphones"
        case appleSpatial
        case controllerSpeaker = "controllerSpeakerOnCloud"
        case media
    }

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - volume: The playback volume.
    ///   - outputDevice: The output device, or `nil` for the default.
    ///   - bufferMilliseconds: The playback buffer.
    ///   - startWithMicrophone: Whether the microphone starts on.
    ///   - inputDevice: The input device, or `nil` for the default.
    ///   - audio3D: Whether 3D audio is used on headphones.
    ///   - appleSpatial: Whether Apple spatial audio is used otherwise.
    ///   - controllerSpeaker: Whether PS5 cloud streams ask for controller speaker sounds.
    ///   - chatVolume: The party voice chat level.
    public init(
        volume: Double = 1.0,
        outputDevice: String? = nil,
        bufferMilliseconds: Int = Self.defaultBufferMilliseconds,
        startWithMicrophone: Bool = false,
        inputDevice: String? = nil,
        audio3D: Bool = true,
        appleSpatial: Bool = true,
        controllerSpeaker: Bool = false,
        chatVolume: Double = 1.0
    ) {
        self.volume = volume
        self.chatVolume = chatVolume
        self.outputDevice = outputDevice
        self.bufferMilliseconds = bufferMilliseconds
        self.startWithMicrophone = startWithMicrophone
        self.inputDevice = inputDevice
        spatialAudio = SpatialAudio(audio3D: audio3D, appleSpatial: appleSpatial)
        self.controllerSpeaker = controllerSpeaker
    }

    /// Decodes settings, defaulting anything missing.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        volume = try values.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        chatVolume = try values.decodeIfPresent(Double.self, forKey: .chatVolume) ?? 1.0
        outputDevice = try values.decodeIfPresent(String.self, forKey: .outputDevice)
        bufferMilliseconds = try values.decodeIfPresent(Int.self, forKey: .bufferMilliseconds)
            ?? Self.defaultBufferMilliseconds
        startWithMicrophone = try values.decodeIfPresent(Bool.self, forKey: .startWithMicrophone) ?? false
        inputDevice = try values.decodeIfPresent(String.self, forKey: .inputDevice)
        spatialAudio = SpatialAudio(
            audio3D: try values.decodeIfPresent(Bool.self, forKey: .audio3D) ?? true,
            appleSpatial: try values.decodeIfPresent(Bool.self, forKey: .appleSpatial) ?? true
        )
        controllerSpeaker = try values.decodeIfPresent(Bool.self, forKey: .controllerSpeaker) ?? false
        media = (try? values.decodeIfPresent(StreamMedia.self, forKey: .media)) ?? .pictureAndSound
    }

    /// Encodes the settings with the spatial switches flattened.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: The encoder's error.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(volume, forKey: .volume)
        try values.encode(chatVolume, forKey: .chatVolume)
        try values.encodeIfPresent(outputDevice, forKey: .outputDevice)
        try values.encode(bufferMilliseconds, forKey: .bufferMilliseconds)
        try values.encode(startWithMicrophone, forKey: .startWithMicrophone)
        try values.encodeIfPresent(inputDevice, forKey: .inputDevice)
        try values.encode(spatialAudio.audio3D, forKey: .audio3D)
        try values.encode(spatialAudio.appleSpatial, forKey: .appleSpatial)
        try values.encode(controllerSpeaker, forKey: .controllerSpeaker)
        try values.encode(media, forKey: .media)
    }

    /// The settings clamped into range, with empty device names cleared and the buffer stepped.
    ///
    /// - Returns: The normalised settings.
    public func normalized() -> Self {
        var value = self
        value.volume = min(Self.volumeRange.upperBound, max(Self.volumeRange.lowerBound, volume))
        value.chatVolume = min(Self.volumeRange.upperBound, max(Self.volumeRange.lowerBound, chatVolume))
        if value.outputDevice?.isEmpty == true {
            value.outputDevice = nil
        }
        if value.inputDevice?.isEmpty == true {
            value.inputDevice = nil
        }
        let stepped = Int((Double(bufferMilliseconds) / Double(Self.bufferStep)).rounded()) * Self.bufferStep
        value.bufferMilliseconds = min(Self.bufferRange.upperBound, max(Self.bufferRange.lowerBound, stepped))
        return value
    }

    /// Checks every value.
    ///
    /// - Returns: The settings unchanged.
    /// - Throws: ``SoundSettingsError/invalid`` when a value is out of range.
    public func validated() throws -> Self {
        guard Self.volumeRange.contains(volume), Self.volumeRange.contains(chatVolume),
              Self.bufferRange.contains(bufferMilliseconds),
              outputDevice.map({ !$0.isEmpty && $0.utf8.count < 256 }) ?? true,
              inputDevice.map({ !$0.isEmpty && $0.utf8.count < 256 }) ?? true
        else {
            throw SoundSettingsError.invalid
        }
        return self
    }
}

extension SoundSettings: PersistedSettingValue {
    /// The key the sound settings are stored under.
    public static var settingKey: SettingKey<SoundSettings> {
        SettingKeys.sound
    }
}

/// Why sound settings were refused.
public enum SoundSettingsError: Error {
    /// The volume, buffer or a device name is out of range.
    case invalid
}
