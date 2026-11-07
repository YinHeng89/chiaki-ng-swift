import DesignSystem
import Observation
import PlatformUI
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Presents the on-screen keyboard as a sheet over a window from code that is not a SwiftUI view, such as
/// the stream's keyboard for the console.
///
/// The sheet is hosted outside the presenting view tree, so the caller passes the navigator and the
/// controller glyphs it should use.
@MainActor
public enum ControllerKeyboardSheet {
    /// What the keyboard edits.
    public struct Request: Sendable {
        /// The title for a field that has no label of its own.
        public static let untitledTitle: LocalizedStringResource = .keyboardUntitledField

        /// The keyboard's title.
        public let title: LocalizedStringResource

        /// The starting text.
        public let text: String

        /// Whether the text is hidden.
        public let secure: Bool

        /// Creates a request.
        ///
        /// - Parameters:
        ///   - title: The keyboard's title.
        ///   - text: The starting text.
        ///   - secure: Whether the text is hidden.
        public init(title: LocalizedStringResource, text: String, secure: Bool) {
            self.title = title
            self.text = text
            self.secure = secure
        }
    }

    /// A presented keyboard sheet.
    @MainActor
    public final class Handle {
        fileprivate let model: KeyboardText
        fileprivate let sheetReference: SheetReference
        fileprivate weak var parent: PlatformWindow?

        fileprivate init(model: KeyboardText, sheetReference: SheetReference, parent: PlatformWindow) {
            self.model = model
            self.sheetReference = sheetReference
            self.parent = parent
        }

        /// Whether the sheet is still shown.
        public var isPresented: Bool {
            sheetReference.presented != nil
        }

        /// The text typed so far.
        public var text: String {
            model.text
        }

        /// Replaces the text, for example when the console changes it.
        ///
        /// - Parameter text: The new text.
        public func setText(_ text: String) {
            guard model.text != text else {
                return
            }
            model.text = text
        }

        /// Closes the sheet without calling its dismissal handler.
        public func close() {
            if !sheetReference.end(in: parent) {
                sheetReference.presented = nil
            }
        }
    }

    /// Presents the keyboard over a window.
    ///
    /// - Parameters:
    ///   - window: The window to present over.
    ///   - navigator: The app's navigator, published to the keyboard.
    ///   - glyphs: The controller glyphs for the keyboard's hints.
    ///   - request: What the keyboard edits.
    ///   - update: Receives every change to the text.
    ///   - dismissed: Runs when the user closes the keyboard; receives whether Done was chosen.
    ///   - interrupted: Runs when the system closes the sheet without the user.
    /// - Returns: The presented sheet, or `nil` when the window cannot present one now.
    @discardableResult
    public static func present(
        in window: PlatformWindow,
        navigator: PlatformMenuNavigator?,
        glyphs: ControllerGlyphResolver? = nil,
        request: Request,
        update: @escaping (String) -> Void,
        dismissed: @escaping (Bool) -> Void,
        interrupted: (() -> Void)? = nil
    ) -> Handle? {
        guard SheetReference.canBegin(in: window) else {
            return nil
        }
        let sheetReference = SheetReference()
        let model = KeyboardText(text: request.text)
        let content = HostedControllerKeyboard(
            title: request.title,
            model: model,
            secure: request.secure,
            sourceWindow: window,
            navigator: navigator,
            glyphs: glyphs,
            update: update,
            dismiss: { advance in
                guard sheetReference.end(in: window) else {
                    return
                }
                dismissed(advance)
            }
        )
        sheetReference.begin(content, in: window) {
            interrupted?()
        }
        return Handle(model: model, sheetReference: sheetReference, parent: window)
    }

