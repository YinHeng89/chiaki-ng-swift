@testable import ChiakiFeatures
import ChiakiDiagnostics
import ChiakiModels
import ChiakiTestSupport
import Foundation
import Testing

@Test func cloudEndAndHealthLinesCarryTheOutcome() {
    let failed = CloudSessionEnd(
        title: "Astro", outcome: .startFailed(.invalidArgument), cancelled: false, seconds: 12.34, decoded: 0,
        gpuErrors: 0,
        failureMessage: "PSNow title preparation failed: Game not free",
        diagnostics: "route=4 stage=32 domain=9 cause=9 error_message=\"GAME_NOT_FREE:4.99\""
    )
    #expect(failed.level == .error)
    #expect(
        failed.message == "Cloud stream of \"Astro\" failed after 12.3 s during PS Now title preparation: PSNow title "
            + "preparation failed: Game not free; service error GAME_NOT_FREE:4.99; 0 frames decoded, 0 GPU errors "
            + "[ending start_failed.invalid_argument; route=4 stage=32 domain=9 cause=9 "
            + "error_message=\"GAME_NOT_FREE:4.99\"]"
    )
    let stopped = CloudSessionEnd(
        title: "Astro", outcome: .left, cancelled: true, seconds: 60, decoded: 3600, gpuErrors: 0,
        failureMessage: nil, diagnostics: nil
    )
    #expect(stopped
        .message ==
        "Cloud stream of \"Astro\" was stopped by the user after 60.0 s: 3600 frames decoded, 0 GPU errors")
    var health = CloudHealth()
    let first = health.sample(RenderStatistics(fixture: ["received": 600, "lost": 0]), decoded: 600)
    #expect(first.level == .debug)
    let second = health.sample(RenderStatistics(fixture: ["received": 1200, "lost": 4]), decoded: 1190)
    #expect(second.level == .info)
    #expect(second.message.hasSuffix("losses or rejections grew in the last 10 s"))
}

@Test func cloudLibraryLineCountsTitlesAndLocale() throws {
    let json = Data(#"""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en","fallbackRegion":"US",
     "warning":null,"games":[
      {"productId":"A","name":"A","platform":"ps5","category":"game","isOwned":true,"plusCatalog":false,
       "streamServiceType":"pscloud","streamIdentifier":"a"},
      {"productId":"B","name":"B","platform":"ps4","category":"game","isOwned":false,"plusCatalog":true,
       "streamServiceType":"psnow","streamIdentifier":"b"}]}
    """#.utf8)
    let snapshot = try CloudLibrarySnapshot.decode(json)
    #expect(
        CloudLibraryLog.loaded(snapshot, who: "account 6f9619ff…", locale: "en-GB", milliseconds: 950)
            == "Fetched 2 titles for account 6f9619ff… in 950 ms: 1 owned, 1 in the PS Plus catalog, 1 PS Cloud "
            + "and 1 PS Now, 0 hidden; locale en-GB"
    )
}
