import AVKit
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The game detail's horizontal rail of screenshots and trailers, with paging buttons when it overflows.
///
/// Each tile is a controller focus stop that opens its item, and focusing a tile scrolls it to the centre.
struct GameMediaRail: View {
    /// The rail's scroll geometry, used to page it and enable the paging buttons.
    struct Metrics: Equatable {
        /// The current horizontal scroll offset.
        var offset: CGFloat = 0
        /// The visible width of the rail.
        var viewport: CGFloat = 0
        /// The full width of the rail's content.
        var content: CGFloat = 0

        /// The furthest the rail can scroll, or zero when everything fits.
        var maximumOffset: CGFloat {
            max(0, content - viewport)
        }

        /// The offset one page forward or back, a viewport less one tile, clamped to the scrollable range.
        ///
        /// - Parameter forward: Whether to page forward rather than back.
        func page(forward: Bool) -> CGFloat {
            let step = max(viewport - GameMediaRail.tileStride, GameMediaRail.tileStride)
            let proposed = offset + (forward
                ? step
                : -step)
            return min(max(proposed, 0), maximumOffset)
        }
    }

    /// The horizontal distance from one tile to the next.
    nonisolated static let tileStride: CGFloat = 234

    /// The screenshots and trailers in rail order.
    let media: [GameDetailPresentation.Media]
    /// The horizontal inset of the title row and the rail's content.
    let inset: CGFloat
    /// Whether a vertical mouse wheel scrolls the rail sideways.
    let wheelScrolls: Bool
    /// The cloud library's controller focus, bound to the tiles.
    @MenuFocusState.Binding var focus: CloudLibraryFocus?
    /// Opens the media item at an index.
    let open: (Int) -> Void
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var metrics = Metrics()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The accessibility label of a tile, such as "Screenshot 2" or "Trailer 1".
    ///
    /// - Parameters:
    /// - index: The tile's position in the rail.
    /// - item: The media item.
    nonisolated static func label(_ index: Int, _ item: GameDetailPresentation.Media) -> String {
        item.isScreenshot
            ? "Screenshot \(index + 1)"
            : "Trailer \(index + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Screenshots and trailers")
                    .font(.system(size: 19, weight: .semibold))
                Spacer()
                if metrics.maximumOffset > 1 {
                    HStack(spacing: 8) {
                        pageButton(forward: false)
                        pageButton(forward: true)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, inset)
            rail
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: metrics.maximumOffset > 1)
    }

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                    tile(index, item)
                        .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, inset)
            .padding(.vertical, 6)
            .background(WheelScrollsAlongRow(enabled: wheelScrolls))
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            Metrics(
                offset: geometry.contentOffset.x,
                viewport: geometry.containerSize.width,
                content: geometry.contentSize.width
            )
        } action: { _, value in
            metrics = value
        }
        .onChange(of: focus) { _, target in
            guard case .media(let index) = target, media.indices.contains(index) else {
                return
            }
            withAnimation(AppMotion.animation(reduced: reduceMotion)) {
                position.scrollTo(id: index, anchor: .center)
            }
        }
    }

    private func tile(_ index: Int, _ item: GameDetailPresentation.Media) -> some View {
        FocusButton {
            open(index)
        } label: {
            art(item)
                .frame(width: 220, height: 124)
                .clipShape(.rect(cornerRadius: 12))
                .containedFocusGlow(in: .roundedRectangle(12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.14))
                }
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.contained)
        .menuFocused($focus, equals: .media(index))
        .accessibilityIdentifier("cloud-detail-media-\(index)")
        .accessibilityLabel(Self.label(index, item))
    }

    @ViewBuilder private func art(_ item: GameDetailPresentation.Media) -> some View {
        switch item {
        case .screenshot(let url):
            GameArtImage(url: url, size: .tile)
        case .trailer(let url):
            GameTrailerStill(url: url)
        }
    }

    private func pageButton(forward: Bool) -> some View {
        Button {
            let target = metrics.page(forward: forward)
            withAnimation(AppMotion.animation(reduced: reduceMotion)) {
                position.scrollTo(x: target)
            }
        } label: {
            Label(
                forward
                    ? "Scroll Forward"
                    : "Scroll Back",
                systemImage: forward
                    ? "chevron.right"
                    : "chevron.left"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 16, height: 16)
        }
        .interactiveGrowth()
        .glassControlStyle()
        .buttonBorderShape(.circle)
        .menuFocusable(false)
        .focusEffectDisabled()
        .disabled(forward
            ? metrics.offset >= metrics.maximumOffset - 1
            : metrics.offset <= 1)
            .accessibilityIdentifier(forward
                ? "cloud-detail-media-forward"
                : "cloud-detail-media-back")
    }
}

