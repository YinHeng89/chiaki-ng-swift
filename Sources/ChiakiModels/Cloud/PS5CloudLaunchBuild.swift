/// Whether this build of the app may start PS Cloud launches.
///
/// The `CHIAKI_PS5_CLOUD_LAUNCH` build setting decides it. A build made with `CHIAKI_PS5_CLOUD_LAUNCH=0` keeps
/// PS Cloud titles listed but offers no way to start them, and the core refuses them too. PS Now titles launch
/// in every build.
public enum PS5CloudLaunchBuild {
    #if CHIAKI_PS5_CLOUD_LAUNCH
        /// `true`: this build may start PS Cloud launches.
        public static let included = true
    #else
        /// `false`: this build refuses PS Cloud launches.
        public static let included = false
    #endif
}
