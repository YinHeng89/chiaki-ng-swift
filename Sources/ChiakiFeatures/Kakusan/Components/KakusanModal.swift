import ChiakiModels
import CoreGraphics
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// A Kakusan card over the window, driven by a feature's `ChiakiModels/KakusanControlGrid`.
///
/// The card owns controller input for its own window while it is shown: directions move the feature's
/// selection, Confirm activates the selected control and Back goes back. It handles nothing until it knows its
/// window, and nothing while a sheet or prompt is in front of it.
public struct KakusanModal<Content: View>: View {
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout
    /// The card's width on a regular screen.
    public var width: CGFloat
    /// Whether the window behind the card is dimmed.
    public var dims: Bool
    /// The card's controls and the selected one.
    public let controls: KakusanControlGrid
    /// Moves the selection.
    public let move: (KakusanGridStep) -> Void
    /// Activates a control.
    public let activate: (KakusanControl) -> Void
    /// Goes back.
    public let back: () -> Void
    /// The card's content.
    @ViewBuilder public var content: () -> Content
    @State private var hostWindow: PlatformWindow?

    /// Creates a Kakusan modal.
    ///
    /// - Parameters:
    ///   - width: The card's width on a regular screen.
    ///   - dims: Whether the window behind the card is dimmed.
    ///   - controls: The card's controls and the selected one.
    ///   - move: Moves the selection.
    ///   - activate: Activates a control.
    ///   - back: Goes back.
    ///   - content: The card's content.
    public init(
        width: CGFloat = 540,
        dims: Bool = true,
        controls: KakusanControlGrid,
        move: @escaping (KakusanGridStep) -> Void,
        activate: @escaping (KakusanControl) -> Void,
        back: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.dims = dims
        self.controls = controls
        self.move = move
        self.activate = activate
        self.back = back
        self.content = content
    }

    public var body: some View {
        ZStack {
            if dims {
                Dimming.standard.color
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
            }
            card
                .modalCard(.overlay)
                .padding(.horizontal, compactMargins.horizontal)
                .padding(.vertical, compactMargins.vertical)
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.96).combined(with: .opacity))
        }
        .frame(
            maxWidth: layout.isCompact
                ? .infinity
                : nil,
            maxHeight: layout.isCompact
                ? .infinity
                : nil
        )
        .background(WindowAccessor { hostWindow = $0 })
        .menuInputBlocking()
        .menuHandlers(move: handleMove, modalActivate: handleActivation, back: handleBack)
    }

    @ViewBuilder private var card: some View {
        if layout.isCompact {
            ViewThatFits(in: .vertical) {
                compactContent
                ScrollViewReader { proxy in
                    ScrollView {
                        compactContent
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: controls.selection) { _, current in
                        guard let current else {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(current, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: width)
        } else {
            VStack(alignment: .leading, spacing: 20, content: content)
                .padding(30)
                .frame(width: width)
        }
    }

    private var compactMargins: (horizontal: CGFloat, vertical: CGFloat) {
        guard layout.isCompact else {
            return (0, 0)
        }
        return (max(KakusanModalFit.margin, layout.sideInset), KakusanModalFit.margin)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: KakusanModalFit.spacing, content: content)
            .padding(KakusanModalFit.padding)
    }

    private func owns(_ window: PlatformWindow) -> Bool {
        guard let hostWindow, hostWindow === window else {
            return false
        }
        return !WindowFocus(window).hasAttachedSheet && !(navigator?.inputGate.isPrompting ?? false)
    }

    private func handleMove(_ window: PlatformWindow, _ direction: MenuMoveDirection) -> Bool {
        guard owns(window) else {
            return false
        }
        switch direction {
        case .up:
            move(.up)
        case .down:
            move(.down)
        case .left:
            move(.left)
        case .right:
            move(.right)
        @unknown default:
            break
        }
        return true
    }

    private func handleActivation(_ window: PlatformWindow) -> Bool {
        guard owns(window) else {
            return false
        }
        if let selection = controls.selection {
            activate(selection)
        }
        return true
    }

    private func handleBack(_ window: PlatformWindow) -> Bool {
        guard owns(window) else {
            return false
        }
        back()
        return true
    }
}

extension View {
    /// Marks the view as a Kakusan control: focused when it is the grid's selection, and a scroll target.
    ///
    /// - Parameters:
    ///   - control: The control the view is.
    ///   - controls: The card's controls.
    /// - Returns: The marked view.
    public func kakusanControl(_ control: KakusanControl,
                               in controls: KakusanControlGrid) -> some View {
        environment(\.menuItemFocused, controls.selection == control)
            .id(control)
    }
}

/// How a Kakusan card fits a compact screen.
private enum KakusanModalFit {
    /// The gap between a card's sections.
    public static let spacing: CGFloat = 14
    /// The padding inside a card.
    public static let padding: CGFloat = 18
    /// The least space kept between a card and the screen edge.
    public static let margin: CGFloat = 10
}
