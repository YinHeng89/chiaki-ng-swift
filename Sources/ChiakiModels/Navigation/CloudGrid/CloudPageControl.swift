import Foundation

/// The page bar: whether it is open, dragged to a page or typed into.
///
/// The bar opens while the pointer is over it or it holds focus, and settles back once neither does and no
/// drag or typing is under way.
public struct CloudPageControl: Equatable, Sendable {
    /// Where the bar is.
    public enum Phase: Equatable, Sendable {
        /// Folded to its dots.
        case resting
        /// Opened by the pointer or focus.
        case open
        /// Dragged to this page.
        case dragging(Int)
        /// A page number is being typed.
        case typing(String)
    }

    /// What happened to the bar.
    public enum Event: Equatable, Sendable {
        /// The pointer entered or left it.
        case pointer(Bool)
        /// It took or lost focus.
        case focus(Bool)
        /// It was dragged to this page.
        case dragged(Int)
        /// The drag ended.
        case released
        /// Typing a page number started.
        case startTyping
        /// The typed text changed.
        case typed(String)
        /// The typed number was confirmed.
        case commit
        /// The drag or typing was cancelled.
        case cancel
    }

    private struct Attention: OptionSet, Equatable, Sendable {
        let rawValue: Int
        static let pointer = Attention(rawValue: 1)
        static let focus = Attention(rawValue: 2)
    }

    /// Where the bar is.
    public private(set) var phase = Phase.resting
    private var attention: Attention = []

    /// Creates a resting bar.
    public init() {
    }

    /// Whether the bar is unfolded.
    public var isOpen: Bool {
        phase != .resting
    }

    /// The text being typed, if any.
    public var typed: String? {
        guard case .typing(let text) = phase else {
            return nil
        }
        return text
    }

    /// The page the bar shows: the dragged page while dragging, the current page otherwise.
    ///
    /// - Parameter current: The page the grid shows.
    /// - Returns: The page to highlight.
    public func shownPage(current: Int) -> Int {
        guard case .dragging(let page) = phase else {
            return current
        }
        return page
    }

    /// Moves the bar for an event.
    ///
    /// - Parameters:
    ///   - event: What happened.
    ///   - pageCount: The pages in the listing; a single page keeps the bar resting.
    /// - Returns: The page to show when the event chose one.
    public mutating func handle(_ event: Event, pageCount: Int) -> Int? {
        guard pageCount > 1 else {
            phase = .resting
            attention = []
            return nil
        }
        switch event {
        case .pointer(let inside):
            attend(.pointer, inside)
        case .focus(let focused):
            attend(.focus, focused)
        case .dragged(let page):
            phase = .dragging(min(max(0, page), pageCount - 1))
        case .released:
            guard case .dragging(let page) = phase else {
                return nil
            }
            settle()
            return page
        case .startTyping:
            phase = .typing("")
        case .typed(let text):
            guard case .typing = phase else {
                return nil
            }
            phase = .typing(text)
        case .commit:
            guard case .typing(let text) = phase else {
                return nil
            }
            settle()
            return CloudPageJump.page(typed: text, count: pageCount)
        case .cancel:
            settle()
        }
        return nil
    }

    private mutating func attend(_ kind: Attention, _ present: Bool) {
        if present {
            attention.insert(kind)
        } else {
            attention.remove(kind)
        }
        switch phase {
        case .resting, .open:
            settle()
        case .dragging, .typing:
            break
        }
    }

    private mutating func settle() {
        phase = attention.isEmpty
            ? .resting
            : .open
    }
}

/// Reads a page number typed into the page bar.
public enum CloudPageJump {
    /// The page a typed number asks for.
    ///
    /// - Parameters:
    ///   - text: The typed text.
    ///   - count: The pages in the listing.
    /// - Returns: The zero-based page, clamped to the listing, or `nil` when the text is not a number.
    public static func page(typed text: String, count: Int) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard count > 0, !trimmed.isEmpty else {
            return nil
        }
        if let number = Int(trimmed) {
            return min(max(1, number), count) - 1
        }
        return trimmed.allSatisfy(\.isWholeNumber)
            ? count - 1
            : nil
    }
}
