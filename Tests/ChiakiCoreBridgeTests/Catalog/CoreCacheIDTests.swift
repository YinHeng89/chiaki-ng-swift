import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import Testing

@Test func everyCacheTheCoreNamesCrossesByItsNumber() {
    let all = (UInt8.min...UInt8.max).compactMap(libchiaking.catalog.CacheId.init(rawValue:))
    #expect(all == [
        libchiaking.catalog.CacheId.streamable_lists, libchiaking.catalog.CacheId.included_titles,
        libchiaking.catalog.CacheId.libraries,
        libchiaking.catalog.CacheId.refusals,
        libchiaking.catalog.CacheId.game_details, libchiaking.catalog.CacheId.images,
        libchiaking.catalog.CacheId.for_sale_titles, libchiaking.catalog.CacheId.played_games
    ])
}
