import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@MainActor @Test func privacySettingsErrorOffersTheAccountUpgradePage() {
    let message = "PSNow: Account privacy validation — PlayStation account privacy settings need to be completed. "
        + "Detail 7. HTTP 400. https://id.sonyentertainmentnetwork.com/id/upgrade_account_ca/"
        + "?entry=upgrade_account&applicationId=psnow"
    let link = CopyableErrorMessage.link(in: message)
    #expect(link?.host == "id.sonyentertainmentnetwork.com")
    #expect(link?.query?.contains("applicationId=psnow") == true)
}

@MainActor @Test func errorWithoutHttpsLinkOffersNoPage() {
    #expect(CopyableErrorMessage.link(in: "The console refused the connection (4617).") == nil)
    #expect(CopyableErrorMessage.link(in: "See http://example.com for details") == nil)
}
