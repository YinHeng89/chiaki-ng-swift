import Foundation

/// The `--user-data <dir>` launch option, read before anything opens the database.
///
/// The option points ``UserData/support`` at another folder, which then holds the database and the
/// `Catalog` folder; logs, caches and the Keychain key stay where ``UserData/live(in:)`` puts them. The
/// remaining arguments are what the launch request parser reads.
public struct UserDataArgument: Equatable, Sendable {
    /// Why the option could not be read.
    public enum Failure: Error, Equatable, Sendable {
        /// The option was given without a folder.
        case missingDirectory

        /// The option was given more than once.
        case repeated
    }

    /// The option's spelling.
    public static let flag = "--user-data"

    /// The folder the option names, or `nil` when it was not given.
    public let directory: URL?

    /// The arguments with the option and its folder removed, executable path first.
    public let remaining: [String]

    /// Reads the option from a process's arguments.
    ///
    /// Both `--user-data <dir>` and `--user-data=<dir>` are accepted. A relative folder is resolved against
    /// the current directory and a leading `~` is expanded.
    ///
    /// - Parameter arguments: The process arguments, executable path first.
    /// - Throws: ``Failure/missingDirectory`` when no folder follows the option, or ``Failure/repeated``
    ///   when it is given twice.
    public init(arguments: [String]) throws(Failure) {
        var directory: URL?
        var remaining: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            index += 1
            let path: String
            if argument == Self.flag {
                guard index < arguments.endIndex, !arguments[index].isEmpty else {
                    throw .missingDirectory
                }
                path = arguments[index]
                index += 1
            } else if argument.hasPrefix(Self.flag + "=") {
                path = String(argument.dropFirst(Self.flag.count + 1))
                guard !path.isEmpty else {
                    throw .missingDirectory
                }
            } else {
                remaining.append(argument)
                continue
            }
            guard directory == nil else {
                throw .repeated
            }
            directory = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        self.directory = directory
        self.remaining = remaining
    }

    /// The location this launch uses.
    ///
    /// - Parameter process: The process asking.
    /// - Returns: ``UserData/directory(_:in:)`` for the named folder, or ``UserData/live(in:)`` without one.
    /// - Throws: The error ``UserData/live(in:)`` throws.
    public func location(in process: HostProcess = .current) throws -> UserData {
        if let directory {
            return try UserData.directory(directory, in: process)
        }
        return try UserData.live(in: process)
    }
}
