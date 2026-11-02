import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let firstSession = StreamSessionID(uuid: UUID(0))

private func cloudSource() -> StreamSource {
    .cloud(CloudStreamRequest(
        profile: ProfileID(uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!),
        title: CloudStreamTitle(
            product: ProductID(rawValue: "EP0000-PPSA00000_00-GAME000000000000")!,
            name: "Example",
            service: .psCloud
        )
    ))
}

@Test func systemNoticesDropPrivateSymbolsAndNameTheirTrophy() {
    let screenshot = CloudSystemNotice(kind: .screenshotSaved)
    #expect(screenshot.headline == "Screenshot saved")
    #expect(screenshot.shownFor == .seconds(4))
    let trophy = CloudSystemNotice(
        kind: .trophyEarned(.gold), title: "\u{E04A} Where's Mr. Dinosaur?", detail: "Trophy earned!"
    )
    #expect(trophy.headline == "Where's Mr. Dinosaur?")
    #expect(trophy.lines == ["Gold trophy earned"])
    #expect(trophy.announcement == "Where's Mr. Dinosaur?\nGold trophy earned")
    #expect(trophy.shownFor == .seconds(6))
    let unnamed = CloudSystemNotice(kind: .trophyEarned(.platinum))
    #expect(unnamed.headline == "Platinum trophy earned")
    #expect(unnamed.lines.isEmpty)
}

@Test func aTrialRunningOutShowsTheServiceWordingForLonger() {
    let trial = CloudSystemNotice(
        kind: .trialTimeLeft, title: "You have 5 minutes remaining on your game trial."
    )
    #expect(trial.headline == "You have 5 minutes remaining on your game trial.")
    #expect(trial.lines.isEmpty)
    #expect(trial.announcement == "You have 5 minutes remaining on your game trial.")
    #expect(trial.shownFor == .seconds(8))
    let unworded = CloudSystemNotice(kind: .trialTimeLeft)
    #expect(unworded.headline == "Your game trial is running out")
    #expect(unworded.lines.isEmpty)
}

@MainActor @Test func toastsShowOneAtATimeInTheOrderTheyArrived() async {
    let clock = TestClock()
    let store = TestStore(initialState: CloudToastsReducer.State()) {
        CloudToastsReducer()
    } withDependencies: {
        $0.continuousClock = clock
    }
    let screenshot = CloudSystemNotice(kind: .screenshotSaved)
    let trophy = CloudSystemNotice(kind: .trophyEarned(.silver), title: "Hello")
    await store.send(.received(screenshot)) {
        $0.phase = .showing(.init(id: 0, notice: screenshot))
        $0.nextID = 1
    }
    await store.send(.received(trophy)) {
        $0.queued = [.init(id: 1, notice: trophy)]
        $0.nextID = 2
    }
    await store.send(.expired(1))
    await clock.advance(by: screenshot.shownFor)
    await store.receive(.expired(0)) {
        $0.phase = .showing(.init(id: 1, notice: trophy))
        $0.queued = []
    }
    await clock.advance(by: trophy.shownFor)
    await store.receive(.expired(1)) {
        $0.phase = .idle
    }
}

@MainActor @Test func theQueueKeepsTheNewestToasts() async {
    let store = TestStore(initialState: CloudToastsReducer.State()) {
        CloudToastsReducer()
    } withDependencies: {
        $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off
    for _ in 0..<(CloudToastsReducer.queueLimit + 3) {
        await store.send(.received(CloudSystemNotice(kind: .screenshotSaved)))
    }
    #expect(store.state.shown?.id == 0)
    #expect(store.state.queued.map(\.id) == [3, 4, 5, 6])
    await store.send(.clear)
}

@MainActor @Test func noticesReachTheToastsOnlyWhilePlayingAndLeaveWithTheSession() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    let notice = CloudSystemNotice(kind: .recordingSaved)
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .cloudNotice(notice)))
    #expect(store.state.toasts.shown == nil)
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(StreamSessionID(uuid: UUID(99)), .cloudNotice(notice)))
    #expect(store.state.toasts.shown == nil)
    await store.send(.event(firstSession, .cloudNotice(notice)))
    await store.receive(.toasts(.received(notice)))
    #expect(store.state.toasts.shown?.notice == notice)
    await store.send(.event(firstSession, .recording(CloudRecordingBanner(elapsed: "00:10"))))
    await store.receive(.toasts(.recording(CloudRecordingBanner(elapsed: "00:10"))))
    #expect(store.state.toasts.recording?.elapsed == "00:10")
    await store.send(.failed(firstSession, .renderer))
    await store.receive(.toasts(.clear))
    #expect(store.state.toasts.isEmpty)
}

