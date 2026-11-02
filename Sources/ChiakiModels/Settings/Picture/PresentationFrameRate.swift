/// The frame rate video is presented at.
public enum PresentationFrameRate: String, Codable, CaseIterable, Sendable {
    /// The stream's own frame rate.
    case source

    /// 120 frames per second, with generated frames between the stream's.
    case generated120
}
