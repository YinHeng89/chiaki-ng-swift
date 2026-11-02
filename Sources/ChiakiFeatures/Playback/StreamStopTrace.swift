import ChiakiClients
import Dependencies
import ChiakiDiagnostics
import PlatformUI
import MenuFocus
import Foundation
import SwiftUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Logs diagnostic lines describing what asked a stream to stop, including the input event or controller
/// command behind it.
///
/// Views read one from the environment, where it carries the window's menu navigator, the controller
/// driving menus and the diagnostic log.
struct StreamStopTrace {
    /// The kind of stream whose stop is being traced, which picks the log area and the wording.
    enum Stream {
        /// A local console stream or a cloud stream.
        case console, cloud

        /// The log area the stream's stop messages are written to.
        var area: LogArea {
            switch self {
            case .console:
                .playback
            case .cloud:
                .cloud
            }
        }

        /// The capitalised stream kind used at the start of each log message.
        var title: String {
            switch self {
            case .console:
                "Console"
            case .cloud:
                "Cloud"
            }
        }
    }

    /// The controller driving menus, whose recent commands explain a stop.
    let navigation: (any ControllerNavigation)?

    /// The menu navigator, which tells controller-made events from the user's own.
    let navigator: PlatformMenuNavigator?

    /// The diagnostic log the stop lines are written to.
    let logger: LoggerClient

    /// Logs that a stop of the stream was requested, naming the source and the input that triggered it.
    /// - Parameters:
    ///   - stream: The kind of stream being stopped.
    ///   - source: A short description of the control or path that asked for the stop.
    @MainActor func record(_ stream: Stream, _ source: String) {
        let message = "\(stream.title) stream stop requested by \(source); trigger: \(trigger())"
        logger.enqueue(.diagnostic(stream.area, .info, message))
    }

    /// Logs that a stop of the stream was confirmed, naming the source and the input that triggered it.
    /// - Parameters:
    ///   - stream: The kind of stream being stopped.
    ///   - source: A short description of the confirmation that completed the stop.
    @MainActor func confirm(_ stream: Stream, _ source: String) {
        let message = "\(stream.title) stream stop confirmed after \(source); trigger: \(trigger())"
        logger.enqueue(.diagnostic(stream.area, .info, message))
    }

    /// Describes the current input that led to the stop: the current AppKit event on macOS and any controller
    /// command from the last 1.5 seconds, joined by semicolons.
    @MainActor func trigger() -> String {
        var parts = [String]()
        #if os(macOS)
            if let event = NSApp.currentEvent {
                parts.append(describe(event))
            } else {
                parts.append("no input event")
            }
        #endif
        if let command = navigation?.recentCommand(within: 1.5) {
            parts.append(command)
        }
        return parts.joined(separator: "; ")
    }

    #if os(macOS)
        @MainActor private func describe(_ event: NSEvent) -> String {
            let synthetic = navigator?.isControllerEvent(event) == true
                ? "controller navigation "
                : ""
            switch event.type {
            case .keyDown, .keyUp:
                return "\(synthetic)key \(event.keyCode)"
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
                return "mouse button \(event.buttonNumber)"
            default:
                return "\(synthetic)event type \(event.type.rawValue)"
            }
        }
    #endif
}

extension EnvironmentValues {
    /// The stop trace over this environment's menu navigator, the controller driving menus and the log.
    var streamStopTrace: StreamStopTrace {
        StreamStopTrace(navigation: controllerNavigation, navigator: menuNavigator, logger: logger)
    }
}
