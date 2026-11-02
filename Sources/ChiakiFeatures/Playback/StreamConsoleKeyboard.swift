import ChiakiModels
import PlatformUI
import DesignSystem
import SwiftUI
import MenuFocus

/// An invisible view that keeps a controller keyboard sheet in step with the console's on screen keyboard
/// request, presenting, updating and closing it on the host window.
public struct StreamConsoleKeyboard: View {
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.controllerPromptGlyphs) private var glyphs
    /// The title shown on the controller keyboard sheet.
    public static let title = "Console text"

    /// The console keyboard request to mirror, or `nil` when the console has no keyboard open.
    public let session: ConsoleKeyboardSession?
    /// Receives each text edit together with the identifier of the session it belongs to.
    public let edited: @MainActor (UUID, String) -> Void
    /// Receives whether the text was accepted when the sheet closes, together with the session identifier.
    public let finished: @MainActor (UUID, Bool) -> Void

    /// Creates a stream console keyboard.
    ///
    /// - Parameters:
    ///   - session: The console keyboard request to mirror, or `nil` when the console has no keyboard open.
    ///   - edited: Receives each text edit together with the identifier of the session it belongs to.
    ///   - finished: Receives whether the text was accepted when the sheet closes, together with the session
    ///     identifier.
    public init(
        session: ConsoleKeyboardSession?,
        edited: @escaping @MainActor (UUID, String) -> Void,
        finished: @escaping @MainActor (UUID, Bool) -> Void
    ) {
        self.session = session
        self.edited = edited
        self.finished = finished
    }

    @State private var presenter = StreamConsoleKeyboardPresenter()

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .background(WindowAccessor { window in
                guard presenter.window !== window else {
                    return
                }
                presenter.window = window
                sync()
            })
            .onAppear {
                sync()
            }
            .onChange(of: session) {
                sync()
            }
            .onDisappear {
                presenter.abandon()
            }
    }

    private func sync() {
        presenter.navigator = navigator
        presenter.glyphs = glyphs
        presenter.sync(session, edited: edited, finished: finished)
    }
}

/// Owns the controller keyboard sheet for a console keyboard session, retrying presentation until the window
/// can show it and blocking other menu input while it is up.
@MainActor public final class StreamConsoleKeyboardPresenter {
    private struct Presented {
        let id: UUID
        let handle: ControllerKeyboardSheet.Handle
        let gate: UUID
        let finished: @MainActor (UUID, Bool) -> Void
    }

    /// The window the sheet is presented on.
    public weak var window: PlatformWindow?
    /// The menu navigator whose input gate is held while the sheet is presented.
    public weak var navigator: PlatformMenuNavigator?
    /// Resolves the controller glyphs shown in the sheet's prompts.
    public var glyphs: ControllerGlyphResolver?
    private var presented: Presented?
    private var retry: Task<Void, Never>?

    /// Presents, updates or closes the sheet to match a session, retrying after half a second when the window
    /// cannot present it yet.
    /// - Parameters:
    ///   - session: The console keyboard session to mirror, or `nil` to close the sheet.
    ///   - edited: Receives each text edit with the session identifier.
    ///   - finished: Receives whether the text was accepted when the sheet is dismissed or interrupted.
    public func sync(
        _ session: ConsoleKeyboardSession?,
        edited: @escaping @MainActor (UUID, String) -> Void,
        finished: @escaping @MainActor (UUID, Bool) -> Void
    ) {
        retry?.cancel()
        retry = nil
        guard let session else {
            close()
            return
        }
        if let presented, presented.id == session.id, presented.handle.isPresented {
            presented.handle.setText(session.text)
            return
        }
        close()
        guard let window else {
            return
        }
        let id = session.id
        let gate = UUID()
        let handle = ControllerKeyboardSheet.present(
            in: window,
            navigator: navigator,
            glyphs: glyphs,
            request: ControllerKeyboardSheet.Request(
                title: StreamConsoleKeyboard.title,
                text: session.text,
                secure: false
            ),
            update: { text in
                edited(id, text)
            },
            dismissed: { [weak self] advance in
                self?.finish(id, accepted: advance)
            },
            interrupted: { [weak self] in
                self?.finish(id, accepted: false)
            }
        )
        guard let handle else {
            retry = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else {
                    return
                }
                self?.sync(session, edited: edited, finished: finished)
            }
            return
        }
        navigator?.inputGate.presentations.insert(gate)
        presented = Presented(id: id, handle: handle, gate: gate, finished: finished)
    }

    /// Cancels any pending retry and closes the presented sheet without reporting a result.
    public func close() {
        retry?.cancel()
        retry = nil
        guard let presented else {
            return
        }
        self.presented = nil
        navigator?.inputGate.presentations.remove(presented.gate)
        presented.handle.close()
    }

    /// Closes the sheet and reports the presented session as not accepted, for when the view goes away.
    public func abandon() {
        guard let presented else {
            close()
            return
        }
        close()
        presented.finished(presented.id, false)
    }

    private func finish(_ id: UUID, accepted: Bool) {
        guard let presented, presented.id == id else {
            return
        }
        self.presented = nil
        navigator?.inputGate.presentations.remove(presented.gate)
        presented.finished(id, accepted)
    }
}
