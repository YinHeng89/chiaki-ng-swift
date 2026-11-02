import ChiakiClients
import ChiakiModels
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ChiakiClientsLive
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private func jpeg(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1)
    context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func image(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    return try #require(context.makeImage())
}

@Test func artworkBoxBucketsTheDisplayedCardSize() throws {
    let card = try #require(ArtworkBox(points: CGSize(width: 210, height: 280), scale: 2))
    #expect(card == ArtworkBox(width: 448, height: 576))
    let widest = try #require(ArtworkBox(points: CGSize(width: 280, height: 373.4), scale: 2))
    #expect(widest == ArtworkBox(width: 576, height: 768))
    let oneX = try #require(ArtworkBox(points: CGSize(width: 210, height: 280), scale: 1))
    #expect(oneX == ArtworkBox(width: 256, height: 320))
}

@Test func artworkBoxIgnoresSmallLayoutJitterAndClamps() throws {
    let base = try #require(ArtworkBox(points: CGSize(width: 210, height: 280), scale: 2))
    let jittered = try #require(ArtworkBox(points: CGSize(width: 211.5, height: 281.5), scale: 2))
    #expect(base == jittered)
    #expect(ArtworkBox(width: 1, height: 1) == ArtworkBox(width: 128, height: 128))
    #expect(ArtworkBox(width: 9_000, height: 9_000) == ArtworkBox(width: 2_560, height: 2_560))
    #expect(ArtworkBox(points: .zero, scale: 2) == nil)
    #expect(ArtworkBox(points: CGSize(width: 10, height: 10), scale: 0) == nil)
}

@Test func artworkBoxCoverageAndUnion() {
    let small = ArtworkBox(width: 448, height: 576)
    let detail = ArtworkBox(width: 760, height: 1_320)
    #expect(detail.covers(small))
    #expect(!small.covers(detail))
    #expect(small.covers(small))
    let wide = ArtworkBox(width: 896, height: 200)
    #expect(small.union(wide) == ArtworkBox(width: 896, height: 576))
}

@Test func fillPixelSizeMatchesAspectFillWithoutUpscaling() {
    let card = ArtworkBox(width: 448, height: 576)
    #expect(card.fillPixelSize(sourceWidth: 1_024, sourceHeight: 1_024) == 576)
    #expect(card.fillPixelSize(sourceWidth: 2_048, sourceHeight: 1_152) == 1_024)
    #expect(card.fillPixelSize(sourceWidth: 1_080, sourceHeight: 1_440) == 598)
    #expect(card.fillPixelSize(sourceWidth: 256, sourceHeight: 256) == 256)
    #expect(card.fillPixelSize(sourceWidth: 0, sourceHeight: 0) == 576)
}

@Test func decodeProducesTheCardSizeInsteadOfAFixed768() throws {
    let data = try jpeg(width: 1_024, height: 1_024)
    let card = try #require(ArtworkBox(points: CGSize(width: 210, height: 280), scale: 2))
    let decoded = try #require(ArtworkDecoder.decode(data, box: card))
    #expect(decoded.width == 576)
    #expect(decoded.height == 576)
    let portrait = try jpeg(width: 1_080, height: 1_440)
    let tall = try #require(ArtworkDecoder.decode(portrait, box: card))
    #expect(abs(tall.height - 598) <= 1)
    #expect(abs(tall.width - 448) <= 1)
}

@Test func cacheHitIsSynchronousAndReturnsTheStoredImage() throws {
    let cache = ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16)
    let url = try #require(URL(string: "https://image.example.test/cover.png"))
    let card = ArtworkBox(width: 448, height: 576)
    #expect(cache.image(for: url) == nil)
    let stored = try image(width: 576, height: 576)
    cache.store(stored, for: url, box: card)
    #expect(cache.image(for: url) === stored)
    #expect(cache.image(for: url, box: card) === stored)
    #expect(cache.image(for: url, box: ArtworkBox(width: 256, height: 320)) === stored)
    #expect(cache.image(for: url, box: ArtworkBox(width: 760, height: 1_320)) == nil)
    #expect(cache.box(for: url) == card)
}

@Test func cacheKeepsTheLargerDecodeForAURL() throws {
    let cache = ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16)
    let url = try #require(URL(string: "https://image.example.test/cover.png"))
    let detail = ArtworkBox(width: 768, height: 1_344)
    let large = try image(width: 1_344, height: 1_344)
    cache.store(large, for: url, box: detail)
    cache.store(try image(width: 576, height: 576), for: url, box: ArtworkBox(width: 448, height: 576))
    #expect(cache.image(for: url, box: ArtworkBox(width: 448, height: 576)) === large)
    #expect(cache.box(for: url) == detail)
}

@Test func thumbnailCacheHoldsSeveralScreensOfCards() throws {
    let card = ArtworkBox(width: 448, height: 576)
    let data = try jpeg(width: 1_024, height: 1_024)
    let decoded = try #require(ArtworkDecoder.decode(data, box: card))
    let cost = decoded.bytesPerRow * decoded.height
    let covers = 256 * 1024 * 1024 / cost
    #expect(covers >= 180)
}

