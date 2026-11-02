/// The spatial audio switches, and the rendering they lead to on a given output.
public struct SpatialAudio: Equatable, Sendable {
    /// Whether the console's 3D audio is used on headphones.
    public var audio3D: Bool

    /// Whether Apple spatial audio is used otherwise.
    public var appleSpatial: Bool

    /// Creates the switches.
    ///
    /// - Parameters:
    ///   - audio3D: Whether 3D audio is used on headphones.
    ///   - appleSpatial: Whether Apple spatial audio is used otherwise.
    public init(audio3D: Bool = true, appleSpatial: Bool = true) {
        self.audio3D = audio3D
        self.appleSpatial = appleSpatial
    }

    /// The rendering for an output.
    ///
    /// - Parameters:
    ///   - output: The kind of output device.
    ///   - audio3DAvailable: Whether the stream offers 3D audio.
    /// - Returns: 3D audio on headphones when on and available, otherwise spatial or stereo.
    public func rendering(for output: AudioOutputKind, audio3DAvailable: Bool = true) -> SoundRendering {
        if output == .headphones, audio3D, audio3DAvailable {
            return .audio3D
        }
        return appleSpatial
            ? .spatial
            : .stereo
    }
}

/// How stream sound is rendered.
public enum SoundRendering: Equatable, Sendable {
    /// The console's own 3D audio, for headphones.
    case audio3D

    /// Apple spatial audio.
    case spatial

    /// Plain stereo.
    case stereo
}

/// The kind of device sound plays through.
public enum AudioOutputKind: Equatable, Sendable {
    /// Headphones, where 3D audio is possible.
    case headphones

    /// Speakers.
    case speakers
}
