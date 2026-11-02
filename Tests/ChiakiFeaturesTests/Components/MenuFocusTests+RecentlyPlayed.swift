import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    private func recentLibrary(
        marks: [String: CloudTrialMark] = [:]
    ) -> (StoreOf<LibraryFeature>, MenuFocusHarness) {
        let console = FeatureFocusStores.console(1)
        let store = FeatureFocusStores.libraryStore(consoles: [console]) { state in
            state.recentlyPlayed.selection = .init(profileID: state.selectedAccount ?? UUID(), eligible: true)
            state.recentlyPlayed.phase = .loaded
            state.recentlyPlayed.rails = [RecentlyPlayedRail(
                consoleID: console.id ?? UUID(),
                hardwareID: fixtureHardware,
                titles: RecentlyPlayedRailHost.titles
            )]
            state.recentlyPlayed.trialMarks = marks
        }
        let harness = MenuFocusHarness(width: 1000, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store)
                .transaction { $0.disablesAnimations = true })
        }
        return (store, harness)
    }

    private func enterRecentlyPlayed(
        _ store: StoreOf<LibraryFeature>,
        harness: MenuFocusHarness
    ) async -> Int? {
        await harness.open()
        await waitUntil(harness) {
            if case .console = store.heldFocus {
                return true
            }
            return false
        }
        await harness.send(.down)
        await waitUntil(harness) {
            recentIndex(store.heldFocus) != nil
        }
        await harness.pause(250)
        return recentIndex(store.heldFocus)
    }

    private func recentIndex(_ focus: ConsoleLibraryFocus?) -> Int? {
        guard case let .recentTitle(_, titleID) = focus else {
            return nil
        }
        return RecentlyPlayedRailHost.titles.firstIndex { $0.titleID == titleID }
    }

    @Test func recentlyPlayedRailScrollsToKeepTheFocusedTitleVisible() async {
        let focus = RecentRailFocusProbe()
        let harness = MenuFocusHarness(width: 640, height: 420) { _ in
            MenuFocusHostingView(rootView: RecentlyPlayedRailHost(focus: focus))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        for index in RecentlyPlayedRailHost.titles.indices {
            focus.request = RecentlyPlayedRailHost.target(index)
            await harness.pause(250)
            #expect(focus.focus == RecentlyPlayedRailHost.target(index))
            let frame = harness.focusedFrame
            #expect(frame.minX >= 0 && frame.maxX <= harness.window.frame.width, "title \(index) at \(frame)")
        }
    }

    @Test func trialBadgesOnRailTitlesAreNotFocusStops() async throws {
        let titles = RecentlyPlayedRailHost.titles
        let marks = Dictionary(uniqueKeysWithValues: titles.prefix(4).map {
            ($0.titleID, CloudTrialMark(icon: .trial, label: "Trial"))
        })
        let (store, harness) = recentLibrary(marks: marks)
        defer {
            harness.close()
        }
        let first = try #require(await enterRecentlyPlayed(store, harness: harness))
        let firstFrame = harness.focusedFrame
        for index in first + 1 ... first + 2 {
            await harness.send(.right)
            await harness.pause(250)
            #expect(recentIndex(store.heldFocus) == index)
        }
        for index in [first + 1, first] {
            await harness.send(.left)
            await harness.pause(250)
            #expect(recentIndex(store.heldFocus) == index)
        }
        #expect(harness.focusedFrame == firstFrame)
    }

    @Test func holdingAnArrowKeyKeepsMovingFocus() async throws {
        let (store, harness) = recentLibrary()
        defer {
            harness.close()
        }
        let first = try #require(await enterRecentlyPlayed(store, harness: harness))
        for repeated in [false, true, true, true] {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: harness.window.windowNumber, context: nil,
                characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}",
                isARepeat: repeated, keyCode: 124
            ) else {
                continue
            }
            #expect(testNavigator.renewsArrowPress(event) == repeated)
            harness.window.sendEvent(repeated
                ? AppKitMenuNavigator.freshArrowPress(event)
                : event)
            await harness.pause(150)
        }
        #expect(recentIndex(store.heldFocus) == first + 4)
    }

    @Test func pageButtonsScrollTheRailForPointerUsers() async {
        let rail = RailOffsetProbe()
        let harness = MenuFocusHarness(width: 640, height: 420) { _ in
            MenuFocusHostingView(rootView: RecentlyPlayedRailHost(rail: rail))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            rail.maximum > 300
        }
        #expect(rail.offset == 0)
        click(CGPoint(x: 570, y: 388), in: harness.window)
        await harness.pause(300)
        #expect(rail.offset == 0)
        click(CGPoint(x: 604, y: 388), in: harness.window)
        await waitUntil(harness) {
            rail.offset > 300
        }
        #expect(rail.offset > 300, "\(rail.offset)")
        for _ in 0 ..< 6 {
            let before = rail.offset
            click(CGPoint(x: 604, y: 388), in: harness.window)
            await waitUntil(harness) {
                rail.offset != before || abs(rail.offset - rail.maximum) < 1
            }
            await harness.pause(200)
        }
        #expect(abs(rail.offset - rail.maximum) < 1, "\(rail.offset) \(rail.maximum)")
        click(CGPoint(x: 570, y: 388), in: harness.window)
        await waitUntil(harness) {
            rail.offset < rail.maximum - 300
        }
        #expect(rail.offset < rail.maximum - 300, "\(rail.offset) \(rail.maximum)")
    }

    @Test func pageButtonsStayOutOfKeyboardAndControllerFocus() async {
        let harness = MenuFocusHarness(width: 640, height: 420) { _ in
            MenuFocusHostingView(rootView: RecentlyPlayedRailHost())
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        let pager = CGRect(x: 540, y: 365, width: 100, height: 45)
        for backward in [true, false] {
            for step in 0 ..< 12 {
                testNavigator.move(backward: backward, in: harness.window)
                await harness.pause(60)
                let frame = harness.focusedFrame
                #expect(!frame.intersects(pager), "backward \(backward) step \(step) \(frame)")
            }
        }
    }
}

