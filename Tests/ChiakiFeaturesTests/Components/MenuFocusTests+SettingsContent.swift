import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Synchronization
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    private func expectTextSizeSegmentsChooseWithConfirm(
        _ harness: MenuFocusHarness,
        store: StoreOf<SettingsFeature>
    ) async {
        await harness.send(.confirm)
        let chosen = store.playStationAccessibility.draft.textSizeOverride ?? 99
        #expect(PlayStationAccessibilitySettings.textSizeRange.contains(chosen))
        await harness.send([.right, .confirm])
        #expect(store.playStationAccessibility.draft.textSizeOverride == min(chosen + 1, 2))
    }

    private func expectBackRestoresTheKeptSpeed(
        _ harness: MenuFocusHarness,
        store: StoreOf<SettingsFeature>,
        speed: NSView?
    ) async {
        await harness.send(.back)
        #expect(harness.focusedView === speed && store.playStationAccessibility.draft.screenReaderSpeed == 3)
        await harness.send([.confirm, .right, .right, .confirm])
        #expect(store.playStationAccessibility.draft.screenReaderSpeed == 5)
        await harness.send([.confirm, .right])
        #expect(store.playStationAccessibility.draft.screenReaderSpeed == 6)
        await harness.send(.back)
        #expect(harness.focusedView === speed && store.playStationAccessibility.draft.screenReaderSpeed == 5)
    }

    @Test func accessibilityTabReachesChoicesAndReturnsFocusOnBack() async {
        let store = FeatureFocusStores.settingsStore(tab: .accessibility)
        let harness = MenuFocusHarness(width: 1000, height: 750) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        let tab = harness.focusedView
        await harness.send(.down)
        await harness.pause(120)
        let reader = harness.focusedView
        #expect(reader !== tab)
        let defaults = PlayStationAccessibilitySystemDefaults.current
        await harness.send(.confirm)
        #expect(store.playStationAccessibility.draft.screenReaderOverride == !defaults.screenReader)
        await harness.send(.down)
        #expect(harness.focusedView !== reader)
        let speed = harness.focusedView
        await harness.send([.confirm, .right])
        #expect(store.playStationAccessibility.draft.screenReaderSpeed == 4)
        #expect(harness.focusedView === speed)
        await expectBackRestoresTheKeptSpeed(harness, store: store, speed: speed)
        await harness.send(.down)
        let volume = harness.focusedView
        await harness.send([.confirm, .right])
        #expect(store.playStationAccessibility.draft.screenReaderVolume == 13)
        #expect(harness.focusedView === volume)
        await harness.send(.back)
        #expect(harness.focusedView === volume && store.playStationAccessibility.draft
            .screenReaderVolume == 12)
        await harness.send(.down)
        #expect(harness.focusedView != nil && harness.focusedView !== volume)
        await expectTextSizeSegmentsChooseWithConfirm(harness, store: store)
        await harness.send([.down, .confirm])
        #expect(store.playStationAccessibility.draft.boldTextOverride == !defaults.boldText)
        await harness.send([.down, .confirm])
        #expect(store.playStationAccessibility.draft.higherContrastOverride == !defaults.higherContrast)
        await harness.send([.down, .confirm])
        #expect(store.playStationAccessibility.draft == PlayStationAccessibilitySettings())
        await harness.send(.back)
        #expect(harness.focusedView === tab)
        await harness.send(.previous)
        #expect(store.route == .interface)
        await harness.send(.next)
        #expect(store.route == .accessibility)
    }

    @Test func settingsNetworkFieldIsReachedBeforeKeyboardOpens() async {
        let store = FeatureFocusStores.settingsStore(tab: .network)
        let harness = MenuFocusHarness(width: 1000, height: 750) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(150)
        let sweep = window.firstResponder
        let enabled = store.network.discovery.draft.unicastEnabled
        await harness.send(.confirm)
        #expect(store.network.discovery.draft.unicastEnabled != enabled)
        #expect(window.firstResponder === sweep)
        await harness.send(.down)
        #expect(window.firstResponder is NSTextView)
        #expect(window.attachedSheet == nil)
        let subnets = window.firstResponder
        await harness.send(.down)
        #expect(window.firstResponder !== subnets)
        await harness.send(.up)
        #expect(window.firstResponder === subnets)
        await harness.send(.up)
        #expect(window.firstResponder === sweep)
        await harness.send(.up)
        #expect(window.firstResponder !== sweep)
        harness.perform([.down], in: window)
        await harness.pause(150)
        #expect(window.firstResponder === sweep)
        await harness.send(.down)
        #expect(window.firstResponder === subnets)
        await harness.send(.left)
        #expect(window.firstResponder === subnets)
        await harness.send(.right)
        #expect(window.firstResponder === subnets)
        await harness.send(.confirm)
        #expect(window.attachedSheet != nil)
    }

    @Test func rejectedSubnetsKeepTheirTextAndHoldFocusUntilFixed() async {
        var invalid = DiscoverySettings()
        invalid.subnets = ["192.168.1.0/16"]
        var network = NetworkSettingsFeature.State()
        network.subnets = "192.168.1.0/16"
        network.discovery.setting = .saveFailed(saved: DiscoverySettings(), draft: invalid, failure: .invalid)
        network.discovery.draft = invalid
        let accepted = SettingsClient.inMemory()
        let coreChecked = SettingsClient(read: accepted.read) { value throws(PersistedSettingFailure) in
            if let discovery = value as? DiscoverySettings, discovery.subnets.contains("192.168.1.0/16") {
                throw .invalid
            }
            try await accepted.write(value)
        }
        let store = FeatureFocusStores.settingsStore(tab: .network, network: network, settings: coreChecked)
        let harness = MenuFocusHarness(width: 1000, height: 750) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(150)
        await harness.send(.down)
        #expect(window.firstResponder is NSTextView)
        let subnets = window.firstResponder
        await harness.send(.down)
        #expect(window.firstResponder === subnets)
        await harness.send(.up)
        #expect(window.firstResponder === subnets)
        #expect(store.network.subnets == "192.168.1.0/16")
        #expect(store.network.subnetsRejected)
    }

    @Test func pictureServiceSegmentsMoveIndividuallyAndKeepFocusAtEdges() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 800) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        await harness.send([.right, .confirm])
        await harness.pause(100)
        await harness.send([.down, .left])
        let psCloud = harness.focusedFrame.integral
        await harness.send(.left)
        #expect(harness.focusedFrame.integral == psCloud)
        await harness.send([.right, .confirm])
        let psNow = harness.focusedFrame.integral
        #expect(psNow.midX > psCloud.midX)
        #expect(abs(psNow.midY - psCloud.midY) <= 2)
        await harness.send(.right)
        #expect(harness.focusedFrame.integral == psNow)
        #expect(store.cloudPicture.picture.draft.psNowAutomaticBitrate)
        await harness.send([.down, .down, .confirm])
        #expect(!store.cloudPicture.picture.draft.psNowAutomaticBitrate)
    }

    @Test func pictureSettingsKeepsFocusAcrossStreamAndServiceChoices() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 800) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        await harness.send([.right, .confirm])
        await harness.pause(100)
        await harness.send(.down)
        let serviceFrame = harness.focusedFrame.integral
        #expect(serviceFrame.midY > 550)
        #expect(serviceFrame.midY < 630)
        await harness.send(.left)
        #expect(harness.focusedFrame.integral.midX < serviceFrame.midX)
        await harness.send([.right, .confirm, .down, .down])
        #expect(store.cloudPicture.picture.draft.psNowAutomaticBitrate)
        await harness.send(.confirm)
        #expect(!store.cloudPicture.picture.draft.psNowAutomaticBitrate)
        await harness.pause(400)
        let bitrate = store.cloudPicture.picture.draft.psNowBitrateMbps
        await harness.send([.confirm, .right])
        #expect(store.cloudPicture.picture.draft.psNowBitrateMbps == bitrate + 1)
        await harness.send(.left)
        #expect(store.cloudPicture.picture.draft.psNowBitrateMbps == bitrate)
    }

    @Test func cloudPictureHDRToggleIsReachableBelowAutomaticBitrate() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 800) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        await harness.send([.right, .confirm])
        await harness.pause(100)
        await harness.send([.down, .down, .down])
        #expect(store.cloudPicture.picture.draft.psCloudAutomaticBitrate)
        let automatic = harness.focusedFrame.integral
        await harness.send(.down)
        #expect(harness.focusedFrame.integral.midY < automatic.midY)
        #expect(store.cloudPicture.picture.draft.hdr)
        await harness.send(.confirm)
        #expect(!store.cloudPicture.picture.draft.hdr)
        await harness.send(.up)
        #expect(harness.focusedFrame.integral.midY == automatic.midY)
    }

    @Test func cloudQualityPickerIsReachedBelowHDRAndLeadsBack() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 800) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        await harness.send([.right, .confirm])
        await harness.pause(100)
        await harness.send([.down, .down, .down, .down])
        let hdr = harness.focusedFrame.integral
        await harness.send(.down)
        let quality = harness.focusedFrame.integral
        #expect(quality.midY < hdr.midY)
        #expect(store.cloudPicture.picture.draft.psCloudQuality == .high)
        await harness.send(.up)
        #expect(harness.focusedFrame.integral.midY == hdr.midY)
    }

    @Test func captureSavingFollowsPlayStationBelowQualityWithItsFolderButtons() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 800) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        await harness.send([.right, .confirm])
        await harness.pause(100)
        await harness.send([.down, .down, .down, .down, .down])
        let quality = harness.focusedFrame.integral
        await harness.send(.down)
        let saving = harness.focusedFrame.integral
        #expect(saving.midY < quality.midY)
        #expect(store.cloudPicture.picture.draft.captureSaving == .followPlayStation)
        await harness.send(.down)
        let folder = harness.focusedFrame.integral
        #expect(folder.midY < saving.midY)
        await harness.send(.up)
        let back = harness.focusedFrame.integral
        #expect(back.midY > folder.midY)
        await harness.send(.up)
        #expect(harness.focusedFrame.integral.midY > back.midY)
    }

    @Test func controlsSettingsDirectionalTraversalReachesContent() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = MenuFocusHarness(width: 1300, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 1180, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        var frames = [CGRect]()
        for _ in 0..<50 {
            if harness.focusedView != nil {
                let frame = harness.focusedFrame.integral
                if frames.last != frame {
                    frames.append(frame)
                }
                if abs(frame.height - ControlsBoardPlacement.chipHeight) < 2 {
                    break
                }
            }
            await harness.send(.down)
        }
        #expect(frames.count >= 5)
        #expect(frames.contains { $0.midX < 300 && $0.midY > 600 })
        #expect(frames.contains { $0.midX < 300 && $0.midY < 600 && $0.midY > 450 })
        let chip = harness.focusedView
        let chipFrame = harness.focusedFrame
        #expect(abs(chipFrame.height - ControlsBoardPlacement.chipHeight) < 2)
        await harness.send(.left)
        let across = harness.focusedFrame
        #expect(across.maxX < chipFrame.minX)
        #expect(abs(across.height - ControlsBoardPlacement.chipHeight) < 2)
        await harness.send(.right)
        #expect(harness.window.firstResponder === chip)
        await harness.send(.confirm)
        #expect(store.controls.capture != nil)
    }

    @Test func returningFocusRestoresOrAdvancesFromTheOriginControl() async {
        _ = NSApplication.shared
        let probe = GridFocusProbe()
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: ColumnsFixture(probe: probe))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        try? await Task.sleep(for: .milliseconds(300))
        let origin = window.firstResponder as? NSView
        let originFrame = origin?.convert(origin?.bounds ?? .zero, to: nil) ?? .zero
        #expect(probe.focus == "right1")

        window.makeFirstResponder(nil)
        await settle(host)
        if let origin {
            await testNavigator.returnFocus(to: origin, in: window, advance: false)
        }
        await settle(host)
        #expect(probe.focus == "right1")

        window.makeFirstResponder(nil)
        await settle(host)
        if let origin {
            await testNavigator.returnFocus(to: origin, in: window, advance: true)
        }
        try? await Task.sleep(for: .milliseconds(200))
        await settle(host)
        let advanced = window.firstResponder as? NSView
        let advancedFrame = advanced?.convert(advanced?.bounds ?? .zero, to: nil) ?? .zero
        #expect(advanced != nil)
        #expect(abs(advancedFrame.midX - originFrame.midX) > 2 || abs(advancedFrame.midY - originFrame.midY) >
            2)
    }

    @Test func textFieldsAreNavigableUntilReturnEntersEditing() async {
        _ = NSApplication.shared
        let host = MenuFocusHostingView(rootView: TextNavigationFixture())
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 300),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(window.firstResponder is NSTextView)

        func key(_ code: UInt16, _ characters: String) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            )!
        }

        #expect(testNavigator.handleTextFieldKey(key(125, "\u{F701}"), in: window))
        await settle(host)
        #expect(!(window.firstResponder is NSTextView))

        testNavigator.move(backward: true, in: window)
        await settle(host)
        #expect(window.firstResponder is NSTextView)
        #expect(!testNavigator.isEditingText(in: window))

        #expect(testNavigator.handleTextFieldKey(key(36, "\r"), in: window))
        #expect(testNavigator.isEditingText(in: window))
        #expect(!testNavigator.handleTextFieldKey(key(123, "\u{F702}"), in: window))
        #expect(window.firstResponder is NSTextView)

        #expect(testNavigator.handleTextFieldKey(key(53, "\u{1b}"), in: window))
        #expect(!testNavigator.isEditingText(in: window))
        #expect(window.firstResponder is NSTextView)

        #expect(testNavigator.handleTextFieldKey(key(124, "\u{F703}"), in: window))
        await settle(host)
        #expect(!(window.firstResponder is NSTextView))
    }

    @Test func interfaceMenuPositionSegmentsMoveOneStepAndSelect() async {
        let store = FeatureFocusStores.settingsStore(tab: .interface)
        let harness = MenuFocusHarness(width: 1000, height: 800) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(200)
        let edges = LibraryRailEdge.allCases
        await harness.send(.confirm)
        await harness.pause(200)
        guard let entered = edges.firstIndex(of: store.interface.draft.railEdge), entered > 0 else {
            Issue.record("Focus did not enter the menu position segments past the first option")
            return
        }
        await harness.send([.left, .confirm])
        await harness.pause(200)
        #expect(store.interface.draft.railEdge == edges[entered - 1])
        await harness.send([.right, .confirm])
        await harness.pause(200)
        #expect(store.interface.draft.railEdge == edges[entered])
    }

    @Test func consoleHDRCheckboxSitsBelowTheCodecAndToggles() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 1100) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(200)
        #expect(store.picture.isEditable)
        #expect(store.picture.draft.localPS5HDR)
        await harness.send([.down, .down, .down, .down, .down])
        let codec = window.firstResponder
        let codecFrame = harness.focusedFrame.integral
        await harness.send(.down)
        let checkbox = window.firstResponder
        #expect(checkbox !== codec)
        #expect(harness.focusedFrame.integral.midY < codecFrame.midY)
        #expect(harness.focusedFrame.integral.width < 30)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(!store.picture.draft.localPS5HDR)
        await harness.send(.up)
        #expect(window.firstResponder === codec)
        await harness.send(.down)
        #expect(window.firstResponder === checkbox)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.picture.draft.localPS5HDR)
        await harness.send(.down)
        #expect(window.firstResponder !== checkbox)
        await harness.send(.up)
        #expect(window.firstResponder === checkbox)
    }

    @Test func pictureFullScreenToggleSitsAboveTheColourGroupAndToggles() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 1100) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(200)
        #expect(store.picture.isEditable)
        #expect(!store.picture.draft.fullScreenStreams)
        var previous = window.firstResponder
        for _ in 0..<20 {
            await harness.send(.down)
            if window.firstResponder === previous {
                break
            }
            previous = window.firstResponder
        }
        await harness.send([.up, .up, .up, .up, .up, .up])
        let toggle = window.firstResponder
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.picture.draft.fullScreenStreams)
        #expect(store.picture.draft.adjustments.isNeutral)
        await harness.send(.up)
        #expect(window.firstResponder !== toggle)
        await harness.send(.down)
        #expect(window.firstResponder === toggle)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(!store.picture.draft.fullScreenStreams)
    }
}
