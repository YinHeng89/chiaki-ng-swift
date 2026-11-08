import Foundation

/// Which media a stream carries.
public enum StreamMedia: String, Codable, CaseIterable, Sendable {
    /// Video and sound.
    case pictureAndSound

    /// Sound without video.
    case soundOnly

    /// Video without sound.
    case pictureOnly

    /// Neither; the stream only carries controller input.
    case controlsOnly

    /// The label shown for the choice.
    public var title: LocalizedStringResource {
        switch self {
        case .pictureAndSound:
            .settingsSoundMediaPictureAndSound
        case .soundOnly:
            .settingsSoundMediaSoundOnly
        case .pictureOnly:
            .settingsSoundMediaPictureOnly
        case .controlsOnly:
            .settingsSoundMediaControlsOnly
        }
    }

    /// Whether video is carried.
    public var picture: Bool {
        self == .pictureAndSound || self == .pictureOnly
    }

    /// Whether sound is carried.
    public var sound: Bool {
        self == .pictureAndSound || self == .soundOnly
    }
}
