import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    private struct StreamTrophiesMenu {
        let menu: StoreOf<StreamMenuReducer>
        let trophies: StoreOf<StreamTrophiesFeature>
        let harness: MenuFocusHarness
    }

    @MainActor private func streamTrophiesMenu(
        reads: LockIsolated<Int>,
        earnedLater: Bool = false,
        extraTrophies: Int = 0,
        height: CGFloat = 900
    ) -> StreamTrophiesMenu {
        let extra = (0 ..< extraTrophies).map { index in
            PSNTrophy(id: 2 + index, grade: .bronze, name: "Trophy \(index + 1)")
        }
        let current = CurrentTrophies(
            title: TrophyTitle(id: "NPWR07028_00", name: "UNCHARTED 4", progress: 2),
            trophies: TitleTrophies(groups: [], trophies: [
                PSNTrophy(id: 0, grade: .bronze, name: "Start", earned: true),
                PSNTrophy(id: 1, grade: .gold, name: "Secret", hidden: true)
            ] + extra)
        )
        let trophiesClient = PSNTrophiesClient(
            summary: { _ throws(PSNTrophiesFailure) in
                throw .unavailable
            },
            titles: { _ throws(PSNTrophiesFailure) in
                throw .unavailable
            },
            trophies: { _, _ throws(PSNTrophiesFailure) in
                throw .unavailable
            },
            current: { _, _ throws(PSNTrophiesFailure) in
                let read = reads.withValue {
                    $0 += 1
                    return $0
                }
                guard earnedLater, read > 1 else {
                    return current
                }
                var earned = current
                earned.trophies.trophies[1].earned = true
                return earned
            }
        )
        let menu = Store(initialState: StreamMenuReducer.State(context: .cloud("psnow"))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        let trophies = Store(initialState: StreamTrophiesFeature.State(
            profile: ProfileID(uuid: UUID(0)),
            titleIDs: ["CUSA00341_00"]
        )) {
            StreamTrophiesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.psnTrophies = trophiesClient
        }
        let harness = MenuFocusHarness(width: 1000, height: height) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(
                store: menu,
                stopTitle: "Disconnect",
                trophies: trophies
            )
            .frame(width: 1000, height: height))
        }
        return StreamTrophiesMenu(menu: menu, trophies: trophies, harness: harness)
    }

    @Test func streamTrophiesAreRevealedFilteredAndRefreshedWithTheController() async {
        let reads = LockIsolated(0)
        let opened = streamTrophiesMenu(reads: reads)
        let menu = opened.menu
        let trophies = opened.trophies
        let harness = opened.harness
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(300)
        while menu.navigation.panel != .trophies {
            let before = menu.navigation.panel
            await harness.send(.next)
            await harness.pause(200)
            if menu.navigation.panel == before {
                break
            }
        }
        #expect(menu.navigation.panel == .trophies)
        await waitUntil(harness) {
            trophies.current != nil
        }
        #expect(reads.value == 1)
        await harness.send([.up, .down, .confirm])
        await harness.pause(200)
        #expect(trophies.revealed == [1])
        await harness.send([.up, .up, .up, .up, .right])
        await harness.pause(200)
        #expect(trophies.filter == .earned)
        #expect(trophies.shown.map(\.id) == [0])
        await harness.send([.up, .confirm])
        await waitUntil(harness) {
            reads.value == 2
        }
        #expect(reads.value == 2)
    }

    @Test func backFromALongTrophiesPanelReturnsToItsTabFirst() async {
        let reads = LockIsolated(0)
        let opened = streamTrophiesMenu(reads: reads, extraTrophies: 40, height: 700)
        let menu = opened.menu
        let trophies = opened.trophies
        let harness = opened.harness
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(300)
        while menu.navigation.panel != .trophies {
            let before = menu.navigation.panel
            await harness.send(.next)
            await harness.pause(200)
            if menu.navigation.panel == before {
                break
            }
        }
        #expect(menu.navigation.panel == .trophies)
        await waitUntil(harness) {
            trophies.current != nil
        }
        await harness.send(.up)
        for _ in 0 ..< 12 {
            await harness.send(.up)
        }
        await harness.pause(300)
        await harness.send(.back)
        await harness.pause(300)
        #expect(menu.navigation.level == .panel)
        await harness.send([.right, .confirm])
        await harness.pause(300)
        #expect(menu.navigation.panel != .trophies)
        await harness.send(.back)
        await harness.pause(200)
        #expect(menu.navigation.level == .panel)
        await harness.send(.back)
        await harness.pause(200)
        #expect(menu.navigation.level == .gameplay)
    }

    @Test func aReopenedTrophiesPanelIsEnteredAtItsTopAndWalkedIntoItsList() async {
        let reads = LockIsolated(0)
        let opened = streamTrophiesMenu(reads: reads, extraTrophies: 40, height: 700)
        let menu = opened.menu
        let trophies = opened.trophies
        let harness = opened.harness
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(300)
        while menu.navigation.panel != .trophies {
            let before = menu.navigation.panel
            await harness.send(.next)
            await harness.pause(200)
            if menu.navigation.panel == before {
                break
            }
        }
        await waitUntil(harness) {
            trophies.current != nil
        }
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(300)
        #expect(menu.navigation.level == .gameplay)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(400)
        #expect(menu.navigation.panel == .trophies)
        let readsBefore = reads.value
        await harness.send(.up)
        await harness.pause(200)
        #expect(reads.value == readsBefore)
        await harness.send([.down, .confirm])
        await harness.pause(200)
        #expect(trophies.revealed == [1])
    }

    @Test func squareJumpsToTheStreamTrophiesFilter() async {
        let reads = LockIsolated(0)
        let opened = streamTrophiesMenu(reads: reads, extraTrophies: 40, height: 700)
        let menu = opened.menu
        let trophies = opened.trophies
        let harness = opened.harness
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(300)
        while menu.navigation.panel != .trophies {
            let before = menu.navigation.panel
            await harness.send(.next)
            await harness.pause(200)
            if menu.navigation.panel == before {
                break
            }
        }
        await waitUntil(harness) {
            trophies.current != nil
        }
        await harness.send(.up)
        await harness.send(Array(repeating: .down, count: 15))
        await harness.pause(200)
        await harness.send([.alternate, .right])
        await harness.pause(200)
        #expect(trophies.filter == .earned)
    }

    @Test func streamTrophiesKeepFocusWhenTheFocusedTrophyLeavesTheList() async {
        let reads = LockIsolated(0)
        let opened = streamTrophiesMenu(reads: reads, earnedLater: true)
        let menu = opened.menu
        let trophies = opened.trophies
        let harness = opened.harness
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(300)
        while menu.navigation.panel != .trophies {
            let before = menu.navigation.panel
            await harness.send(.next)
            await harness.pause(200)
            if menu.navigation.panel == before {
                break
            }
        }
        await waitUntil(harness) {
            trophies.current != nil
        }
        await harness.send([.up, .up, .up, .up, .right, .right])
        await harness.pause(200)
        #expect(trophies.filter == .unearned)
        await harness.send([.down, .down])
        await harness.pause(200)
        trophies.send(.refresh)
        await waitUntil(harness) {
            reads.value == 2 && trophies.shown.isEmpty
        }
        await harness.pause(300)
        await harness.send([.up, .up])
        await harness.pause(200)
        await harness.send(.right)
        await harness.pause(200)
        #expect(trophies.filter == .all)
    }
}
