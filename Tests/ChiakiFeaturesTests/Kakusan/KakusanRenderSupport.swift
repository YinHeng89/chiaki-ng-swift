#if CHIAKI_KAKUSAN
    @testable import ChiakiFeatures
    import ChiakiModels
    import PlatformUI
    import SwiftUI
    import Testing
    import ChiakiTestSupport
    import MenuFocus

    struct KakusanCapture {
        let coverage: Double
        let windowServer: Bool

        func expect(above minimum: Double, _ name: String,
                    sourceLocation: SourceLocation = #_sourceLocation) {
            guard windowServer else {
                withKnownIssue("cacheDisplay cannot capture views inside Liquid Glass",
                               isIntermittent: true) {
                    #expect(
                        coverage > minimum,
                        "\(name) rendered almost nothing \(coverage)",
                        sourceLocation: sourceLocation
                    )
                }
                return
            }
            #expect(
                coverage > minimum,
                "\(name) rendered almost nothing \(coverage)",
                sourceLocation: sourceLocation
            )
        }
    }

    struct KakusanRender {
        let name: String
        let dark: Bool

        var backdrop: Color {
            dark
                ? Color(red: 0.06, green: 0.08, blue: 0.11)
                : Color(red: 0.93, green: 0.94, blue: 0.96)
        }

        @MainActor func render(_ root: some View,
                               size: CGSize = CGSize(width: 1320, height: 860)) async throws
            -> KakusanCapture {
            _ = NSApplication.shared
            let scheme: ColorScheme = dark
                ? .dark
                : .light
            let view = MenuFocusHostingView(rootView: ZStack {
                backdrop
                root
            }
            .environment(\.colorScheme, scheme))
            let window = HeadlessWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.appearance = NSAppearance(named: dark
                ? .darkAqua
                : .aqua)
            window.orderFrontRegardless()
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            let capture = try await WindowCapture.of(window, view: view)
            let bitmap = capture.bitmap
            window.contentView = nil
            window.close()
            try await Task.sleep(for: .milliseconds(50))
            if let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] {
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                let suffix = dark
                    ? "dark"
                    : "light"
                try data
                    .write(to: URL(fileURLWithPath: directory)
                        .appendingPathComponent("kakusan-\(name)-\(suffix).png"))
            }
            return KakusanCapture(coverage: coverage(bitmap), windowServer: capture.windowServer)
        }

        private func coverage(_ bitmap: NSBitmapImageRep) -> Double {
            guard let data = bitmap.bitmapData, bitmap.bitsPerSample == 8, bitmap.samplesPerPixel >= 3 else {
                return 0
            }
            let stride = bitmap.samplesPerPixel
            let rowBytes = bitmap.bytesPerRow
            let offset = bitmap.bitmapFormat.contains(.alphaFirst)
                ? 1
                : 0
            let reference = (0 ..< 3).map { Int(data[offset + $0]) }
            let step = 4
            var changed = 0
            var sampled = 0
            for row in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                for column in Swift.stride(from: 0, to: bitmap.pixelsWide, by: step) {
                    sampled += 1
                    let base = row * rowBytes + column * stride + offset
                    let delta = (0 ..< 3).reduce(0) { total, channel in
                        total + abs(Int(data[base + channel]) - reference[channel])
                    }
                    if delta > 36 {
                        changed += 1
                    }
                }
            }
            return Double(changed) / Double(max(sampled, 1))
        }
    }
#endif
