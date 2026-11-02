/// Whether this build of the app includes Kakusan, which lets invited players join a live play session.
///
/// The `CHIAKI_KAKUSAN` build setting decides it. A build made with `CHIAKI_KAKUSAN=0` leaves Kakusan
/// out of the core and the app, and every screen, button, settings tab and menu entry that leads to
/// Kakusan stays hidden.
public enum KakusanBuild {
    #if CHIAKI_KAKUSAN
        /// `true`: this build includes Kakusan, so its screens and entry points are shown.
        public static let included = true
    #else
        /// `false`: this build leaves Kakusan out, so its screens and entry points stay hidden.
        public static let included = false
    #endif
}