@MainActor @Test func aCaptureThumbnailFromTheSessionJoinsItsToast() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    let picture = CloudCaptureThumbnail(id: "local1", video: false, jpeg: Data([0xFF, 0xD8]))
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(firstSession, .cloudNotice(CloudSystemNotice(kind: .screenshotSaved))))
    await store.send(.event(firstSession, .captureThumbnail(picture)))
    await store.receive(.toasts(.thumbnail(picture)))
    #expect(store.state.toasts.shown?.thumbnail == picture.jpeg)
    await store.send(.stop)
    await store.skipReceivedActions()
}

@MainActor @Test func thumbnailsJoinTheirSavedToastWhicheverArrivesFirst() async {
    let store = TestStore(initialState: CloudToastsReducer.State()) {
        CloudToastsReducer()
    } withDependencies: {
        $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off
    let picture = CloudCaptureThumbnail(id: "local1", video: false, jpeg: Data([0xFF, 0xD8]))
    let clip = CloudCaptureThumbnail(id: "local2", video: true, jpeg: Data([0xFF, 0xD9]))
    await store.send(.received(CloudSystemNotice(kind: .screenshotSaved)))
    await store.send(.thumbnail(picture))
    #expect(store.state.shown?.thumbnail == picture.jpeg)
    await store.send(.thumbnail(clip))
    await store.send(.received(CloudSystemNotice(kind: .screenshotRefused)))
    await store.send(.received(CloudSystemNotice(kind: .recordingSaved)))
    #expect(store.state.queued.map(\.thumbnail) == [nil, clip.jpeg])
    await store.send(.clear)
}

@Test func savedCapturesAreNamedAfterTheGameAndTime() {
    let created = Date(timeIntervalSince1970: 1_792_319_468)
    let name = CloudCaptureFileName(
        title: "My Friend: Peppa/Pig", created: created, fileExtension: ".JPG", video: false
    ).value
    #expect(name.hasPrefix("My Friend  Peppa Pig 2026-10-1"))
    #expect(name.hasSuffix(".jpg"))
    let clip = CloudCaptureFileName(title: "", created: created, fileExtension: "", video: true).value
    #expect(clip.hasPrefix("Video clip "))
    #expect(clip.hasSuffix(".mp4"))
    #expect(CloudCaptureFileName(title: "", created: created, fileExtension: "", video: false).value
        .hasPrefix("Screenshot "))
}

@Test func captureSavingDefaultsToPlayStationAndKeepsAnEarlierChoice() throws {
    let decoder = JSONDecoder()
    #expect(CloudPictureSettings().captureSaving == .followPlayStation)
    #expect(try decoder.decode(CloudPictureSettings.self, from: Data("{}".utf8))
        .captureSaving == .followPlayStation)
    #expect(try decoder.decode(CloudPictureSettings.self, from: Data(#"{"savesCaptures":false}"#.utf8))
        .captureSaving == .never)
    #expect(try decoder.decode(CloudPictureSettings.self, from: Data(#"{"captureSaving":"always"}"#.utf8))
        .captureSaving == .always)
    let saved = try JSONEncoder().encode(CloudPictureSettings())
    #expect(try decoder.decode(CloudPictureSettings.self, from: saved).captureSaving == .followPlayStation)
}

@MainActor @Test func anEndedTrialOffersNoRetry() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    store.exhaustivity = .off
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.failed(firstSession, .stream(.consoleQuit(.trialEnded), overInternet: true)))
    #expect(!store.state.offersRetry)
    #expect(store.state.failureMessage?.hasPrefix("Your game trial has ended.") == true)
    await store.send(.retry)
    #expect(store.state.offersRetry == false)
    await store.send(.stop)
    await store.skipReceivedActions()
}

@MainActor @Test func aDroppedCloudStreamStillOffersARetry() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    store.exhaustivity = .off
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.failed(firstSession, .stream(.consoleQuit(.consoleDisconnected), overInternet: true)))
    #expect(store.state.offersRetry)
    await store.send(.stop)
    await store.skipReceivedActions()
}
