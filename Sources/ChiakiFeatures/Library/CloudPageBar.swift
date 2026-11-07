import ChiakiModels
import SwiftUI
import DesignSystem
import MenuFocus

/// The page indicator under the grid: a row of shrinking dots that unfolds into a scrub bar with a page
/// handle while hovered or focused, where pages can be dragged to, tapped or typed.
///
/// On touch, where nothing hovers, the scrub bar stays unfolded so a finger can drag or tap straight to a
/// page.
struct CloudPageBar: View {
    /// The bar's fixed height.
    static let height: CGFloat = 44
    /// The scrub bar's inset from either side.
    static let inset: CGFloat = 60
    /// The curve the dots unfold into the scrub bar along.
    static let fold = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)

    /// The page shown, counted from zero.
    let page: Int
    /// The number of pages.
    let pageCount: Int
    /// The page control's state: whether the bar is open, dragging or taking a typed page.
    let control: CloudPageControl
    /// The library's controller focus, which the handle and the page number field take.
    @MenuFocusState.Binding var focus: CloudLibraryFocus?
    /// Sends pointer, drag, typing and commit events to the page control.
    let send: (CloudPageControl.Event) -> Void
    /// Moves controller focus away from the handle in a direction.
    let move: @MainActor (MenuMoveDirection) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout

    private var open: Bool {
        control.isOpen || !layout.hoverAffordances
    }

    private var shownPage: Int {
        control.shownPage(current: page)
    }

    var body: some View {
        ZStack {
            if pageCount > 1 {
                dots
                    .opacity(open
                        ? 0
                        : 1)
                        .scaleEffect(
                            x: open && !reduceMotion
                                ? 1.6
                                : 1,
                            y: open && !reduceMotion
                                ? 0.6
                                : 1
                        )
                        .allowsHitTesting(!open)
                        .accessibilityHidden(true)
                scrub
                    .padding(.horizontal, Self.inset)
                    .opacity(open
                        ? 1
                        : 0)
                        .scaleEffect(x: open || reduceMotion
                            ? 1
                            : 0.3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .contentShape(.rect)
        .onHover { inside in
            send(.pointer(inside))
        }
        .animation(reduceMotion
            ? .easeInOut(duration: 0.2)
            : Self.fold, value: open)
            .animation(reduceMotion
                ? nil
                : CloudGameGrid.slide, value: page)
    }

    private var dots: some View {
        CloudPageDotStrip(page: page, pageCount: pageCount, height: Self.height) { chosen in
            send(.dragged(chosen))
            send(.released)
        }
    }

    /// How large a page dot is drawn for its distance from the current page.
    ///
    /// - Parameter size: The dot's size class.
    /// - Returns: The dot's scale.
    static func scale(of size: CloudPageDot.Size) -> CGFloat {
        switch size {
        case .now:
            1.15
        case .full:
            1
        case .near:
            0.78
        case .far:
            0.52
        case .edge:
            0.3
        }
    }

    /// How bright a page dot is drawn for its distance from the current page.
    ///
    /// - Parameter size: The dot's size class.
    /// - Returns: The dot's opacity.
    static func opacity(of size: CloudPageDot.Size) -> Double {
        switch size {
        case .now:
            1
        case .full, .near:
            0.34
        case .far:
            0.22
        case .edge:
            0.14
        }
    }

    /// The page under a point on the scrub bar, rounded to the nearest page.
    ///
    /// - Parameters:
    ///   - position: The point's distance from the bar's leading edge.
    ///   - width: The bar's width.
    ///   - count: The number of pages.
    /// - Returns: The page, counted from zero and clamped to the pages that exist.
    static func page(at position: CGFloat, width: CGFloat, count: Int) -> Int {
        guard width > 0, count > 1 else {
            return 0
        }
        let fraction = min(max(0, position / width), 1)
        return Int((fraction * CGFloat(count - 1)).rounded())
    }

    private var scrub: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let position = width * CGFloat(shownPage) / CGFloat(max(1, pageCount - 1))
            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.22), location: 0.06),
                        .init(color: .white.opacity(0.22), location: 0.94),
                        .init(color: .white.opacity(0), location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 2)
                LinearGradient(
                    colors: [Palette.accent.opacity(0), Palette.accent.opacity(0.75)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: position, height: 2)
                handle
                    .fixedSize()
                    .position(x: position, y: Self.height / 2)
            }
            .frame(width: width, height: Self.height)
            .contentShape(.rect)
            .onTapGesture { location in
                send(.dragged(Self.page(at: location.x, width: width, count: pageCount)))
                send(.released)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        send(.dragged(Self.page(at: drag.location.x, width: width, count: pageCount)))
                    }
                    .onEnded { _ in
                        send(.released)
                    }
            )
        }
        .frame(height: Self.height)
    }

    @ViewBuilder private var handle: some View {
        if let typed = control.typed {
            HStack(spacing: 6) {
                CloudPageNumberField(
                    typed: typed, current: page + 1, focus: $focus, send: send
                )
                Text(.libraryPageBarOfTotal(total: pageCount))
                    .foregroundStyle(.secondary)
            }
            .modifier(CloudPageHandle(dragging: false))
        } else {
            FocusButton {
                send(.startTyping)
            } label: {
                HStack(spacing: 6) {
                    Text("\(shownPage + 1)")
                        .fontWeight(.bold)
                    Text(.libraryPageBarOfTotal(total: pageCount))
                        .foregroundStyle(.secondary)
                }
                .modifier(CloudPageHandle(dragging: control.phase == .dragging(shownPage)))
            }
            .buttonStyle(.plain)
            .focusHighlightShape(.capsule)
            .menuFocused($focus, equals: .pageBar)
            .environment(\.menuMove, move)
            .accessibilityLabel(.libraryPageBarPageOfTotal(page: shownPage + 1, total: pageCount))
            .accessibilityIdentifier("cloud-page-bar")
        }
    }
}

