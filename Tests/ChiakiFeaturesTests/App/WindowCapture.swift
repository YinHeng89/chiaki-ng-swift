@testable import ChiakiFeatures
import ChiakiModels
import AppKit
import ScreenCaptureKit
import Testing

struct WindowCapture {
    let bitmap: NSBitmapImageRep
    let windowServer: Bool

    @MainActor static func of(_ window: NSWindow, view: NSView) async throws -> WindowCapture {
        if let bitmap = await windowServerBitmap(window, size: view.bounds.size) {
            return WindowCapture(bitmap: bitmap, windowServer: true)
        }
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return WindowCapture(bitmap: bitmap, windowServer: false)
    }

    func png() throws -> Data {
        try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor private static func windowServerBitmap(_ window: NSWindow,
                                                      size: CGSize) async -> NSBitmapImageRep? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ),
            let shown = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
        else {
            return nil
        }
        let scale = window.backingScaleFactor
        let titleBar = window.frame.height - window.contentLayoutRect.height
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: 0, y: titleBar, width: size.width, height: size.height)
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: shown),
            configuration: configuration
        ) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image)
    }
}
