import Foundation

/// How stream video is placed in a window: the fit mode and, for ``VideoFitMode/zoom``, the magnification.
public struct VideoFit: Codable, Equatable, Sendable {
    /// The allowed magnification.
    public static let zoomRange = 1.0...3.0

    /// The fit mode.
    public var mode = VideoFitMode.fit

    /// The magnification applied in ``VideoFitMode/zoom``.
    public var zoom = 1.0

    /// Creates a fit, clamping the magnification.
    ///
    /// - Parameters:
    ///   - mode: The fit mode.
    ///   - zoom: The magnification.
    public init(mode: VideoFitMode = .fit, zoom: Double = 1.0) {
        self.mode = mode
        self.zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom))
    }

    /// Decodes a fit, defaulting anything missing.
    ///
    /// - Parameter decoder: The decoder holding the stored fit.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try values.decodeIfPresent(VideoFitMode.self, forKey: .mode) ?? .fit,
            zoom: try values.decodeIfPresent(Double.self, forKey: .zoom) ?? 1.0
        )
    }

    /// The video rectangle inside a window, centred.
    ///
    /// - Parameters:
    ///   - width: The window width.
    ///   - height: The window height.
    ///   - aspect: The video's width-to-height ratio.
    /// - Returns: The video frame, empty for an empty window.
    public func frame(width: Double, height: Double, aspect: Double = 16.0 / 9.0) -> VideoFrame {
        guard width > 0, height > 0 else {
            return VideoFrame(originX: 0, originY: 0, width: 0, height: 0)
        }
        let videoWidth: Double
        switch mode {
        case .stretch:
            return VideoFrame(originX: 0, originY: 0, width: width, height: height)
        case .fit:
            videoWidth = min(width, height * aspect)
        case .zoom:
            videoWidth = max(width, height * aspect) * zoom
        }
        let videoHeight = videoWidth / aspect
        return VideoFrame(
            originX: (width - videoWidth) / 2,
            originY: (height - videoHeight) / 2,
            width: videoWidth,
            height: videoHeight
        )
    }
}

/// A rectangle in window points where stream video is drawn.
public struct VideoFrame: Equatable, Sendable {
    /// The left edge.
    public var originX: Double

    /// The top edge.
    public var originY: Double

    /// The width.
    public var width: Double

    /// The height.
    public var height: Double

    /// Creates a frame.
    ///
    /// - Parameters:
    ///   - originX: The left edge.
    ///   - originY: The top edge.
    ///   - width: The width.
    ///   - height: The height.
    public init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}

/// How the video fills a window whose shape differs from the stream's.
public enum VideoFitMode: String, Codable, CaseIterable, Sendable {
    /// The whole picture is shown, with bars where the shapes differ.
    case fit

    /// The picture fills the window and is cropped, optionally magnified further.
    case zoom

    /// The picture is stretched to the window's shape.
    case stretch

    /// The label shown for the mode.
    public var title: LocalizedStringResource {
        switch self {
        case .fit:
            return .settingsPictureVideoFitFit
        case .zoom:
            return .settingsPictureVideoFitZoom
        case .stretch:
            return .settingsPictureVideoFitStretch
        }
    }
}
