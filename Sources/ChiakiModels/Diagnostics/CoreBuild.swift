/// The version and source commit the linked core was built as.
public struct CoreBuild: Hashable, Sendable {
    /// The core's version, such as `2.0.0` or `2.0.0-rc1`.
    public let version: String

    /// The abbreviated commit the core was built from, or empty when the build did not record one.
    public let commit: String

    /// Describes a build.
    ///
    /// - Parameters:
    ///   - version: The core's version.
    ///   - commit: The abbreviated commit, or empty.
    public init(version: String, commit: String) {
        self.version = version
        self.commit = commit
    }
}