/// A row of shrinking page dots, the current page's in the accent colour, each a tap target as tall as the
/// strip that shows its page.
///
/// The dots duplicate what Left and Right already do on the cards, so they are not focus stops.
struct CloudPageDotStrip: View {
    /// The diameter of a dot at full size.
    static let dot: CGFloat = 7
    /// The gap between two dots.
    static let gap: CGFloat = 14

    /// The page shown, counted from zero.
    let page: Int
    /// The number of pages.
    let pageCount: Int
    /// The strip's height, which is each dot's hit height.
    let height: CGFloat
    /// Shows the page a dot stands for.
    let choose: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CloudPageDots.dots(page: page, count: pageCount), id: \.page) { dot in
                Button {
                    choose(dot.page)
                } label: {
                    Circle()
                        .fill(dot.size == .now
                            ? Palette.accent
                            : Color.white.opacity(CloudPageBar.opacity(of: dot.size)))
                            .frame(width: Self.dot, height: Self.dot)
                            .scaleEffect(CloudPageBar.scale(of: dot.size))
                            .frame(width: Self.dot + Self.gap, height: height)
                            .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .menuFocusable(false)
                .focusEffectDisabled()
                .accessibilityLabel(.libraryPageBarPageOfTotal(page: dot.page + 1, total: pageCount))
                .accessibilityAddTraits(dot.size == .now
                    ? .isSelected
                    : [])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityIdentifier("cloud-page-dots")
    }
}

/// Draws the page handle as an interactive glass capsule that grows while it is dragged.
struct CloudPageHandle: ViewModifier {
    /// Whether the handle is being dragged.
    let dragging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Styles the handle's content as the capsule.
    ///
    /// - Parameter content: The handle's label.
    /// - Returns: The styled handle.
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .glassEffect(AppGlass.control.interactive(), in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(dragging && !reduceMotion
                ? 1.1
                : 1)
                .animation(reduceMotion
                    ? nil
                    : .spring(response: 0.22, dampingFraction: 0.6), value: dragging)
    }
}

/// The field for typing a page number, which takes focus when it appears and returns focus to the page bar
/// when the page is committed or cancelled.
struct CloudPageNumberField: View {
    /// The text typed so far.
    let typed: String
    /// The current page as counted from one, shown as the placeholder.
    let current: Int
    /// The library's controller focus.
    @MenuFocusState.Binding var focus: CloudLibraryFocus?
    /// Sends typed text, commit and cancel events to the page control.
    let send: (CloudPageControl.Event) -> Void

    var body: some View {
        let text = Binding(get: { typed }, set: { send(.typed($0)) })
        TextField("\(current)", text: text)
            .textFieldStyle(.plain)
            .fontWeight(.bold)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .foregroundStyle(Palette.accent)
            .menuFocusBinding($focus, equals: .pageNumber)
            .controllerKeyboard(
                title: .libraryPageBarPage,
                text: text,
                isFocused: focus == .pageNumber,
                numberPad: true
            )
            .onAppear {
                focus = .pageNumber
            }
            .onSubmit {
                send(.commit)
                refocus()
            }
            .onMenuExitCommand {
                send(.cancel)
                refocus()
            }
            .onMenuKeyPress(keys: [.upArrow, .downArrow], phases: .down) { _ in
                .handled
            }
            .accessibilityLabel(.libraryPageBarPage)
            .accessibilityIdentifier("cloud-page-number")
    }

    private func refocus() {
        Task { @MainActor in
            await Task.yield()
            focus = .pageBar
        }
    }
}
