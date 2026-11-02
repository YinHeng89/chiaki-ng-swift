import ChiakiModels
import ChiakiDiagnostics
import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

extension StreamMenuOverlay {
    /// The panel control that holds focus, or `nil` when focus is on a tab, the top controls or nothing.
    var focusedControl: StreamMenuControl? {
        guard case let .control(control) = focusTarget else {
            return nil
        }
        return control
    }

    /// The foreground colour of a panel tab, primary for the selected panel and secondary otherwise.
    func tone(_ item: StreamMenuPanel) -> Color {
        if panel == item {
            return .primary
        }
        return .secondary
    }

    /// The background of a panel tab, a faint accent tint for the selected panel and clear otherwise.
    func selectionBackground(_ item: StreamMenuPanel) -> Color {
        if panel == item {
            return Palette.accent.opacity(0.1)
        }
        return .clear
    }

    /// The accessibility traits of a panel tab, marking the selected panel as selected.
    func selectionTraits(_ item: StreamMenuPanel) -> AccessibilityTraits {
        if panel == item {
            return .isSelected
        }
        return []
    }

    /// The controls a panel offers controller focus, in navigation order, given the loaded draft and the
    /// available features. Only the retry control is offered when loading failed.
    /// - Parameter targetPanel: The panel whose controls are listed.
    func controls(in targetPanel: StreamMenuPanel) -> [StreamMenuControl] {
        guard store.loaded else {
            return store.phase == .failed
                ? [.retryLoad]
                : []
        }
        switch targetPanel {
        case .picture:
            return pictureControls
        case .stream:
            return StreamMenuLaunchControls.controls(for: store.draft)
        case .colour:
            return StreamMenuColourControls.controls
        case .sound:
            return soundControls
        case .statistics:
            return statisticsRows.flatMap { $0 }
        case .players:
            guard let couch else {
                return []
            }
            return StreamPlayersPanel.controls(for: couch.state, kakusan: kakusan?.state)
        case .invitations:
            guard let invitations else {
                return []
            }
            return StreamMenuInvitationsControls.controls(for: invitations.state)
        case .trophies:
            guard let trophies else {
                return []
            }
            return StreamMenuTrophiesControls.controls(for: trophies.state)
        case .session:
            return sessionControls
        }
    }

    private var soundControls: [StreamMenuControl] {
        var controls: [StreamMenuControl] = [.soundVolume]
        if store.draft.chatVolume != nil {
            controls.append(.soundChatVolume)
        }
        if store.audio3DDisabledReason == nil {
            controls.append(.soundAudio3D)
        }
        controls.append(.soundSpatial)
        if microphone?.available == true {
            controls.append(.soundMicrophone)
        }
        return controls
    }

    private var pictureControls: [StreamMenuControl] {
        var controls = [StreamMenuControl]()
        if frameGenerationEligible {
            controls.append(.pictureGenerated)
        }
        controls.append(.pictureOutput)
        if store.draft.upscaledOutput != .disabled {
            controls.append(.pictureUpscaler)
        }
        return controls + StreamMenuDisplayControls.controls(for: store.draft.videoFit)
    }

    /// The panels shown in the tab rail. Players needs couch co-op and Colour is hidden for guests.
    var panels: [StreamMenuPanel] {
        StreamMenuPanel.allCases.filter { item in
            switch item {
            case .players:
                couch != nil
            case .colour, .stream:
                store.context != .guest
            case .invitations:
                invitations != nil
            case .trophies:
                trophies != nil
            case .picture, .sound, .statistics, .session:
                true
            }
        }
    }

    /// The dock items after the divider, in order: Settings, the developer log while it is turned on, then
    /// the close button.
    var dockItems: [StreamMenuFocusTarget] {
        [.settings] + (liveLogButtonShown
            ? [.log]
            : []) + [.exit]
    }

    /// Moves focus along the tab rail, moving past the last tab to the first dock item after the divider.
    /// - Parameters:
    ///   - offset: The number of tabs to move, negative to go left.
    ///   - selecting: Whether the newly focused tab's panel is also selected.
    func moveTabFocus(by offset: Int, selecting: Bool = false) {
        let current: StreamMenuPanel
        if case .tab(let item) = focusTarget {
            current = item
        } else {
            current = panel
        }
        guard let index = panels.firstIndex(of: current) else {
            return
        }
        let nextIndex = index + offset
        guard panels.indices.contains(nextIndex) else {
            if offset > 0 {
                focusTarget = dockItems.first
            }
            return
        }
        let nextPanel = panels[nextIndex]
        if selecting {
            store.send(.selectPanel(nextPanel))
        }
        focusTarget = .tab(nextPanel)
    }

