import AppKit

let fullBleed = CommandLine.arguments.contains("--ios")
let arguments = CommandLine.arguments.filter { $0 != "--ios" }
let logoURL = URL(fileURLWithPath: arguments[1])
let iconset = URL(fileURLWithPath: arguments[2])
let label = arguments.count > 3
    ? arguments[3].uppercased()
    : ""
let lime = NSColor(srgbRed: 0.68, green: 0.78, blue: 0.04, alpha: 1)
let ink = NSColor(srgbRed: 0.055, green: 0.075, blue: 0.10, alpha: 1)

guard let source = NSImage(contentsOf: logoURL),
      let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let context = CGContext(
          data: nil,
          width: sourceImage.width,
          height: sourceImage.height,
          bitsPerComponent: 8,
          bytesPerRow: sourceImage.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let bytes = context.data?.assumingMemoryBound(to: UInt8.self)
else {
    FileHandle.standardError.write(Data("Could not read \(logoURL.path)\n".utf8))
    exit(1)
}
context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
for offset in stride(from: 0, to: sourceImage.width * sourceImage.height * 4, by: 4) {
    let alpha = bytes[offset + 3]
    if alpha > 0 && bytes[offset + 2] > bytes[offset + 1] {
        bytes[offset] = alpha
        bytes[offset + 1] = alpha
        bytes[offset + 2] = alpha
    }
}
guard let recoloured = context.makeImage() else {
    exit(1)
}
let logo = NSImage(cgImage: recoloured, size: source.size)

func drawIcon(in canvas: CGFloat) {
    let unit = canvas / 1024
    let body = fullBleed
        ? NSRect(x: 0, y: 0, width: canvas, height: canvas)
        : NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let radius = fullBleed
        ? 0
        : 185 * unit
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(
        starting: NSColor(srgbRed: 0.10, green: 0.145, blue: 0.19, alpha: 1),
        ending: ink
    )?.draw(in: shape, angle: -90)

    let logoWidth = (fullBleed ? 760 : 640) * unit
    let logoHeight = logoWidth * logo.size.height / logo.size.width
    let logoY = label.isEmpty
        ? (canvas - logoHeight) / 2
        : 430 * unit
    logo.draw(
        in: NSRect(x: (canvas - logoWidth) / 2, y: logoY, width: logoWidth, height: logoHeight),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    guard !label.isEmpty else {
        return
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 104 * unit, weight: .heavy),
        .foregroundColor: ink,
        .kern: 6 * unit,
    ]
    let text = NSAttributedString(string: label, attributes: attributes)
    let textSize = text.size()
    let pill = NSRect(
        x: (canvas - textSize.width - 112 * unit) / 2,
        y: 200 * unit,
        width: textSize.width + 112 * unit,
        height: 156 * unit
    )
    lime.setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    text.draw(at: NSPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2))
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let renders: [(points: Double, scale: Int)] = fullBleed
    ? [(60, 2), (60, 3), (76, 2), (83.5, 2), (1024, 1)]
    : [16, 32, 128, 256, 512].flatMap { points in
        [(Double(points), 1), (Double(points), 2)]
    }
for render in renders {
    let points = render.points
    let scale = render.scale
    do {
        let pixels = Int(points * Double(scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            exit(1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        drawIcon(in: CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()
        let size = points == points.rounded()
            ? String(Int(points))
            : String(points)
        let name = fullBleed
            ? "AppIcon\(size)x\(size)@\(scale)x.png"
            : scale == 1
            ? "icon_\(size)x\(size).png"
            : "icon_\(size)x\(size)@2x.png"
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            exit(1)
        }
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