/// Lets a plain vertical mouse wheel scroll the horizontal row it sits in, leaving trackpad and horizontal
/// scrolls alone.
///
/// Place it in the background of a horizontal scroll view's content; it draws nothing and takes no clicks.
struct WheelScrollsAlongRow: PlatformViewRepresentable {
    /// The invisible platform view that watches the wheel.
    typealias PlatformViewType = Marker

    /// How far one line of wheel movement scrolls the row.
    nonisolated static let lineStep: CGFloat = 40

    /// Whether the wheel redirection is active.
    let enabled: Bool

    /// One wheel movement.
    struct Wheel {
        /// The horizontal movement in lines.
        let deltaX: CGFloat
        /// The vertical movement in lines.
        let deltaY: CGFloat
        /// Whether the movement comes from a precise device such as a trackpad.
        let precise: Bool
    }

    /// Works out where a wheel movement scrolls the row.
    ///
    /// - Parameters:
    /// - current: The row's current offset.
    /// - viewport: The visible width.
    /// - content: The content width.
    /// - wheel: The wheel movement.
    /// - Returns: The new clamped offset, or `nil` when the movement is precise, mostly horizontal, the row
    ///   does not overflow, or nothing would move.
    nonisolated static func offset(
        from current: CGFloat,
        viewport: CGFloat,
        content: CGFloat,
        wheel: Wheel
    ) -> CGFloat? {
        guard !wheel.precise, wheel.deltaY != 0, abs(wheel.deltaY) > abs(wheel.deltaX),
              content > viewport else {
            return nil
        }
        let target = min(max(current - wheel.deltaY * lineStep, 0), content - viewport)
        guard abs(target - current) >= 0.5 else {
            return nil
        }
        return target
    }

    /// Creates the marker view.
    func makePlatformView(context: Context) -> Marker {
        let marker = Marker()
        marker.enabled = enabled
        return marker
    }

    /// Turns the redirection on or off.
    func updatePlatformView(_ marker: Marker, context: Context) {
        marker.enabled = enabled
    }

    /// Stops watching the wheel when the view goes away.
    static func dismantlePlatformView(_ marker: Marker, coordinator: ()) {
        marker.stopWatching()
    }

    #if os(macOS)
        /// An invisible view that intercepts scroll-wheel events over its enclosing scroll view and scrolls
        /// it sideways.
        final class Marker: NSView {
            /// Whether wheel events are redirected.
            var enabled = true
            private var monitor: Any?

            /// Lets every click pass through.
            override func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }

            /// Starts watching scroll-wheel events when the view joins a window, and stops when it leaves.
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stopWatching()
                guard window != nil else {
                    return
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self, self.scroll(with: event) else {
                        return event
                    }
                    return nil
                }
            }

            /// Stops watching scroll-wheel events.
            func stopWatching() {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }

            private func scroll(with event: NSEvent) -> Bool {
                guard enabled, let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                      let scrollView = enclosingScrollView, let document = scrollView.documentView else {
                    return false
                }
                let clip = scrollView.contentView
                guard clip.bounds.contains(clip.convert(event.locationInWindow, from: nil)),
                      let target = WheelScrollsAlongRow.offset(
                          from: clip.bounds.origin.x, viewport: clip.bounds.width,
                          content: document.frame.width,
                          wheel: Wheel(
                              deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                              precise: event.hasPreciseScrollingDeltas
                          )
                      ) else {
                    return false
                }
                clip.setBoundsOrigin(CGPoint(x: target, y: clip.bounds.origin.y))
                scrollView.reflectScrolledClipView(clip)
                return true
            }
        }
    #else
        /// An invisible view that adds a discrete-scroll recogniser to its enclosing scroll view and scrolls
        /// it sideways on vertical wheel movement.
        final class Marker: UIView, UIGestureRecognizerDelegate {
            /// Whether wheel movement is redirected.
            var enabled = true
            private var wheel: UIPanGestureRecognizer?

            /// Lets every touch pass through.
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                nil
            }

            /// Attaches the wheel recogniser to the enclosing scroll view when the view joins a window, and
            /// removes it when it leaves.
            override func didMoveToWindow() {
                super.didMoveToWindow()
                stopWatching()
                guard window != nil, let scrollView = hostScrollView else {
                    return
                }
                let recognizer = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
                recognizer.allowedScrollTypesMask = .discrete
                recognizer.allowedTouchTypes = []
                recognizer.delegate = self
                scrollView.addGestureRecognizer(recognizer)
                wheel = recognizer
            }

            /// Removes the wheel recogniser.
            func stopWatching() {
                if let wheel {
                    wheel.view?.removeGestureRecognizer(wheel)
                }
                wheel = nil
            }

            /// Begins only for mostly vertical wheel movement over a row that overflows, while redirection is
            /// enabled.
            override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
                guard enabled, let pan = recognizer as? UIPanGestureRecognizer,
                      let scrollView = pan.view as? UIScrollView else {
                    return false
                }
                let velocity = pan.velocity(in: scrollView)
                return abs(velocity.y) > abs(velocity.x) && scrollView.contentSize.width > scrollView.bounds
                    .width
            }

            private var hostScrollView: UIScrollView? {
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView {
                        return scrollView
                    }
                    ancestor = view.superview
                }
                return nil
            }

            private func target(for translation: CGPoint, in scrollView: UIScrollView) -> CGFloat? {
                WheelScrollsAlongRow.offset(
                    from: scrollView.contentOffset.x, viewport: scrollView.bounds.width,
                    content: scrollView.contentSize.width,
                    wheel: Wheel(
                        deltaX: translation.x / WheelScrollsAlongRow.lineStep,
                        deltaY: translation.y / WheelScrollsAlongRow.lineStep,
                        precise: false
                    )
                )
            }

            @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
                guard enabled, let scrollView = recognizer.view as? UIScrollView,
                      recognizer.state == .began || recognizer.state == .changed else {
                    return
                }
                let translation = recognizer.translation(in: scrollView)
                recognizer.setTranslation(.zero, in: scrollView)
                guard let target = target(for: translation, in: scrollView) else {
                    return
                }
                scrollView.setContentOffset(
                    CGPoint(x: target, y: scrollView.contentOffset.y),
                    animated: false
                )
            }
        }
    #endif
}

