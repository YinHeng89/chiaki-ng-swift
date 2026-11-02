import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct AboutTests {
    @Test func loadingReadsTheCoreBuildAndTheBundledContributors() async {
        let build = CoreBuild(version: "2.0.0", commit: "abc123def456")
        let store = TestStore(initialState: AboutReducer.State()) {
            AboutReducer()
        } withDependencies: {
            $0.settings = SettingsClient.inMemory()
            $0.settings.coreBuild = {
                build
            }
        }
        let contributors = AboutReducer.bundledContributors
        #expect(contributors.prefix(3) == ["streetpea", "kyogre404", "xlanor"])
        await store.send(.load)
        await store.receive(.loaded(build, contributors)) {
            $0.coreBuild = build
            $0.contributors = contributors
        }
        await store.send(.toggleContributors) {
            $0.contributorsShown = true
        }
    }

    @Test func everyLinkOpensItsAddress() async {
        let opened = LockIsolated<[URL]>([])
        let store = TestStore(initialState: AboutReducer.State()) {
            AboutReducer()
        } withDependencies: {
            $0.openURL = OpenURLEffect { url in
                opened.withValue {
                    $0.append(url)
                }
                return true
            }
        }
        for link in AboutReducer.Link.allCases {
            await store.send(.open(link))
        }
        await store.send(.openContributor("kyogre404"))
        await store.send(.openContributor("not a login"))
        #expect(opened.value == AboutReducer.Link.allCases
            .map(\.url) + [URL(string: "https://github.com/kyogre404")!])
        #expect(AboutReducer.Link.discord.url.absoluteString == "https://discord.gg/tAMbRuwXDH")
        #expect(AboutReducer.Link.leadMaintainer.url.absoluteString == "https://github.com/streetpea")
        #expect(AboutReducer.Link.privacyPolicy.url.absoluteString
            == "https://github.com/chiaki-ng/chiaki-ng-swift/blob/main/PRIVACY.md")
    }
}
