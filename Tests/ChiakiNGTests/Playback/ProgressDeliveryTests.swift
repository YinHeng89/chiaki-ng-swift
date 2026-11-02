import ChiakiAssets
import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCore
import ChiakiCoreBridge
import ChiakiModels
import Foundation
import Testing
import Video

private struct Carried<Value>: @unchecked Sendable {
    let value: Value
}

@MainActor private final class Arrivals {
    var reports: [OperationProgress?] = []
    var steps: [CloudStartStep?] = []
    var onMainThread: [Bool] = []

    func saw(_ report: OperationProgress?) {
        reports.append(report)
        onMainThread.append(Thread.isMainThread)
    }
}

@Suite(.serialized) @MainActor struct ProgressDeliveryTests {
    private func player() throws -> Carried<CNLiveVideoPlayer> {
        let shader = try #require(ChiakiAssets.url(forResource: "VideoColour", withExtension: "txt"))
        let weights = try #require(ChiakiAssets.url(forResource: "FSRCNNX16", withExtension: "bin"))
        return Carried(value: try #require(CNLiveVideoPlayer(
            shader: try String(contentsOf: shader, encoding: .utf8),
            fsrcnnWeights: try Data(contentsOf: weights)
        )))
    }

    private func offTheMainThread(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                work()
                done.resume()
            }
        }
        await withCheckedContinuation { (drained: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                drained.resume()
            }
        }
    }

    private func reserving() throws -> libchiaking.play.LaunchProgress {
        var counts = libchiaking.play.LaunchProgress.Counts()
        counts.step = .init(libchiaking.progress.Position(number: 7, of: 10))
        return try #require(libchiaking.play.LaunchProgress.at(.ps5_cloud, .reserving_server, counts).value)
    }

    @Test func aConnectReportReachesSwiftOnTheMainThreadWithItsRoute() async throws {
        let player = try player()
        let arrivals = Arrivals()
        let deliver: @Sendable () -> Void = {
            var report = libchiaking.play.ConnectProgress()
            report.step = .reaching_console
            report.attempt = 4
            var route = libchiaking.progress.InternetRoute()
            route.step = .route_chosen
            route.purpose = .stream
            route.chosen = .init(.discovered)
            report.route = .init(route)
            player.value.deliver(report)
        }
        player.value.connectProgressHandler = { progress in
            arrivals.saw(OperationProgressReader.progress(of: progress.pointee))
        }
        await offTheMainThread(deliver)
        #expect(arrivals.reports == [
            OperationProgress(
                step: .connect(.reachingConsole),
                attempt: 4,
                elapsedMilliseconds: 0,
                route: OperationProgress.Route(step: .routeChosen, purpose: .stream, chosen: .discovered)
            )
        ])
        #expect(arrivals.onMainThread == [true])
        player.value.connectProgressHandler = nil
        await offTheMainThread(deliver)
        #expect(arrivals.reports.count == 1)
    }

    @Test func aLaunchReportReachesSwiftOnTheMainThreadWithItsStep() async throws {
        let player = try player()
        let arrivals = Arrivals()
        let report = try reserving()
        let carried = Carried(value: report)
        let deliver: @Sendable (Bool) -> Void = { playing in
            player.value.deliver(carried.value, playing: playing)
        }
        player.value.launchProgressHandler = { progress, playing in
            arrivals.saw(OperationProgressReader.progress(of: progress.pointee))
            arrivals.steps.append(OperationProgressReader.step(of: progress.pointee, playing: playing))
        }
        await offTheMainThread {
            deliver(false)
        }
        #expect(arrivals.reports == [
            OperationProgress(
                step: .launch(.reservingServer),
                position: .init(number: 7, total: 10),
                attempt: 0
            )
        ])
        #expect(arrivals.steps == [OperationProgressReader.step(of: report, playing: false)])
        #expect(arrivals.steps.count == 1 && arrivals.steps[0] != nil)
        #expect(arrivals.onMainThread == [true])
        await offTheMainThread {
            deliver(true)
        }
        #expect(arrivals.steps.count == 2 && arrivals.steps[1] == nil)
        player.value.launchProgressHandler = nil
        await offTheMainThread {
            deliver(false)
        }
        #expect(arrivals.reports.count == 2)
    }
}
