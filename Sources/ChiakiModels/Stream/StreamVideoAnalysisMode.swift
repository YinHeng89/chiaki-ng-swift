/// Video analysis overlay that the player can draw over the stream.
public enum StreamVideoAnalysisMode: String, CaseIterable, Sendable {
    /// No analysis overlay.
    case off = "Off"
    /// Colours the picture by brightness in nits.
    case hdrHeatmap = "HDR heatmap"
    /// Marks highlights above SDR reference white and near 1000 nits.
    case highlightClipping = "Highlight clipping"
}