    #if os(macOS)
        @MainActor
        fileprivate final class SheetReference {
            var presented: PlatformWindow?

            static func canBegin(in window: PlatformWindow) -> Bool {
                window.attachedSheet == nil
            }

            func begin(
                _ content: HostedControllerKeyboard,
                in window: PlatformWindow,
                interrupted: @escaping () -> Void
            ) {
                let host = NSHostingController(rootView: content)
                host.sizingOptions = .preferredContentSize
                let sheet = PlatformWindow(contentViewController: host)
                sheet.isReleasedWhenClosed = false
                presented = sheet
                window.beginSheet(sheet) { [self] _ in
                    guard presented != nil else {
                        return
                    }
                    presented = nil
                    interrupted()
                }
            }

            func end(in parent: PlatformWindow?) -> Bool {
                guard let sheet = presented, let parent, sheet.sheetParent === parent else {
                    return false
                }
                presented = nil
                parent.endSheet(sheet)
                return true
            }
        }
    #else
        @MainActor
        fileprivate final class SheetReference {
            var presented: UIViewController?

            static func canBegin(in window: PlatformWindow) -> Bool {
                guard let presenter = WindowFocus(window).topPresentedController else {
                    return false
                }
                return !presenter.isBeingDismissed && !(presenter is KeyboardHost)
            }

            func begin(
                _ content: HostedControllerKeyboard,
                in window: PlatformWindow,
                interrupted: @escaping () -> Void
            ) {
                let host = KeyboardHost(rootView: content)
                host.sizingOptions = .preferredContentSize
                host.modalPresentationStyle = .formSheet
                host.ended = { [self] in
                    guard presented != nil else {
                        return
                    }
                    presented = nil
                    interrupted()
                }
                presented = host
                WindowFocus(window).topPresentedController?.present(
                    host,
                    animated: !UIAccessibility.isReduceMotionEnabled
                )
            }

            func end(in parent: PlatformWindow?) -> Bool {
                guard let sheet = presented, sheet.presentingViewController != nil else {
                    return false
                }
                presented = nil
                sheet.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
                return true
            }
        }

        fileprivate final class KeyboardHost: UIHostingController<HostedControllerKeyboard> {
            var ended: () -> Void = {
            }

            override func viewDidDisappear(_ animated: Bool) {
                super.viewDidDisappear(animated)
                if isBeingDismissed {
                    ended()
                }
            }
        }
    #endif

    /// The text shared between a presented keyboard and its ``Handle``.
    @MainActor
    @Observable
    final class KeyboardText {
        /// The text typed so far.
        var text: String

        /// Creates the shared text.
        ///
        /// - Parameter text: The starting text.
        init(text: String) {
            self.text = text
        }
    }
}

/// The root view of a ``ControllerKeyboardSheet``: the keyboard with the environment its sheet window does
/// not inherit.
private struct HostedControllerKeyboard: View {
    /// The keyboard's title.
    let title: LocalizedStringResource

    /// The text shared with the sheet's handle.
    @Bindable var model: ControllerKeyboardSheet.KeyboardText

    /// Whether the text is hidden.
    let secure: Bool

    /// The window the keyboard covers.
    let sourceWindow: PlatformWindow

    /// The app's navigator.
    let navigator: PlatformMenuNavigator?

    /// The controller glyphs for the hints.
    let glyphs: ControllerGlyphResolver?

    /// Receives every change to the text.
    let update: (String) -> Void

    /// Closes the sheet; receives whether Done was chosen.
    let dismiss: (Bool) -> Void

    /// The keyboard, wired to the navigator and glyphs.
    var body: some View {
        keyboard
            .environment(\.controllerPromptGlyphs, glyphs)
            .onChange(of: model.text) { _, value in
                update(value)
            }
    }

    @ViewBuilder private var keyboard: some View {
        let content = ControllerOnScreenKeyboard(
            title: title,
            text: $model.text,
            secure: secure,
            numberPad: false,
            allowsNewline: false,
            sourceWindow: sourceWindow,
            dismiss: dismiss
        )
        .environment(\.settingsMenuFocus, false)
        if let navigator {
            content.menuNavigator(navigator)
        } else {
            content
        }
    }
}
