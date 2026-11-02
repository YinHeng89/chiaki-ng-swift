import Foundation

/// Builds the version label the app shows from the bundle's version, release tag and commit.
public enum AppVersion {
    /// The version shown when the bundle has no usable short version string.
    public static let fallback = "2.0.0"
    /// The Info.plist key that carries the release tag appended after the version.
    public static let tagKey = "ChiakiVersionTag"
    /// The Info.plist key that carries the commit shown in parentheses after the version.
    public static let commitKey = "ChiakiCommit"

    /// Formats a version label such as `v2.0.0-beta (abc123)`, leaving out empty parts.
    /// - Parameters:
    ///   - version: The short version string, or `nil` or empty to use ``AppVersion/fallback``.
    ///   - tag: A release tag appended after a hyphen when present.
    ///   - commit: A commit identifier appended in parentheses when present.
    /// - Returns: The formatted label.
    public static func display(version: String?, tag: String?, commit: String? = nil) -> String {
        let resolved = version.flatMap { value in
            value.isEmpty
                ? nil
                : value
        } ?? fallback
        var label = "v\(resolved)"
        if let tag, !tag.isEmpty {
            label += "-\(tag)"
        }
        if let commit, !commit.isEmpty {
            label += " (\(commit))"
        }
        return label
    }

    /// Formats the version label from the values stored in a bundle's Info.plist.
    /// - Parameter bundle: The bundle to read, the main bundle by default.
    /// - Returns: The formatted label.
    public static func display(bundle: Bundle = .main) -> String {
        display(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            tag: bundle.object(forInfoDictionaryKey: tagKey) as? String,
            commit: bundle.object(forInfoDictionaryKey: commitKey) as? String
        )
    }
}
