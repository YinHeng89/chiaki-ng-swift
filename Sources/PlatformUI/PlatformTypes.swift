#if canImport(AppKit)
    import AppKit

    /// The platform's view class: `NSView` on macOS.
    public typealias PlatformView = NSView
    /// The platform's window class: `NSWindow` on macOS.
    public typealias PlatformWindow = NSWindow
    /// The platform's image class: `NSImage` on macOS.
    public typealias PlatformImage = NSImage
    /// The platform's colour class: `NSColor` on macOS.
    public typealias PlatformColor = NSColor
    /// The platform's screen class: `NSScreen` on macOS.
    public typealias PlatformScreen = NSScreen
#else
    import UIKit

    /// The platform's view class: `UIView` on iOS.
    public typealias PlatformView = UIView
    /// The platform's window class: `UIWindow` on iOS.
    public typealias PlatformWindow = UIWindow
    /// The platform's image class: `UIImage` on iOS.
    public typealias PlatformImage = UIImage
    /// The platform's colour class: `UIColor` on iOS.
    public typealias PlatformColor = UIColor
    /// The platform's screen class: `UIScreen` on iOS.
    public typealias PlatformScreen = UIScreen
#endif
