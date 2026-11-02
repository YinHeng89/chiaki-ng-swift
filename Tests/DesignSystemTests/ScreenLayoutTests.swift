import SwiftUI
import Testing
@testable import DesignSystem

@Test func screenRoomFollowsBothAxes() {
    #expect(ScreenLayout.room(for: CGSize(width: 390, height: 844)) == .compact)
    #expect(ScreenLayout.room(for: CGSize(width: 932, height: 430)) == .compact)
    #expect(ScreenLayout.room(for: CGSize(width: 507, height: 1024)) == .compact)
    #expect(ScreenLayout.room(for: CGSize(width: 900, height: 560)) == .regular)
    #expect(ScreenLayout.room(for: CGSize(width: 1180, height: 820)) == .regular)
    #expect(ScreenLayout.room(for: CGSize(width: 1400, height: 800)) == .wide)
    #expect(ScreenLayout.room(for: CGSize(width: 1920, height: 1080)) == .wide)
}

@Test func measuredLayoutKeepsTheLargerSideInset() {
    let layout = ScreenLayout.measured(
        size: CGSize(width: 932, height: 430),
        safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)
    )
    #expect(layout.room == .compact)
    #expect(layout.sideInset == 59)
    #expect(layout.bottomInset == 21)
    #expect(layout.bottomChromeInset == 33)
    #expect(ScreenLayout(room: .regular, bottomInset: 21).bottomChromeInset == 45)
    #expect(ScreenLayout(room: .regular).bottomChromeInset == 24)
    #expect(layout.touch == ScreenLayout.touchPlatform)
}

@Test func topChromeInsetShrinksOnlyWithoutATitleBar() {
    let compact = ScreenLayout(room: .compact)
    let regular = ScreenLayout(room: .regular)
    #expect(regular.topChromeInset == ScreenLayout.regularTopChrome)
    if ScreenLayout.titleBarChrome {
        #expect(compact.topChromeInset == ScreenLayout.regularTopChrome)
    } else {
        #expect(compact.topChromeInset == ScreenLayout.compactTopChrome)
    }
}

@Test func compactScreenEnvironmentWritesThroughToTheLayout() {
    var values = EnvironmentValues()
    #expect(!values.compactScreen)
    values.compactScreen = true
    #expect(values.screenLayout.room == .compact)
    values.screenSideInset = 44
    #expect(values.screenLayout.sideInset == 44)
    values.compactScreen = false
    #expect(values.screenLayout.room == .regular)
    #expect(values.screenLayout.sideInset == 44)
}

@Test func statureFollowsHeightAlone() {
    #expect(ScreenLayout.stature(for: CGSize(width: 852, height: 393)) == .short)
    #expect(ScreenLayout.stature(for: CGSize(width: 678, height: 820)) == .tall)
    #expect(ScreenLayout.stature(for: CGSize(width: 1920, height: 479)) == .short)
    #expect(ScreenLayout.stature(for: CGSize(width: 320, height: 480)) == .tall)
    let phone = ScreenLayout.measured(size: CGSize(width: 852, height: 393), safeArea: EdgeInsets())
    #expect(phone.isShort)
    #expect(phone.isCompact)
}

@Test func touchDecidesControlSizeAndHoverAffordances() {
    let touch = ScreenLayout(room: .regular, touch: true)
    let pointer = ScreenLayout(room: .regular, touch: false)
    #expect(touch.controlSize == ScreenLayout.touchTarget)
    #expect(pointer.controlSize == 0)
    #expect(touch.controlSpacing > pointer.controlSpacing)
    #expect(!touch.hoverAffordances)
    #expect(pointer.hoverAffordances)
    #expect(ScreenLayout(room: .compact).sheetsFillWidth)
    #expect(!ScreenLayout(room: .wide).sheetsFillWidth)
    #expect(ScreenLayout(room: .compact).sheetMargin < ScreenLayout(room: .regular).sheetMargin)
}
