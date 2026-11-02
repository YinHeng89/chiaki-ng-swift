import SwiftUI

#if canImport(AppKit)
    import AppKit

    /// A SwiftUI representable written once for both platforms, backed by `NSViewRepresentable` on macOS.
    ///
    /// Conformers implement the `Platform` methods; the native requirements forward to them.
    public protocol PlatformViewRepresentable: NSViewRepresentable where NSViewType == PlatformViewType {
        /// The view class the representable creates.
        associatedtype PlatformViewType: NSView

        /// Creates the platform view.
        ///
        /// - Parameter context: The representable context.
        /// - Returns: The new view.
        @MainActor func makePlatformView(context: Context) -> PlatformViewType

        /// Updates the platform view with new SwiftUI state.
        ///
        /// - Parameters:
        ///   - view: The view to update.
        ///   - context: The representable context.
        @MainActor func updatePlatformView(_ view: PlatformViewType, context: Context)

        /// Tears down the platform view when SwiftUI removes it.
        ///
        /// - Parameters:
        ///   - view: The view being removed.
        ///   - coordinator: The representable's coordinator.
        @MainActor static func dismantlePlatformView(_ view: PlatformViewType, coordinator: Coordinator)
    }

    extension PlatformViewRepresentable {
        /// Forwards to ``makePlatformView(context:)``.
        ///
        /// - Parameter context: The representable context.
        /// - Returns: The new view.
        public func makeNSView(context: Context) -> PlatformViewType {
            makePlatformView(context: context)
        }

        /// Forwards to ``updatePlatformView(_:context:)``.
        ///
        /// - Parameters:
        ///   - nsView: The view to update.
        ///   - context: The representable context.
        public func updateNSView(_ nsView: PlatformViewType, context: Context) {
            updatePlatformView(nsView, context: context)
        }

        /// Forwards to ``dismantlePlatformView(_:coordinator:)``.
        ///
        /// - Parameters:
        ///   - nsView: The view being removed.
        ///   - coordinator: The representable's coordinator.
        public static func dismantleNSView(_ nsView: PlatformViewType, coordinator: Coordinator) {
            dismantlePlatformView(nsView, coordinator: coordinator)
        }

        /// Does nothing; conformers override it when their view needs tearing down.
        ///
        /// - Parameters:
        ///   - view: The view being removed.
        ///   - coordinator: The representable's coordinator.
        public static func dismantlePlatformView(_ view: PlatformViewType, coordinator: Coordinator) {
        }
    }
#else
    import UIKit

    /// A SwiftUI representable written once for both platforms, backed by `UIViewRepresentable` on iOS.
    ///
    /// Conformers implement the `Platform` methods; the native requirements forward to them.
    public protocol PlatformViewRepresentable: UIViewRepresentable where UIViewType == PlatformViewType {
        /// The view class the representable creates.
        associatedtype PlatformViewType: UIView

        /// Creates the platform view.
        ///
        /// - Parameter context: The representable context.
        /// - Returns: The new view.
        @MainActor func makePlatformView(context: Context) -> PlatformViewType

        /// Updates the platform view with new SwiftUI state.
        ///
        /// - Parameters:
        ///   - view: The view to update.
        ///   - context: The representable context.
        @MainActor func updatePlatformView(_ view: PlatformViewType, context: Context)

        /// Tears down the platform view when SwiftUI removes it.
        ///
        /// - Parameters:
        ///   - view: The view being removed.
        ///   - coordinator: The representable's coordinator.
        @MainActor static func dismantlePlatformView(_ view: PlatformViewType, coordinator: Coordinator)
    }

    extension PlatformViewRepresentable {
        /// Forwards to ``makePlatformView(context:)``.
        ///
        /// - Parameter context: The representable context.
        /// - Returns: The new view.
        public func makeUIView(context: Context) -> PlatformViewType {
            makePlatformView(context: context)
        }

        /// Forwards to ``updatePlatformView(_:context:)``.
        ///
        /// - Parameters:
        ///   - uiView: The view to update.
        ///   - context: The representable context.
        public func updateUIView(_ uiView: PlatformViewType, context: Context) {
            updatePlatformView(uiView, context: context)
        }

        /// Forwards to ``dismantlePlatformView(_:coordinator:)``.
        ///
        /// - Parameters:
        ///   - uiView: The view being removed.
        ///   - coordinator: The representable's coordinator.
        public static func dismantleUIView(_ uiView: PlatformViewType, coordinator: Coordinator) {
            dismantlePlatformView(uiView, coordinator: coordinator)
        }

        /// Does nothing; conformers override it when their view needs tearing down.
        ///
        /// - Parameters:
        ///   - view: The view being removed.
        ///   - coordinator: The representable's coordinator.
        public static func dismantlePlatformView(_ view: PlatformViewType, coordinator: Coordinator) {
        }
    }
#endif