@MainActor final class RecentRailFocusProbe {
    var request: ConsoleLibraryFocus?
    var focus: ConsoleLibraryFocus?
}

@MainActor final class RailOffsetProbe {
    var offset: CGFloat = 0
    var maximum: CGFloat = 0
}

struct RecentlyPlayedRailHost: View {
    static let consoleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let titles = (0 ..< 10).map { index in
        RecentTitle(
            titleID: "PPSA0000\(index)_00", launchID: "PPSA0000\(index)", name: "Game \(index)",
            imageURL: "", recent: true
        )
    }

    static func target(_ index: Int) -> ConsoleLibraryFocus {
        .recentTitle(consoleID, titles[index].titleID)
    }

    var rail: RailOffsetProbe?
    var focus: RecentRailFocusProbe?
    @State private var recentlyPlayed: RecentlyPlayedReducer.State = {
        var state = RecentlyPlayedReducer.State()
        state.selection = .init(profileID: UUID(), eligible: true)
        state.phase = .loaded
        state.rails = [RecentlyPlayedRail(consoleID: consoleID, hardwareID: fixtureHardware, titles: titles)]
        return state
    }()

    @MenuFocusState private var focused: ConsoleLibraryFocus?

    var body: some View {
        RecentlyPlayedSection(
            recentlyPlayed: recentlyPlayed,
            consoles: [RegistrationFlow.ConsoleTarget(address: "fixture", kind: .ps5, id: Self.consoleID)],
            busy: false,
            play: { _, _ in
            },
            focus: $focused,
            move: { _, _ in
            }
        )
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            CGRect(
                x: geometry.contentOffset.x,
                y: 0,
                width: max(0, geometry.contentSize.width - geometry.containerSize.width),
                height: 0
            )
        } action: { _, value in
            rail?.offset = value.minX
            rail?.maximum = value.width
        }
        .transaction { $0.disablesAnimations = true }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: focused) { _, value in
            focus?.focus = value
        }
        .task {
            while !Task.isCancelled {
                if let request = focus?.request {
                    focus?.request = nil
                    focused = request
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}

@MainActor
func waitUntil(_ harness: MenuFocusHarness, attempts: Int = 60, _ condition: () -> Bool) async {
    for _ in 0 ..< attempts {
        if condition() {
            return
        }
        await harness.pause(50)
    }
}

private let fixtureHardware = Data(repeating: 0xa1, count: 6)
