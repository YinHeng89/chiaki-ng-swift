#if os(macOS)
    import AppKit
    import PlatformUI

    /// Scrolls the innermost visible scroll view so the focused control is not cut off.
    ///
    /// Only scroll views that can scroll, contain the control, are frontmost at their centre and do not
    /// manage their own focus scrolling (``SelfManagedFocusScrolling``) are moved. The control is kept
    /// ``FocusGeometry/revealMargin`` points from the edge, and the scroll animates unless Reduce
    /// Motion is on.
    @MainActor
    public enum AppKitScrollReveal {
        /// Reveals the focused control of a window.
        ///
        /// - Parameter window: The window whose focus to reveal.
        public static func revealFocus(in window: PlatformWindow) {
            guard window.isVisible,
                  let view = AppKitKeyViews.focusView(in: window),
                  view !== window.contentView,
                  let frame = AppKitKeyViews.focusFrame(view),
                  frame.height < window.frame.height,
                  let scrollView = activeScrollView(containing: frame, in: window) else {
                return
            }
            reveal(frame, in: scrollView)
        }

        /// Reveals the focused control of a window now and again after the focus change settles.
        ///
        /// - Parameter window: The window whose focus to reveal.
        public static func scheduleReveal(in window: PlatformWindow) {
            Task { @MainActor in
                await Task.yield()
                revealFocus(in: window)
                try? await Task.sleep(for: .milliseconds(140))
                revealFocus(in: window)
            }
        }

        private static func activeScrollView(containing frame: CGRect,
                                             in window: PlatformWindow) -> NSScrollView? {
            guard let content = window.contentView else {
                return nil
            }
            var candidates = [(scrollView: NSScrollView, depth: Int)]()
            collectScrollViews(in: content, depth: 0, into: &candidates)
            let point = CGPoint(x: frame.midX, y: frame.midY)
            return candidates
                .filter { candidate in
                    isScrollable(candidate.scrollView)
                        && !managesOwnScrolling(candidate.scrollView)
                        && documentFrame(of: candidate.scrollView)?.contains(point) == true
                        && isFrontmost(candidate.scrollView, in: content)
                }
                .max { first, second in
                    first.depth < second.depth
                }?
                .scrollView
        }

        private static func collectScrollViews(
            in view: NSView,
            depth: Int,
            into candidates: inout [(scrollView: NSScrollView, depth: Int)]
        ) {
            for subview in view.subviews where !subview.isHidden {
                if let scrollView = subview as? NSScrollView {
                    candidates.append((scrollView, depth))
                }
                collectScrollViews(in: subview, depth: depth + 1, into: &candidates)
            }
        }

        private static func managesOwnScrolling(_ scrollView: NSScrollView) -> Bool {
            guard let document = scrollView.documentView else {
                return false
            }
            return containsMarker(document)
        }

        private static func containsMarker(_ view: NSView) -> Bool {
            view.subviews.contains { subview in
                subview is SelfManagedFocusScrolling.Marker || containsMarker(subview)
            }
        }

        private static func isScrollable(_ scrollView: NSScrollView) -> Bool {
            guard let document = scrollView.documentView else {
                return false
            }
            return document.frame.height > scrollView.contentView.bounds.height + 1
        }

        private static func documentFrame(of scrollView: NSScrollView) -> CGRect? {
            guard let document = scrollView.documentView else {
                return nil
            }
            return document.convert(document.bounds, to: nil)
        }

        private static func isFrontmost(_ scrollView: NSScrollView, in content: NSView) -> Bool {
            let clip = scrollView.contentView
            let visible = clip.convert(clip.bounds, to: nil)
            let probe = CGPoint(x: visible.midX, y: visible.midY)
            guard let hit = content.hitTest(content.convert(probe, from: nil)) else {
                return false
            }
            return hit === scrollView || hit.isDescendant(of: scrollView)
        }

        private static func reveal(_ frame: CGRect, in scrollView: NSScrollView) {
            let clip = scrollView.contentView
            let target = clip.convert(frame, from: nil)
            let visible = clip.bounds
            let margin = min(FocusGeometry.revealMargin, max(0, (visible.height - target.height) / 2))
            var delta: CGFloat = 0
            if target.maxY > visible.maxY - margin {
                delta = target.maxY - (visible.maxY - margin)
            }
            if target.minY < visible.minY + margin {
                delta = target.minY - (visible.minY + margin)
            }
            guard abs(delta) >= 1 else {
                return
            }
            var bounds = visible
            bounds.origin.y += delta
            let origin = clip.constrainBoundsRect(bounds).origin
            guard origin != visible.origin else {
                return
            }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                clip.setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(clip)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(clip)
            }
            let start = visible.origin
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard clip.bounds.origin == start else {
                    return
                }
                clip.setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(clip)
            }
        }
    }
#endif