    /// Focuses the last control of the current panel, nearest the dock, landing on the selected fit option for
    /// the fit row; the Trophies panel, whose list can be long, is entered at its first trophy instead, or at
    /// Refresh until the trophies arrive.
    func focusLastControl() {
        let shown = controls(in: panel)
        if panel == .trophies, let first = shown.first {
            let trophy = shown.first { control in
                if case .trophy = control {
                    return true
                }
                return false
            }
            trophiesEntryWaits = trophy == nil
            trophiesAnchor = trophy ?? first
            focusTarget = .control(trophy ?? first)
            return
        }
        if panel == .statistics, store.loaded {
            focusTarget = .control(.troubleshootTopic(store.troubleshootTopic.rawValue))
            return
        }
        guard let last = controls(in: panel).last else {
            return
        }
        focusTarget = .control(StreamMenuDisplayControls.entry(last, videoFit: store.draft.videoFit))
    }

    /// Moves focus up or down the current panel's controls, skipping options that share a row, and moves
    /// below the last control to the panel's tab.
    func moveControlFocus(_ control: StreamMenuControl, by offset: Int) {
        let controls = controls(in: panel)
        guard var nextIndex = controls.firstIndex(of: control) else {
            return
        }
        repeat {
            nextIndex += offset
        } while controls.indices.contains(nextIndex)
            && StreamMenuDisplayControls.sharesRow(controls[nextIndex], control)
        guard controls.indices.contains(nextIndex) else {
            if offset > 0 {
                focusTarget = .tab(panel)
            }
            return
        }
        let next = StreamMenuDisplayControls.entry(controls[nextIndex], videoFit: store.draft.videoFit)
        guard panel == .trophies else {
            focusTarget = .control(next)
            return
        }
        trophiesAnchor = next
        Task { @MainActor in
            await Task.yield()
            focusTarget = .control(next)
        }
    }

    /// The Statistics panel's rows, from top to bottom: overlay level, glass, layout, video analysis, Measure
    /// brightness while the HDR heatmap shows, and the connection tips topics.
    var statisticsRows: [[StreamMenuControl]] {
        [
            StreamDiagnosticsAppearance.Level.allCases.map {
                .statisticsOverlay($0.rawValue)
            },
            StreamDiagnosticsAppearance.Glass.allCases.map {
                .diagnosticsGlass($0.rawValue)
            },
            StreamDiagnosticsAppearance.Layout.allCases.map {
                .diagnosticsLayout($0.rawValue)
            },
            StreamVideoAnalysisMode.allCases.map {
                .videoAnalysis($0.rawValue)
            }
        ] + (measuresBrightness
            ? [[.measureBrightness]]
            : []) + [StreamMenuTroubleshootControls.controls]
    }

    /// Whether the HDR heatmap shows, so the brightness marker can be measured.
    var measuresBrightness: Bool {
        store.diagnostics.analysis == .hdrHeatmap
    }

    /// Moves focus to the row above or below in the Statistics panel, keeping the column where it can, and
    /// moves below the last row to the Statistics tab.
    func moveStatisticsRow(_ control: StreamMenuControl, upward: Bool) {
        if control == .measureBrightness, upward {
            focusTarget = .control(.videoAnalysis(store.diagnostics.analysis.rawValue))
            return
        }
        let rows = statisticsRows
        guard let row = rows.firstIndex(where: { $0.contains(control) }),
              let column = rows[row].firstIndex(of: control) else {
            return
        }
        let target = row + (
            upward
                ? -1
                : 1
        )
        guard rows.indices.contains(target) else {
            if !upward {
                focusTarget = .tab(.statistics)
            }
            return
        }
        focusTarget = .control(rows[target][min(column, rows[target].count - 1)])
    }

    /// Moves focus left or right among the options of a choice row, stopping at either end.
    /// - Returns: `true` when the control belongs to a choice row, whether or not focus moved.
    func moveChoiceFocus(_ control: StreamMenuControl, by offset: Int) -> Bool {
        let choices: [StreamMenuControl]
        switch control {
        case .statisticsOverlay, .diagnosticsGlass, .diagnosticsLayout, .videoAnalysis:
            choices = statisticsRows.first { $0.contains(control) } ?? []
        case .troubleshootTopic:
            choices = StreamMenuTroubleshootControls.controls
        case .pictureFit:
            choices = StreamMenuDisplayControls.controls(for: VideoFit()).filter {
                $0 != .pictureZoom
            }
        default:
            return false
        }
        guard let index = choices.firstIndex(of: control) else {
            return false
        }
        let nextIndex = index + offset
        guard choices.indices.contains(nextIndex) else {
            return true
        }
        focusTarget = .control(choices[nextIndex])
        return true
    }

    /// Handles Left or Right on a panel control by moving along a choice row or cycling a choice, or by
    /// adjusting a slider while Confirm has started adjusting it.
    func moveControlValue(_ control: StreamMenuControl, by offset: Int) {
        if control.isSlider {
            if sliderNavigation.isAdjusting(control) {
                _ = adjustSlider(control, by: offset)
            }
            return
        }
        if moveChoiceFocus(control, by: offset) || cycleChoice(control, by: offset) {
            return
        }
    }

