/// Something the native session reports to a Kakusan guest.
public enum KakusanGuestEvent: Equatable, Sendable {
    /// The reply for the host is ready to send back.
    case replyReady(KakusanBlock)

    /// The host's identity is known.
    case hostIdentified(KakusanIdentity)

    /// The guest's code is ready to read out.
    case codeReady(KakusanCode)

    /// The session changed state.
    case stateChanged(KakusanStateChange)

    /// The host's stream is ready at the given frame rate.
    case streamReady(fps: Int)

    /// The video view for the guest stream exists.
    case presented(StreamSurface)

    /// The first frame was shown.
    case firstFrame

    /// The stream stopped.
    case streamStopped
}
