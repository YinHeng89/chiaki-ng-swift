import ChiakiClients
import ChiakiDiagnostics
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct SettingsFeatureTests {
    @Test func closingAndSwitchingTabsKeepEveryPanesEdits() async {
        var white = ControlsConfiguration()
        white.lightbar = .fixed(rgb: 0xffffff)
        var initial = SettingsFeature.State()
        initial.controls = .loaded()
        initial.controls.draft = white
        let store = TestStore(initialState: initial) {
            SettingsFeature()
        }
        await store.send(.select(.controls)) {
            $0.route = .controls
        }
        await store.send(.select(.picture)) {
            $0.route = .picture
        }
        await store.send(.closed)
        #expect(store.state.controls.draft == white)
    }

    @Test func theRoutesNameTheirTabsInOrder() {
        #expect(SettingsRoute.allCases.map { String(localized: $0.title) } == [
            "Picture", "Sound", "Controls", "Interface", "Accessibility", "Network", "Remote players",
            "Developer",
            "Entitlements",
            "Caches", "Requests", "Tokens", "About"
        ])
        #expect(SettingsRoute.pageWidth == 1180)
        #expect(SettingsRoute.controls.drawsOwnTitle)
        #expect(!SettingsRoute.tokens.drawsOwnTitle)
    }

    @Test func launchingLoadsLoggingInterfaceAndControls() async {
        var logging = LogSettings.defaults
        logging.showLiveLogButton = true
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.settings = .inMemory([logging, InterfaceSettings(railEdge: .top)])
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.launched)
        await store.skipReceivedActions()
        #expect(store.state.logSettings == logging)
        #expect(store.state.interface.saved == InterfaceSettings(railEdge: .top))
        #expect(store.state.controls.isEditable)
    }

    @Test func savedPlayStationAccessibilityReachesThePlayingStreamOnceItSettles() async {
        let updates = LockIsolated<[PlayStationAccessibilitySettings]>([])
        let clock = TestClock()
        var settings = PlayStationAccessibilitySettings()
        settings.screenReaderSpeed = 5
        var settled = settings
        settled.screenReaderSpeed = 6
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.streamSession.updateAccessibility = { value in
                updates.withValue {
                    $0.append(value)
                }
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.playStationAccessibility(.delegate(.committed(settings))))
        await clock.advance(by: .milliseconds(300))
        await store.send(.playStationAccessibility(.delegate(.committed(settled))))
        await clock.advance(by: SettingsFeature.accessibilitySettle)
        await store.finish()
        #expect(updates.value == [settled])
    }

    @Test func aBuiltErrorReportIsPresentedAndDismissedWithDone() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.logSettings.exportReport = {
                "report"
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.developer(.exportReport))
        await store.receive(\.developer.delegate.reportReady) {
            $0.destination = .errorReport(ErrorReportFeature.State(text: "report"))
        }
        await store.send(.destination(.presented(.errorReport(.done))))
        await store.receive(\.destination.dismiss) {
            $0.destination = nil
        }
    }

    @Test func aCacheIsClearedOnlyAfterTheConfirmation() async {
        let cleared = LockIsolated<[CacheClearing]>([])
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.catalog.clearCache = { clearing in
                cleared.withValue {
                    $0.append(clearing)
                }
            }
            $0.catalog.clearDecoded = {}
            $0.catalog.cacheSummaries = {
                []
            }
            $0.catalog.cacheAccountNames = {
                [:]
            }
            $0.catalog.decodedCount = {
                0
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.caches(.askClear(.all)))
        await store.receive(\.caches.delegate.confirmClear) {
            $0.destination = .clearCache(ClearCacheConfirmation.State(.all))
        }
        #expect(cleared.value.isEmpty)
        await store.send(.destination(.presented(.clearCache(.cancel))))
        await store.receive(\.destination.dismiss) {
            $0.destination = nil
        }
        #expect(cleared.value.isEmpty)
        await store.send(.caches(.askClear(.all)))
        await store.receive(\.caches.delegate.confirmClear)
        await store.send(.destination(.presented(.clearCache(.confirm)))) {
            $0.destination = nil
        }
        await store.receive(\.caches.clear)
        await store.skipReceivedActions()
        #expect(cleared.value == [.all])
    }

    @Test func closingThePanelDropsWhatItPresented() async {
        var initial = SettingsFeature.State()
        initial.destination = .errorReport(ErrorReportFeature.State(text: "report"))
        let store = TestStore(initialState: initial) {
            SettingsFeature()
        }
        await store.send(.closed) {
            $0.destination = nil
        }
    }
}
