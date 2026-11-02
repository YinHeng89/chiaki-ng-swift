import Foundation

/// The names this application is known by on disk and to the system.
///
/// Debug builds on macOS and the Mac App Store build use their own bundle identifier and Keychain service so they
/// never share data, keys or system permissions with the downloaded release build installed on the same Mac.
public enum AppIdentity {
    /// The name the application shows for itself, in error reports and scratch folders.
    public static let name = "chiaki-ng"

    #if DEBUG && os(macOS)
        /// The bundle identifier of the application, also the folder name under Application Support, Logs and
        /// Caches; a debug profile named by ``debugProfile`` adds its name, so a second debug instance can sign
        /// in to another account without sharing data.
        public static let bundleIdentifier = debugProfile.map {
            "io.github.chiaki-ng.chiaki-ng.debug.\($0)"
        } ?? "io.github.chiaki-ng.chiaki-ng.debug"

        /// The Keychain service the credential encryption key is stored under.
        public static let keychainService = "\(bundleIdentifier).credentials"

        /// The debug profile named by the `CHIAKI_NG_DEBUG_PROFILE` environment variable, or `nil` when it is
        /// unset or not made only of ASCII letters and digits.
        public static let debugProfile: String? = ProcessInfo.processInfo
            .environment["CHIAKI_NG_DEBUG_PROFILE"]
            .flatMap { name in
                !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
                    ? name.lowercased()
                    : nil
            }
    #elseif CHIAKI_APP_STORE
        /// The bundle identifier of the App Store and TestFlight build, also the name of its sandbox container.
        public static let bundleIdentifier = "io.github.chiaki-ng.chiaki-ng.appstore"

        /// The Keychain service the credential encryption key is stored under.
        public static let keychainService = "io.github.chiaki-ng.chiaki-ng.appstore.credentials"
    #else
        /// The bundle identifier of the application, also the folder name under Application Support, Logs and
        /// Caches.
        public static let bundleIdentifier = "io.github.chiaki-ng.chiaki-ng"

        /// The Keychain service the credential encryption key is stored under.
        public static let keychainService = "io.github.chiaki-ng.chiaki-ng.credentials"
    #endif
}
