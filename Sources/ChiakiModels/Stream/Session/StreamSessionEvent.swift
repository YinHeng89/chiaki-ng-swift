/// Something a live stream session reports, in the order the player reported it.
///
/// The session's event stream finishes normally when the console or service ended the stream, throws a
/// ``StreamFailure`` when it failed, and finishes without a further event once it was left.
public enum StreamSessionEvent: Equatable, Sendable {
    /// The player's video view is ready to embed.
    case presented(StreamSurface)

    /// The picture settings for the given route were applied, after the console was found local or remote.
    case pictureRoute(PictureSettings.Route)

    /// A console stream chose this route: the local network or the internet.
    case route(ConsoleRoute)

    /// The picture is switched off for this stream, so only sound plays.
    case videoDisabled(Bool)

    /// How the picture fits the window when the stream starts.
    case videoFit(VideoFit)

    /// The core retried a console or guest start; `attempt` counts retries from one.
    case startRetried(attempt: Int)

    /// A cloud start reached a step.
    case cloudStep(CloudStartStep)

    /// A cloud launch offered datacenters to choose from.
    case datacenterOffered(CloudDatacenterLaunchOffer)

    /// A cloud launch connected to a datacenter.
    case datacenterSelected(CloudDatacenterSelection)

    /// The start or a reconnection reported progress.
    case progress(StreamProgress)

    /// The console asked for a code.
    case accessRequested(StreamAccessPrompt)

    /// The first video frame was shown.
    case firstFrame

    /// The connection dropped and the core is reconnecting, at `attempt`.
    case reconnecting(attempt: Int)

    /// The core reconnected.
    case reconnected

    /// The console started or stopped prohibiting its picture from being shown.
    case displayProhibited(Bool)

    /// The stream started or stopped receiving nothing from the console for five seconds while it plays.
    case connectionWaiting(Bool)

    /// Something happened to couch seats or controllers.
    case couch(CouchSessionEvent)

    /// The couch controller light colours changed.
    case lights(CouchLights)

    /// The console's on-screen keyboard changed.
    case keyboard(ConsoleKeyboardSignal)

    /// A Kakusan guest session reported something.
    case guest(KakusanGuestEvent)

    /// The cloud service warned that it closes the game soon.
    case closing(CloudClosingNotice)

    /// The PS5 cloud console showed a notice, such as a saved screenshot or an earned trophy.
    case cloudNotice(CloudSystemNotice)

    /// The PS5 cloud console started or updated its recording banner, or `nil` once recording stopped.
    case recording(CloudRecordingBanner?)

    /// The PS5 cloud console sent the preview of a capture it just took.
    case captureThumbnail(CloudCaptureThumbnail)
}
