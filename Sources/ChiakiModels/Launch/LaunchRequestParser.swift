import Foundation

/// Reads launch requests from command-line arguments and `chiaki-ng://stream/<console>` URLs.
public enum LaunchRequestParser {
    /// The URL scheme the app handles.
    public static let scheme = "chiaki-ng"

    private enum Command: Equatable {
        case list
        case stream(String)
    }

    private struct Options {
        var commands: [Command] = []
        var displays: [VideoFitMode] = []
        var remote = false
        var exit = LaunchStreamExit.stayOpen
        var missingConsole = false
    }

    /// Reads the launch arguments.
    ///
    /// - Parameter arguments: The arguments after the executable path.
    /// - Returns: The request, or `nil` when the arguments ask for nothing special.
    /// - Throws: ``LaunchRequestError`` when the arguments conflict or are incomplete.
    public static func parse(arguments: [String]) throws(LaunchRequestError) -> LaunchRequest? {
        let options = scan(arguments)
        if options.missingConsole {
            throw .missingConsole
        }
        guard options.commands.count <= 1 else {
            throw .conflictingCommands
        }
        guard options.displays.count <= 1 else {
            throw .conflictingDisplayModes
        }
        switch options.commands.first {
        case .list:
            return .list
        case .stream(let name):
            return .stream(LaunchStream(
                console: LaunchConsoleReference(name),
                route: options.remote
                    ? .remote
                    : .local,
                display: options.displays.first.map(LaunchDisplay.fullscreen) ?? .window,
                exit: options.exit
            ))
        case nil:
            if let display = options.displays.first {
                throw .streamOptionWithoutStream(flag(for: display))
            }
            if options.remote {
                throw .streamOptionWithoutStream("--remote")
            }
            return options.exit == .quitApp
                ? .session(.quitApp)
                : nil
        }
    }

    private static func scan(_ arguments: [String]) -> Options {
        var options = Options()
        var index = scanPositional(arguments, into: &options)
        while index < arguments.endIndex {
            let argument = arguments[index]
            index += 1
            if argument == "--stream" {
                if let name = consoleName(arguments, at: index) {
                    options.commands.append(.stream(name))
                    index += 1
                } else {
                    options.missingConsole = true
                }
            } else {
                scanFlag(argument, into: &options)
            }
        }
        return options
    }

    private static func scanPositional(_ arguments: [String], into options: inout Options) -> Int {
        guard let first = arguments.first else {
            return arguments.startIndex
        }
        switch first {
        case "list":
            options.commands.append(.list)
            return arguments.startIndex + 1
        case "stream":
            let index = arguments.startIndex + 1
            guard let name = consoleName(arguments, at: index) else {
                options.missingConsole = true
                return index
            }
            options.commands.append(.stream(name))
            return index + 1
        default:
            return arguments.startIndex
        }
    }

    private static func scanFlag(_ argument: String, into options: inout Options) {
        switch argument {
        case "--list":
            options.commands.append(.list)
        case "--fullscreen":
            options.displays.append(.fit)
        case "--zoom":
            options.displays.append(.zoom)
        case "--stretch":
            options.displays.append(.stretch)
        case "--remote":
            options.remote = true
        case "--exit-app-on-stream-exit":
            options.exit = .quitApp
        default:
            guard argument.hasPrefix("--stream=") else {
                return
            }
            let name = String(argument.dropFirst("--stream=".count))
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                options.missingConsole = true
            } else {
                options.commands.append(.stream(name))
            }
        }
    }

    private static func consoleName(_ arguments: [String], at index: Int) -> String? {
        guard index < arguments.endIndex else {
            return nil
        }
        let value = arguments[index]
        guard !value.hasPrefix("-"), !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return value
    }

    private static func flag(for mode: VideoFitMode) -> String {
        switch mode {
        case .fit:
            "--fullscreen"
        case .zoom:
            "--zoom"
        case .stretch:
            "--stretch"
        }
    }

    /// Reads a stream URL such as `chiaki-ng://stream/Living%20Room?mode=zoom&exit=1&route=remote`.
    ///
    /// - Parameter url: The URL the app was opened with.
    /// - Returns: A stream request.
    /// - Throws: ``LaunchRequestError`` for an unsupported URL, a missing console or an unknown option value.
    public static func parse(url: URL) throws(LaunchRequestError) -> LaunchRequest {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == "stream"
        else {
            throw .unsupportedURL(url.absoluteString)
        }
        let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 1,
              let console = String(segments[0]).removingPercentEncoding,
              !console.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            throw .missingConsole
        }
        var stream = LaunchStream(console: LaunchConsoleReference(console))
        for item in components.queryItems ?? [] {
            let value = (item.value ?? "").lowercased()
            switch item.name.lowercased() {
            case "mode":
                stream.display = try display(value)
            case "exit":
                stream.exit = try exit(value)
            case "route":
                stream.route = try route(value)
            default:
                continue
            }
        }
        return .stream(stream)
    }

    private static func display(_ value: String) throws(LaunchRequestError) -> LaunchDisplay {
        switch value {
        case "window", "windowed":
            .window
        case "fullscreen", "fit":
            .fullscreen(.fit)
        case "zoom":
            .fullscreen(.zoom)
        case "stretch":
            .fullscreen(.stretch)
        default:
            throw .unknownMode(value)
        }
    }

    private static func exit(_ value: String) throws(LaunchRequestError) -> LaunchStreamExit {
        switch value {
        case "1", "true", "yes":
            .quitApp
        case "0", "false", "no":
            .stayOpen
        default:
            throw .unknownExitValue(value)
        }
    }

    private static func route(_ value: String) throws(LaunchRequestError) -> LaunchRoute {
        switch value {
        case "local":
            .local
        case "remote":
            .remote
        default:
            throw .unknownRoute(value)
        }
    }
}

/// Why launch arguments or a launch URL were refused.
public enum LaunchRequestError: Error, Equatable, Sendable {
    /// No console was named.
    case missingConsole

    /// Both listing and streaming were asked for.
    case conflictingCommands

    /// More than one display mode was given.
    case conflictingDisplayModes

    /// A stream option was given without a stream; the text is the option.
    case streamOptionWithoutStream(String)

    /// The URL is not a supported stream URL; the text is the URL.
    case unsupportedURL(String)

    /// The display mode is unknown; the text is the mode.
    case unknownMode(String)

    /// The route is unknown; the text is the route.
    case unknownRoute(String)

    /// The exit value is unknown; the text is the value.
    case unknownExitValue(String)

    /// The explanation printed for the user.
    public var message: String {
        switch self {
        case .missingConsole:
            "Name the console to stream, for example --stream \"Living Room\"."
        case .conflictingCommands:
            "Choose either --list or --stream, not both."
        case .conflictingDisplayModes:
            "Choose only one of --fullscreen, --zoom or --stretch."
        case .streamOptionWithoutStream(let option):
            "\(option) only applies together with --stream."
        case .unsupportedURL(let url):
            "chiaki-ng can’t open \(url). Use chiaki-ng://stream/<console>."
        case .unknownMode(let mode):
            "Unknown display mode \"\(mode)\". Use window, fullscreen, zoom or stretch."
        case .unknownRoute(let route):
            "Unknown route \"\(route)\". Use local or remote."
        case .unknownExitValue(let value):
            "Unknown exit value \"\(value)\". Use 1 or 0."
        }
    }
}
