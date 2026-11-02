import Foundation

/// What the app was asked to do at launch.
public enum LaunchRequest: Equatable, Sendable {
    /// Print the known consoles.
    case list

    /// Stream a console.
    case stream(LaunchStream)

    /// Run normally, with the given behaviour when a stream ends.
    case session(LaunchStreamExit)
}

/// A request to stream one console from the command line or a URL.
public struct LaunchStream: Equatable, Sendable {
    /// The console to stream.
    public var console: LaunchConsoleReference

    /// The route to it.
    public var route: LaunchRoute

    /// How the stream is displayed.
    public var display: LaunchDisplay

    /// What happens when the stream ends.
    public var exit: LaunchStreamExit

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - route: The route.
    ///   - display: The display.
    ///   - exit: What happens at the end.
    public init(
        console: LaunchConsoleReference,
        route: LaunchRoute = .local,
        display: LaunchDisplay = .window,
        exit: LaunchStreamExit = .stayOpen
    ) {
        self.console = console
        self.route = route
        self.display = display
        self.exit = exit
    }
}

/// What the app does when a launched stream ends.
public enum LaunchStreamExit: Equatable, Sendable {
    /// Keep the app open.
    case stayOpen

    /// Quit the app.
    case quitApp
}

/// Whether a launched stream reaches the console locally or over the internet.
public enum LaunchRoute: Equatable, Sendable {
    /// On the local network.
    case local

    /// Over the internet.
    case remote
}

/// How a launch request names the console to stream: by its stored id or by name.
public enum LaunchConsoleReference: Equatable, Sendable {
    /// The console's stored id.
    case id(UUID)

    /// The console's name.
    case name(String)

    /// Reads a reference, treating a UUID as an id and anything else as a name.
    ///
    /// - Parameter value: The text from the command line or URL.
    public init(_ value: String) {
        if let id = UUID(uuidString: value) {
            self = .id(id)
        } else {
            self = .name(value)
        }
    }

    /// The reference as text.
    public var description: String {
        switch self {
        case .id(let id):
            id.uuidString
        case .name(let name):
            name
        }
    }
}

/// How a launched stream is displayed.
public enum LaunchDisplay: Equatable, Sendable {
    /// In a window.
    case window

    /// Full screen with the given fit.
    case fullscreen(VideoFitMode)

    /// The fit a full-screen launch overrides, or `nil` for a window.
    public var videoFit: VideoFit? {
        switch self {
        case .window:
            nil
        case .fullscreen(let mode):
            VideoFit(mode: mode)
        }
    }
}
