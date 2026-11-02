import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func datacenterIsSkippedWhenChosenAtLaunch() async throws {
        let harness = try cloudLibraryHarness(selectsAtLaunch: true)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        let filters = CloudLibraryFeature.State().filters.count
        await harness.send([.up] + Array(repeating: .right, count: filters + 2))
        let platform = harness.window.firstResponder
        #expect(harness.focusedFrame.width > 30 && harness.focusedFrame.width < 120)
        await harness.send(.left)
        await harness.pause(200)
        #expect(harness.window.firstResponder !== platform)
        #expect(harness.focusedFrame.width < 60)
        await harness.send(.right)
        #expect(harness.window.firstResponder === platform)
    }

    @Test func launchPickerStartsOnTheLowestPingAndPicksOrCancelsWithoutButtons() async {
        let offer = CloudDatacenterLaunchOffer(rows: [
            CloudDatacenterPingRow(
                name: "eu-west-1", rtt: 91, rtts: [91], mtuIn: 0, mtuOut: 0, port: 0,
                publicIP: "", maxBandwidth: 0, measured: true
            ),
            CloudDatacenterPingRow(
                name: "us-east-1", rtt: 34, rtts: [34], mtuIn: 0, mtuOut: 0, port: 0,
                publicIP: "", maxBandwidth: 0, measured: true
            ),
            CloudDatacenterPingRow(
                name: "us-west-2", rtt: 62, rtts: [62], mtuIn: 0, mtuOut: 0, port: 0,
                publicIP: "", maxBandwidth: 0, measured: true
            )
        ])
        var chosen: [String] = []
        var cancelled = 0
        let harness = MenuFocusHarness(width: 800, height: 600) { _ in
            MenuFocusHostingView(rootView: CloudDatacenterLaunchPickerView(
                offer: offer,
                remaining: 12,
                pending: nil,
                choose: { chosen.append($0) },
                cancel: { cancelled += 1 }
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        let lowest = harness.focusedFrame.integral
        #expect(lowest.width > 250)
        await harness.send(.down)
        let next = harness.focusedFrame.integral
        #expect(next.maxY <= lowest.minY + 1)
        await harness.send(.down)
        await harness.send(.down)
        let last = harness.focusedFrame.integral
        #expect(last.maxY <= next.minY + 1)
        await harness.send([.up, .up])
        #expect(harness.focusedFrame.integral == lowest)
        #expect(chosen.isEmpty && cancelled == 0)
        await harness.send(.down)
        await harness.send(.confirm)
        #expect(chosen == ["us-west-2"])
        await harness.send(.back)
        #expect(cancelled == 1)
    }

    @Test func launchPickerTakesFocusFromTheLayeredCancelWhenItArrivesLate() async throws {
        let offer = CloudDatacenterLaunchOffer(rows: [
            CloudDatacenterPingRow(
                name: "eu-west-1", rtt: 91, rtts: [91], mtuIn: 0, mtuOut: 0, port: 0,
                publicIP: "", maxBandwidth: 0, measured: true
            ),
            CloudDatacenterPingRow(
                name: "us-east-1", rtt: 34, rtts: [34], mtuIn: 0, mtuOut: 0, port: 0,
                publicIP: "", maxBandwidth: 0, measured: true
            )
        ])
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let pixel = try #require(context.makeImage())
        let layers = GameArtLayers(background: pixel, hero: pixel, logo: pixel)
        let calls = StreamSessionCalls()
        let session = StreamSessionID(uuid: UUID(0))
        let store = findingServer(calls, layers: layers, session: session)
        let harness = MenuFocusHarness(width: 1000, height: 700) { _ in
            MenuFocusHostingView(rootView: StreamView(store: store) {
                EmptyView()
            }
            .environment(\.controllerNavigation, testControllerNavigation))
        }
        let override = KeyWindowOverride(harness.window)
        defer {
            store.send(.stop)
            override.restore()
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        let cancelButton = try #require(harness.focusedView)
        #expect(cancelButton.bounds.width > 0 && cancelButton.bounds.width < 200)
        store.send(.event(session, .datacenterOffered(offer)))
        await harness.pause(30)
        harness.window.makeFirstResponder(cancelButton)
        await harness.pause(500)
        #expect(harness.focusedFrame.width > 250)
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(calls.datacenters.value == ["us-east-1"])
        #expect(calls.left.value.isEmpty)
    }

    private func findingServer(
        _ calls: StreamSessionCalls,
        layers: GameArtLayers,
        session: StreamSessionID
    ) -> StoreOf<StreamFeature> {
        let store = Store(initialState: StreamFeature.State()) {
            StreamFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
            $0.streamSession = calls.client(on: $0.streamSession)
            $0.catalog.knownArtLayers = { _ in
                layers
            }
            $0.idleKakusanHosting()
        }
        store.send(.start(.cloud(CloudStreamRequest(
            profile: ProfileID(uuid: UUID()),
            title: CloudStreamTitle(
                product: ProductID(rawValue: "EP0000-PPSA00000_00-GAME000000000000")!,
                name: "Game",
                service: .psCloud
            )
        ))))
        store.send(.event(session, .cloudStep(.findingServer)))
        return store
    }

    private func cloudLibraryHarness(selectsAtLaunch: Bool) throws -> MenuFocusHarness {
        let games = (0..<6).map { index in
            """
            {"productId":"game-\(index)","name":"Game \(index)","platform":"ps5",
            "category":"owned","isOwned":true,"plusCatalog":true,
            "streamServiceType":"pscloud","streamIdentifier":"game-\(index)"}
            """
        }.joined(separator: ",")
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[\(games)]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.cloud.loadDatacenters = {
                CloudDatacenterSettings()
                    .connecting(to: "us-east-1", rttMs: 34, service: .psCloud, at: Date())
                    .selectingAtLaunch(selectsAtLaunch)
            }
        }
        return MenuFocusHarness(width: 1300, height: 800) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
        }
    }
}
