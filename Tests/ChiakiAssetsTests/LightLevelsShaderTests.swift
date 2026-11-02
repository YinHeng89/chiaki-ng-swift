import ChiakiAssets
import Foundation
import Metal
import Testing

private struct ShaderColourConfig {
    var tenBit: UInt32 = 1
    var fullRange: UInt32 = 0
    var bt2020: UInt32 = 1
    var perceptualQuantiser: UInt32 = 1
    var toneMap: UInt32 = 0
    var diagnosticMode: UInt32 = 1
    var referenceWhiteNits: Float = 203
    var adjust: UInt32 = 0
    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var gamma: Float = 1
    var deband: UInt32 = 0
    var frame: UInt32 = 0
    var headroom: Float = 1
    var contentPeak: Float = 1
    var markerX: Float = 0.25
    var markerY: Float = 0.5
}

private struct ShaderLightLevels {
    var peak: UInt32 = 0
    var total: UInt32 = 0
    var samples: UInt32 = 0
    var above: UInt32 = 0
    var marker: UInt32 = 0
    var nearWhite: UInt32 = 0
}

private struct PQFrame {
    static let width = 64
    static let height = 32
    let luma: MTLTexture
    let chroma: MTLTexture

    init(device: MTLDevice, left: Double, right: Double) throws {
        luma = try #require(device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .r16Unorm, width: Self.width, height: Self.height, mipmapped: false
        )))
        chroma = try #require(device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .rg16Unorm, width: Self.width / 2, height: Self.height / 2, mipmapped: false
        )))
        let leftCode = Self.code(nits: left), rightCode = Self.code(nits: right)
        let lumaRows = (0..<Self.height).flatMap { _ in
            (0..<Self.width).map { column in
                column < Self.width / 2
                    ? leftCode
                    : rightCode
            }
        }
        let chromaRows = [UInt16](repeating: UInt16(512) << 6, count: Self.width * Self.height / 2)
        Self.fill(luma, with: lumaRows, width: Self.width, height: Self.height)
        Self.fill(chroma, with: chromaRows, width: Self.width / 2, height: Self.height / 2)
    }

    static func code(nits: Double) -> UInt16 {
        let exponent = 2610.0 / 16384, power = 2523.0 / 32
        let offset = 3424.0 / 4096, scale = 2413.0 / 128, divisor = 2392.0 / 128
        let level = pow(nits / 10000, exponent)
        let signal = pow((offset + scale * level) / (1 + divisor * level), power)
        return UInt16((64 + 876 * signal).rounded()) << 6
    }

    static func fill(_ texture: MTLTexture, with values: [UInt16], width: Int, height: Int) {
        values.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: bytes.baseAddress!, bytesPerRow: values.count / height * 2
            )
        }
    }
}

private func measure(_ frame: PQFrame, device: MTLDevice) throws -> ShaderLightLevels {
    let shaderURL = try #require(ChiakiAssets.url(forResource: "VideoColour", withExtension: "txt"))
    let library = try device.makeLibrary(source: String(contentsOf: shaderURL, encoding: .utf8), options: nil)
    let pipeline = try device.makeComputePipelineState(
        function: try #require(library.makeFunction(name: "light_levels"))
    )
    var config = ShaderColourConfig()
    var step = UInt32(1)
    let levels = try #require(device.makeBuffer(
        length: MemoryLayout<ShaderLightLevels>.size, options: .storageModeShared
    ))
    memset(levels.contents(), 0, MemoryLayout<ShaderLightLevels>.size)
    let command = try #require(device.makeCommandQueue()?.makeCommandBuffer())
    let encoder = try #require(command.makeComputeCommandEncoder())
    encoder.setComputePipelineState(pipeline)
    encoder.setBytes(&config, length: MemoryLayout<ShaderColourConfig>.size, index: 0)
    encoder.setBuffer(levels, offset: 0, index: 1)
    encoder.setBytes(&step, length: MemoryLayout<UInt32>.size, index: 2)
    encoder.setTexture(frame.luma, index: 0)
    encoder.setTexture(frame.chroma, index: 1)
    encoder.dispatchThreads(
        MTLSize(width: PQFrame.width, height: PQFrame.height, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
    )
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    return levels.contents().load(as: ShaderLightLevels.self)
}

@Test func lightLevelsMeasureThePeakAverageAndMarkerOfAPQFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try measure(PQFrame(device: device, left: 1000, right: 100), device: device)
    let pixels = UInt32(PQFrame.width * PQFrame.height)
    #expect(result.samples == pixels)
    #expect(abs(Double(Float(bitPattern: result.peak)) - 1000) < 15)
    #expect(abs(Double(result.total) / Double(result.samples) - 550) < 10)
    #expect(result.above == pixels / 2)
    #expect(abs(Double(Float(bitPattern: result.marker)) - 1000) < 15)
    #expect(result.nearWhite == 0)
}

@Test func lightLevelsCountAFrameThatStopsAtSDRWhite() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try measure(PQFrame(device: device, left: 203, right: 20), device: device)
    let pixels = UInt32(PQFrame.width * PQFrame.height)
    #expect(result.above == 0)
    #expect(result.nearWhite == pixels / 2)
}
