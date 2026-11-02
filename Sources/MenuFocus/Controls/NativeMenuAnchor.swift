import PlatformUI
import SwiftUI

/// Opens a list of choices from a view so a controller can pick one.
///
/// Attach it to a view with ``SwiftUICore/View/nativeMenuAnchor(_:)``. On macOS the choices open as a native menu
/// with the current choice marked and positioned under the pointer; on iOS they open as an action sheet
/// anchored to the view.
@MainActor
public final class NativeMenuAnchorReference {
    fileprivate weak var view: PlatformView?

    /// Creates a reference that is not yet attached to a view.
    public init() {}

    #if os(macOS)
        /// Opens the choices as a native menu at the attached view.
        ///
        /// - Parameters:
        ///   - titles: The choice titles, in order.
        ///   - selected: The index of the current choice, which is marked and positioned under the pointer.
        ///   - select: Called with the index of the chosen item.
        /// - Returns: `false` when the view is not in a window or is hidden, so nothing opened.
        @discardableResult
        public func presentMenu(titles: [String], selected: Int?, select: @escaping (Int) -> Void) -> Bool {
            guard let view, view.window != nil, !view.isHiddenOrHasHiddenAncestor else {
                return false
            }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let target = NativeMenuAnchorTarget(select: select)
            for (index, title) in titles.enumerated() {
                let item = NSMenuItem(
                    title: title,
                    action: #selector(NativeMenuAnchorTarget.choose(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.tag = index
                item.state = index == selected
                    ? .on
                    : .off
                menu.addItem(item)
            }
            let positioned = menu.item(at: selected ?? 0)
            return withExtendedLifetime(target) {
                menu.popUp(positioning: positioned, at: .zero, in: view)
            }
        }
    #else
        /// Opens the choices as an action sheet anchored to the attached view.
        ///
        /// - Parameters:
        ///   - titles: The choice titles, in order.
        ///   - selected: Unused on iOS, where the sheet does not mark a choice.
        ///   - select: Called with the index of the chosen item.
        /// - Returns: `false` when there is no controller that can present the sheet.
        @discardableResult
        public func presentMenu(titles: [String], selected: Int?, select: @escaping (Int) -> Void) -> Bool {
            guard let view, !view.isHidden, var presenter = view.window?.rootViewController else {
                return false
            }
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            guard !presenter.isBeingDismissed, !(presenter is UIAlertController) else {
                return false
            }
            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            for (index, title) in titles.enumerated() {
                sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                    select(index)
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = view.bounds
            presenter.present(sheet, animated: !UIAccessibility.isReduceMotionEnabled)
            return true
        }
    #endif
}

#if os(macOS)
    private final class NativeMenuAnchorTarget: NSObject {
        let select: (Int) -> Void

        init(select: @escaping (Int) -> Void) {
            self.select = select
        }

        @objc func choose(_ sender: NSMenuItem) {
            select(sender.tag)
        }
    }
#endif

/// The invisible view a ``NativeMenuAnchorReference`` opens its choices from.
public struct NativeMenuAnchor: PlatformViewRepresentable {
    /// The platform view type the anchor uses.
    public typealias PlatformViewType = PlatformView

    private let reference: NativeMenuAnchorReference

    /// Creates the anchor for a reference.
    ///
    /// - Parameter reference: The reference that opens menus from this view.
    public init(reference: NativeMenuAnchorReference) {
        self.reference = reference
    }

    /// Makes the anchor view and attaches it to the reference.
    ///
    /// - Parameter context: The representable context.
    /// - Returns: A view that ignores pointer input.
    public func makePlatformView(context: Context) -> PlatformView {
        let view = AnchorView()
        reference.view = view
        return view
    }

    /// Keeps the reference attached to the current view.
    ///
    /// - Parameters:
    ///   - view: The anchor view.
    ///   - context: The representable context.
    public func updatePlatformView(_ view: PlatformView, context: Context) {
        reference.view = view
    }

    #if os(macOS)
        private final class AnchorView: NSView {
            override var isFlipped: Bool {
                true
            }

            override func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }
        }
    #else
        private final class AnchorView: UIView {
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                nil
            }
        }
    #endif
}

extension View {
    /// Places an invisible anchor behind the view so the reference can open a choice list from it.
    ///
    /// - Parameter reference: The reference that opens the list.
    /// - Returns: The view with the anchor in its background.
    public func nativeMenuAnchor(_ reference: NativeMenuAnchorReference) -> some View {
        background(NativeMenuAnchor(reference: reference))
    }
}
