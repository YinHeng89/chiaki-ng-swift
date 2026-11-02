/// The kind of stream the menu tunes, which decides where its settings load from and save to.
public enum StreamTuningContext: Equatable, Sendable {
    /// A Remote Play stream from a console over the given route, saving to the console picture settings.
    case console(PictureSettings.Route, ps5: Bool = true)
    /// A cloud stream from the named service, saving to the cloud picture settings.
    case cloud(String)
    /// A Kakusan guest stream, which only tunes sound and saves no picture settings.
    case guest

    /// The sound target the stream plays to, or `nil` for a guest.
    public var soundTarget: SoundTarget? {
        switch self {
        case .console(_, let ps5):
            ps5
                ? .ps5
                : .ps4
        case .cloud(let service):
            service == "pscloud"
                ? .psCloud
                : .psNow
        case .guest:
            nil
        }
    }
}
