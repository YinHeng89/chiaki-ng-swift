import ChiakiModels
import Testing

@Suite struct ConsoleRouteTests {
    @Test func anInternetStartTheUserAskedForNeverAsksTheCore() async {
        let chosen = await ConsoleRoute.resolve(internetAsked: true) {
            Issue.record("the core was asked")
            return .home
        }
        #expect(chosen == .internet)
        #expect(chosen.overInternet)
    }

    @Test(arguments: [
        (ConsoleRoute?.some(.home), ConsoleRoute.home),
        (ConsoleRoute?.some(.internet), ConsoleRoute.internet),
        (ConsoleRoute?.none, ConsoleRoute.home)
    ])
    func anAutomaticStartFollowsTheRouteTheCoreChose(
        core: ConsoleRoute?,
        expected: ConsoleRoute
    ) async {
        let chosen = await ConsoleRoute.resolve(internetAsked: false) {
            core
        }
        #expect(chosen == expected)
        #expect(chosen.overInternet == (expected == .internet))
    }
}