/// One layer of a game's catalogue art, loaded through the artwork pipeline at a chosen size and kept as a
/// faint placeholder until it arrives.
///
/// Insecure or malformed addresses show the empty placeholder.
struct GameArtImage: View {
    /// The art's address as the catalogue gives it.
    let url: String
    /// The pixel size to load the art at.
    let size: GameArtSize
    /// How the image fills the frame; fills it by default.
    var contentMode = ContentMode.fill
    @Environment(\.catalog) private var catalog
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(.white.opacity(image == nil
                    ? 0.06
                    : 0))
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    }
                }
                .clipped()
                .task(id: url) {
                    guard let address = URL.secureArtwork(url) else {
                        image = nil
                        return
                    }
                    let loaded = await catalog.gameArt(address, size)
                    guard !Task.isCancelled else {
                        return
                    }
                    image = loaded
                }
    }
}

/// A trailer thumbnail with a play badge, whose still frame is loaded the first time it scrolls into view.
private struct GameTrailerStill: View {
    /// Whether the thumbnail has scrolled into view yet.
    enum Sight: Equatable {
        /// The thumbnail has not been on screen yet, or has been seen at least once and loads its frame.
        case unseen, seen
    }

    /// The trailer whose frame the thumbnail shows.
    let url: URL
    @Environment(\.catalog) private var catalog
    @State private var sight = Sight.unseen
    @State private var frame: CGImage?

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .overlay {
                if let frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .overlay {
                Image(systemName: AppIcon.start.rawValue)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CloudGameDetail.detailPage)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.92), in: .circle)
            }
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                if visible {
                    sight = .seen
                }
            }
            .task(id: sight) {
                guard sight == .seen, frame == nil else {
                    return
                }
                let still = await catalog.trailerFrame(url)
                guard !Task.isCancelled else {
                    return
                }
                frame = still
            }
    }
}

#if os(macOS)
    /// Plays a trailer in a native player with floating controls, starting as soon as it appears.
    struct GameTrailerPlayer: NSViewRepresentable {
        /// The trailer to play.
        let url: URL

        /// Creates the player view and starts playback.
        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.controlsStyle = .floating
            view.videoGravity = .resizeAspect
            let player = AVPlayer(url: url)
            view.player = player
            player.play()
            return view
        }

        /// Leaves the player alone; the trailer never changes after creation.
        func updateNSView(_ view: AVPlayerView, context: Context) {
        }

        /// Stops playback and releases the player when the view goes away.
        static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
            view.player?.pause()
            view.player?.replaceCurrentItem(with: nil)
            view.player = nil
        }
    }
#else
    /// Plays a trailer in a native player with playback controls, starting as soon as it appears.
    struct GameTrailerPlayer: UIViewControllerRepresentable {
        /// The trailer to play.
        let url: URL

        /// Creates the player controller and starts playback.
        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.showsPlaybackControls = true
            controller.videoGravity = .resizeAspect
            controller.view.backgroundColor = .clear
            let player = AVPlayer(url: url)
            controller.player = player
            player.play()
            return controller
        }

        /// Leaves the player alone; the trailer never changes after creation.
        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        }

        /// Stops playback and releases the player when the view goes away.
        static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
            controller.player?.pause()
            controller.player?.replaceCurrentItem(with: nil)
            controller.player = nil
        }
    }
#endif