    /// Registers the navigator's Back, activation and focus move handlers for this overlay if none are
    /// registered yet.
    func registerFocusMoveHandler() {
        guard focusMoveHandlerID == nil, activationHandlerID == nil, backHandlerID == nil else {
            return
        }
        backHandlerID = navigator?.handlers.registerBack { window in
            guard !hasOtherPresentation, window === PlaybackWindowControl.keyWindow else {
                return false
            }
            if cancelSliderAdjustment() {
                return true
            }
            if navigationLevel == .measuring {
                finishMeasuring()
                return true
            }
            if closeInvitePickerIfNeeded() {
                return true
            }
            return cancelPlayerPickingIfNeeded()
        }
        activationHandlerID = navigator?.handlers.registerActivation { window in
            finishMeasuringOnConfirm(in: window)
        }
        focusMoveHandlerID = navigator?.handlers.registerFocusMove { window, direction in
            handleFocusMove(direction, in: window)
        }
    }

    private func finishMeasuringOnConfirm(in window: PlatformWindow) -> Bool {
        guard navigationLevel == .measuring, !hasOtherPresentation, window === PlaybackWindowControl.keyWindow
        else {
            return false
        }
        finishMeasuring()
        return true
    }

    private func handleFocusMove(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool {
        guard !hasOtherPresentation,
              window === PlaybackWindowControl.keyWindow,
              !(navigator?.isTrackingMenu ?? false) else {
            return false
        }
        guard navigationActive, LiveLogFocus.focus(in: window) == nil,
              !StreamHomeFocus.focused(in: window) else {
            return false
        }
        if navigationLevel == .measuring {
            store.send(.nudgeMarker(StreamBrightnessMeasureCard.nudge(for: direction)))
            return true
        }
        guard let focusTarget else {
            moveFromUntrackedFocus()
            return true
        }
        movePanelFocus(from: focusTarget, direction: direction, in: window)
        return true
    }

    /// Routes a controller move at the panel level to the tab rail, the panel controls or the dock items after
    /// the divider.
    func movePanelFocus(
        from target: StreamMenuFocusTarget,
        direction: MenuMoveDirection,
        in window: PlatformWindow
    ) {
        switch target {
        case .tab(let item):
            moveFromTab(item, direction: direction)
        case .control(let control):
            moveFromControl(control, direction: direction)
        case .settings, .log, .exit:
            moveFromDockItem(target, direction: direction, in: window)
        case .measureDone:
            store.send(.nudgeMarker(StreamBrightnessMeasureCard.nudge(for: direction)))
        }
    }

    /// Handles a controller move on a dock item after the divider: Left and Right move along the dock and Up
    /// enters the panel.
    func moveFromDockItem(
        _ item: StreamMenuFocusTarget,
        direction: MenuMoveDirection,
        in window: PlatformWindow
    ) {
        guard let index = dockItems.firstIndex(of: item) else {
            return
        }
        switch direction {
        case .left:
            if index > 0 {
                focusTarget = dockItems[index - 1]
            } else if let last = panels.last {
                focusTarget = .tab(last)
            }
        case .right:
            if dockItems.indices.contains(index + 1) {
                focusTarget = dockItems[index + 1]
            }
        case .up:
            focusLastControl()
        case .down:
            break
        }
    }

    /// Handles a controller move on a tab: Left and Right move along the rail and Up enters the panel,
    /// selecting it first when it is not the current panel.
    func moveFromTab(_ item: StreamMenuPanel, direction: MenuMoveDirection) {
        switch direction {
        case .left:
            moveTabFocus(by: -1)
        case .right:
            moveTabFocus(by: 1)
        case .up:
            if item == panel {
                focusLastControl()
            } else {
                selectPanelFromTab(item)
            }
        default:
            break
        }
    }

    /// Handles a controller move on a panel control, using seat columns in Players and rows in Statistics,
    /// and changing the value on Left and Right elsewhere.
    func moveFromControl(_ control: StreamMenuControl, direction: MenuMoveDirection) {
        if case .adjusting(let editing, _) = sliderNavigation, editing != control {
            sliderNavigation.leave()
        }
        if panel == .players {
            movePlayersFocus(control, direction: direction)
            return
        }
        switch direction {
        case .up, .down:
            sliderNavigation.leave()
            let upward = direction == .up
            if panel == .statistics {
                moveStatisticsRow(control, upward: upward)
            } else {
                moveControlFocus(
                    control,
                    by: upward
                        ? -1
                        : 1
                )
            }
        case .left:
            moveControlValue(control, by: -1)
        case .right:
            moveControlValue(control, by: 1)
        }
    }
}