private func shelves(thumbnails: ArtworkCache, heroes: ArtworkCache) -> ArtworkPipeline.Shelves {
    ArtworkPipeline.Shelves(
        thumbnails: thumbnails,
        heroes: heroes,
        gameArt: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16),
        trailers: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16)
    )
}

private actor CoreAnswers {
    private var asked: [URL] = []
    private var finished = 0
    private var cancelled = 0
    private var gate: [CheckedContinuation<Void, Never>] = []
    private var open: Bool

    init(open: Bool) {
        self.open = open
    }

    var questions: [URL] {
        asked
    }

    var cancellations: Int {
        cancelled
    }

    func answer(_ url: URL, with data: Data) async throws -> Data {
        asked.append(url)
        if !open {
            await withCheckedContinuation { continuation in
                gate.append(continuation)
            }
        }
        if Task.isCancelled {
            cancelled += 1
            throw CancellationError()
        }
        finished += 1
        return data
    }

    func release() {
        open = true
        let waiting = gate
        gate = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    func waitUntilAsked(_ count: Int) async {
        while asked.count < count {
            await Task.yield()
        }
    }
}

private func until(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

@Test func theArtworkClientAsksTheCoreAndDecodes() async throws {
    let data = try jpeg(width: 1_024, height: 1_024)
    let core = CoreAnswers(open: true)
    let thumbnails = ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16)
    let client = ArtworkPipeline(shelves: shelves(
        thumbnails: thumbnails,
        heroes: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 4)
    )) { url in
        try await core.answer(url, with: data)
    }
    let url = try #require(URL(string: "https://image.api.playstation.com/cover.png"))
    let card = ArtworkBox(width: 448, height: 576)
    let image = try await client.thumbnail(url, box: card)
    #expect(image.width == 576)
    #expect(thumbnails.image(for: url, box: card) === image)
    #expect(await core.questions == [url])
    let again = try await client.thumbnail(url, box: card)
    #expect(again === image)
    #expect(await core.questions == [url])
    let hero = try await client.hero(url)
    #expect(hero.width == 1_024)
    #expect(await core.questions == [url, url])
    #expect(await client.fetching == 0)
}

@Test func identicalArtworkRequestsShareOneCoreAnswer() async throws {
    let data = try jpeg(width: 512, height: 512)
    let core = CoreAnswers(open: false)
    let client = ArtworkPipeline(shelves: shelves(
        thumbnails: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16),
        heroes: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 4)
    )) { url in
        try await core.answer(url, with: data)
    }
    let url = try #require(URL(string: "https://image.api.playstation.com/shared.png"))
    let card = ArtworkBox(width: 256, height: 256)
    let images = await withTaskGroup(of: CGImage?.self) { group in
        for _ in 0..<12 {
            group.addTask {
                try? await client.thumbnail(url, box: card)
            }
        }
        await core.waitUntilAsked(1)
        try? await Task.sleep(for: .milliseconds(30))
        await core.release()
        return await group.reduce(into: [CGImage?]()) { $0.append($1) }
    }
    #expect(images.count == 12)
    #expect(images.allSatisfy { $0 != nil })
    #expect(await core.questions == [url])
}

@Test func artworkLeftByEveryTileCancelsItsCoreRequest() async throws {
    let data = try jpeg(width: 512, height: 512)
    let core = CoreAnswers(open: false)
    let client = ArtworkPipeline(shelves: shelves(
        thumbnails: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16),
        heroes: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 4)
    )) { url in
        try await core.answer(url, with: data)
    }
    let cover = try #require(URL(string: "https://image.api.playstation.com/gone.png"))
    let hero = try #require(URL(string: "https://image.api.playstation.com/hero.png"))
    let card = ArtworkBox(width: 256, height: 256)
    let first = Task {
        try await client.thumbnail(cover, box: card)
    }
    let second = Task {
        try await client.thumbnail(cover, box: card)
    }
    let shown = Task {
        try await client.hero(hero)
    }
    await core.waitUntilAsked(2)
    #expect(await until { await client.fetching == 2 })
    first.cancel()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await client.fetching == 2)
    second.cancel()
    shown.cancel()
    #expect(await until { await client.fetching == 0 })
    await core.release()
    #expect(await until { await core.cancellations == 2 })
    #expect((try? await first.value) == nil)
    #expect((try? await second.value) == nil)
    #expect((try? await shown.value) == nil)
}

@Test func anOversizedThumbnailIsRefused() async throws {
    let core = CoreAnswers(open: true)
    let thumbnails = ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 16)
    let client = ArtworkPipeline(shelves: shelves(
        thumbnails: thumbnails,
        heroes: ArtworkCache(costLimit: 64 * 1024 * 1024, countLimit: 4)
    )) { url in
        try await core.answer(url, with: Data(count: ArtworkPipeline.thumbnailBytes + 1))
    }
    let url = try #require(URL(string: "https://image.api.playstation.com/huge.png"))
    await #expect(throws: URLError.self) {
        try await client.thumbnail(url, box: ArtworkBox(width: 256, height: 256))
    }
    #expect(thumbnails.image(for: url) == nil)
}
