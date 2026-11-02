import SwiftUI

/// A single line of text that scrolls sideways to reveal its end when it does not fit.
///
/// The text truncates at rest. When ``Trigger`` allows it, the full text scrolls left in one direction
/// only, followed by a second copy so the loop wraps without jumping back; each pass pauses briefly at
/// the start. Scrolling stops under Reduce Motion and while the scene is inactive.
public struct ScrollingText: View {
    /// When the text starts scrolling.
    public enum Trigger: Sendable {
        /// While the pointer hovers over the text.
        case hover
        /// As soon as the text appears.
        case always
    }

    private let text: String
    private let font: Font
    private let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var textWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var started: Date?

    /// Creates a scrolling line of text.
    ///
    /// - Parameters:
    ///   - text: The text to show.
    ///   - font: The font of the text.
    ///   - trigger: When the text starts scrolling.
    public init(text: String, font: Font = .system(size: 16, weight: .regular), trigger: Trigger = .hover) {
        self.text = text
        self.font = font
        self.trigger = trigger
    }

    private var scrolling: Bool {
        started != nil && textWidth > viewportWidth && !reduceMotion && scenePhase == .active
    }

    /// The truncated text with the scrolling copy layered over it.
    public var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(
                scrolling
                    ? 0
                    : 1
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                viewportWidth = width
            }
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !scrolling)) { context in
                    HStack(spacing: Self.gap) {
                        Text(text)
                            .font(font)
                            .fixedSize(horizontal: true, vertical: false)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.width
                            } action: { width in
                                textWidth = width
                            }
                        Text(text)
                            .font(font)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset(at: context.date))
                    .opacity(
                        scrolling
                            ? 1
                            : 0
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .clipped()
            .contentShape(.rect)
            .onHover { hovering in
                guard trigger == .hover else {
                    return
                }
                started = hovering
                    ? .now
                    : nil
            }
            .onAppear {
                if trigger == .always {
                    started = .now
                }
            }
            .onChange(of: text) {
                if trigger == .hover {
                    started = nil
                }
            }
            .help(text)
            .accessibilityLabel(text)
    }

    private static let gap: CGFloat = 40
    private static let speed: CGFloat = 32
    private static let pause: Double = 0.8

    private func offset(at date: Date) -> CGFloat {
        guard scrolling, let started else {
            return 0
        }
        let distance = textWidth + Self.gap
        let pass = Self.pause + Double(distance / Self.speed)
        let elapsed = max(0, date.timeIntervalSince(started)).truncatingRemainder(dividingBy: pass)
        return -min(distance, CGFloat(max(0, elapsed - Self.pause)) * Self.speed)
    }
}
