import Dependencies
import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import Foundation

/// The process entry point: opens the app's data store, then either runs the app with any launch request from
/// the arguments, prints the registered consoles, or prints an argument error and exits.
@main
@MainActor enum ChiakiNGMain {
    /// Parses the command line and runs the chosen command.
    static func main() {
        let option: UserDataArgument
        do throws(UserDataArgument.Failure) {
            option = try UserDataArgument(arguments: ProcessInfo.processInfo.arguments)
        } catch {
            LaunchCommandLine.printError(LaunchCommandLine.message(for: error))
            exit(1)
        }
        let data: UserData
        do {
            data = try option.location()
        } catch {
            LaunchCommandLine.printError("The app's data location is unavailable.")
            exit(1)
        }
        UserData.install(data)
        let composition = AppComposition.live(data)
        composition.prepare()
        switch LaunchCommandLine.command(from: option.remaining) {
        case .run(let request):
            LaunchCommandLine.pending = request
            ChiakiNGApp.run(composition)
        case .list:
            Task {
                await LaunchCommandLine.list()
                exit(0)
            }
            dispatchMain()
        case .invalid(let message):
            LaunchCommandLine.printError(message)
            exit(1)
        }
    }
}

/// Parses command-line and URL launch requests and prints console listings for the command line.
@MainActor enum LaunchCommandLine {
    /// What the command line asks the process to do.
    enum Command: Equatable {
        /// Run the app, starting the given launch request when there is one.
        case run(LaunchRequest?)
        /// Print the registered consoles and exit.
        case list
        /// Print the message as an error and exit.
        case invalid(String)
    }

    /// The launch request parsed at startup, waiting for the app to take it.
    static var pending: LaunchRequest?

    /// Turns process arguments into a command, skipping the executable path.
    /// - Parameter arguments: The full process arguments.
    /// - Returns: The command to run.
    nonisolated static func command(from arguments: [String]) -> Command {
        do {
            let request = try LaunchRequestParser.parse(arguments: Array(arguments.dropFirst()))
            return request == .list
                ? .list
                : .run(request)
        } catch {
            return .invalid(error.message.english)
        }
    }

    /// Returns the waiting launch request and clears it, so it is handled once.
    static func takePending() -> LaunchRequest? {
        defer {
            pending = nil
        }
        return pending
    }

    /// Parses a launch URL and sends the request, logging a warning when the URL is invalid.
    /// - Parameters:
    ///   - url: The opened URL.
    ///   - send: Receives the parsed request.
    static func open(_ url: URL, send: @MainActor (LaunchRequest) -> Void) {
        do {
            send(try LaunchRequestParser.parse(url: url))
        } catch {
            let message = error.message.english
            @Dependency(\.logger) var logger
            logger.enqueue(.diagnostic(.app, .warning, message))
        }
    }

    /// Formats registered consoles for the terminal, one entry per console with its name, id and address.
    /// - Parameter registrations: The registrations to list; duplicates of the same console are listed once.
    /// - Returns: The listing, or a note that no consoles are registered.
    static func listing(_ registrations: [RegistrationFlow.Registration]) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        for registration in registrations {
            let console = registration.console
            let key = console.id?.uuidString ?? console.address
            guard seen.insert(key).inserted else {
                continue
            }
            lines.append("Host: \(console.name ?? console.address)")
            if let id = console.id {
                lines.append("    id: \(id.uuidString)")
            }
            lines.append("    address: \(console.address)")
        }
        return lines.isEmpty
            ? "No registered consoles."
            : lines.joined(separator: "\n")
    }

    /// Loads the saved consoles and prints them, exiting with an error when they cannot be loaded.
    static func list() async {
        @Dependency(\.consoles) var catalog
        switch await catalog.pairings() {
        case .success(let consoles):
            print(listing(consoles.map(RegistrationFlow.Registration.init)))
        case .failure(let failure):
            printError("Saved consoles could not be loaded: \(LogFormat.error(failure))")
            exit(1)
        }
    }

    /// The line printed when the `--user-data` option cannot be read.
    ///
    /// - Parameter failure: Why it could not be read.
    /// - Returns: The message.
    static func message(for failure: UserDataArgument.Failure) -> String {
        switch failure {
        case .missingDirectory:
            "\(UserDataArgument.flag) needs the folder that holds the database and the Catalog folder."
        case .repeated:
            "\(UserDataArgument.flag) can be given only once."
        }
    }

    /// Writes a line to standard error.
    /// - Parameter message: The text to write.
    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
