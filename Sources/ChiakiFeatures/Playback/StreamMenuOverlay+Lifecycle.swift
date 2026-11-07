import ChiakiClients
import PlatformUI
import MenuFocus
import SwiftUI

extension StreamMenuOverlay {
    /// Whether another presentation, such as a sheet or prompt, is blocking input in front of the
    /// stream menu.
    var hasOtherPresentation: Bool {
        navigator?.inputGate.isBlocking(besides: presentationID) ?? false
    }

    /// Removes the focus move, activation and Back handlers this overlay registered with the navigator.
    func unregisterFocusMoveHandler() {
        if let focusMoveHandlerID {
            navigator?.handlers.unregister(focusMoveHandlerID)
            self.focusMoveHandlerID = nil
        }
        if let activationHandlerID {
            navigator?.handlers.unregister(activationHandlerID)
            self.activationHandlerID = nil
        }
        if let backHandlerID {
            navigator?.handlers.unregister(backHandlerID)
            self.backHandlerID = nil
        }
    }

    /// Hands the controller back to the game: leaves the menu, removes the handlers and the input gate entry,
    /// then clears focus and announces that the stream controls closed.
    /// - Parameter save: Whether the draft configuration is saved on the way out.
    func returnToGameplay(save: Bool = true) {
        guard navigationActive else {
            return
        }
        store.send(.returnToGameplay(save: save))
        handBackController()
    }

    /// Gives the controller back to the game after the menu left navigation, whether the overlay or a feature
    /// such as a joined invitation closed it: removes the handlers and the input gate entry, then clears focus
    /// and announces that the stream controls closed.
    func handBackController() {
        sliderNavigation.leave()
        unregisterFocusMoveHandler()
        navigator?.inputGate.presentations.remove(presentationID)
        Task { @MainActor in
            await Task.yield()
            guard navigationLevel == .gameplay else {
                return
            }
            focusTarget = nil
            NotificationCenter.default.post(
                name: .streamControlsDismissed,
                object: PlaybackWindowControl.keyWindow
            )
        }
    }

    /// Opens the control panel with the dock, takes controller navigation, registers the navigator handlers
    /// and gates input.
    ///
    /// While the console hides its video the menu opens on the Session panel, which holds Go to Home screen.
    /// - Parameter target: The dock item or tab to focus, or `nil` for the open panel's tab.
    func open(focusing target: StreamMenuFocusTarget? = nil) {
        guard !navigationActive else {
            if let target {
                focusTarget = target
            }
            return
        }
        if target == nil, homeButtonShown {
            store.send(.selectPanel(.session))
        }
        store.send(.open)
        navigator?.inputGate.presentations.insert(presentationID)
        registerFocusMoveHandler()
        focusOpenedMenu(on: target)
    }

    /// Gives the opened menu its first focus, applying it again for a few turns because the dock is still
    /// appearing, and stopping once a control holds it or focus moved elsewhere.
    /// - Parameter target: The dock item or tab to focus, or `nil` for the open panel's tab.
    private func focusOpenedMenu(on target: StreamMenuFocusTarget?) {
        Task { @MainActor in
            for _ in 0..<10 {
                await Task.yield()
                guard panelPresented, let window = PlaybackWindowControl.keyWindow else {
                    return
                }
                let wanted = target ?? .tab(panel)
                if let current = focusTarget, current != wanted {
                    return
                }
                if focusTarget == wanted, navigator?.hasControlFocus(in: window) == true {
                    return
                }
                if focusTarget == wanted {
                    navigator?.ensureControlFocused(in: window)
                    focusTarget = nil
                    await Task.yield()
                }
                focusTarget = wanted
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    /// Opens the app settings over the stream from the dock.
    func openSettings() {
        navigator?.commands.send(.settings, to: PlaybackWindowControl.keyWindow)
    }

    /// Ends a slider adjustment by restoring the value it had when adjusting started.
    ///
    /// - Returns: `true` when a slider was being adjusted.
    func cancelSliderAdjustment() -> Bool {
        guard case .adjusting(let control, let original) = sliderNavigation else {
            return false
        }
        restoreSlider(control, from: original)
        sliderNavigation.leave()
        return true
    }

    /// Steps back one level: from measuring to the panel, from a control in the panel to the panel's tab in the
    /// dock, and from the dock to gameplay, after cancelling any slider adjustment or controller picking.
    ///
    /// Stopping at the tab keeps the dock one press away from anywhere in a long panel, such as far down the
    /// Trophies list.
    func exitLevel() {
        if cancelSliderAdjustment() {
            return
        }
        if cancelPlayerPickingIfNeeded() {
            return
        }
        switch navigationLevel {
        case .measuring:
            finishMeasuring()
        case .panel:
            if case .control = focusTarget {
                focusTarget = .tab(panel)
                return
            }
            returnToGameplay()
        case .gameplay:
            break
        }
    }

    /// The Statistics panel's Measure brightness action, or `nil` while the HDR heatmap is off.
    var measureBrightnessAction: (() -> Void)? {
        guard measuresBrightness else {
            return nil
        }
        return enterMeasuring
    }

    /// Starts moving the brightness marker by controller, with focus on the measuring card's Done button.
    func enterMeasuring() {
        guard panelPresented, measuresBrightness else {
            return
        }
        store.send(.enterMeasuring)
        guard navigationLevel == .measuring else {
            return
        }
        focusTarget = .measureDone
    }

    /// Stops moving the brightness marker and returns focus to the Measure brightness button.
    func finishMeasuring() {
        guard navigationLevel == .measuring else {
            return
        }
        store.send(.finishMeasuring)
        focusTarget = .control(.measureBrightness)
    }

    /// Opens the control panel from gameplay, or returns to gameplay from any menu level.
    func toggle() {
        if navigationLevel == .gameplay {
            open()
        } else {
            returnToGameplay()
        }
    }

    /// The controls in the Session panel, which include the Home button only when console commands are
    /// available and the Saved Data Management button only for a PS4 game streamed through PS Now.
    var sessionControls: [StreamMenuControl] {
        var controls: [StreamMenuControl] = []
        if store.consoleCommandsAvailable {
            controls.append(.sessionHome)
        }
        if store.offersSavedData {
            controls.append(.sessionSavedData)
        }
        controls.append(.sessionStop)
        return controls
    }

    /// The action for the Session panel's Saved Data Management button, or `nil` when the stream does not offer
    /// it; it hands the controller back to the game so the screen that opens in the stream can be used.
    var savedDataAction: (() -> Void)? {
        guard store.offersSavedData else {
            return nil
        }
        return {
            returnToGameplay()
            store.send(.openSavedData)
        }
    }

    /// The action for the Session panel's Home button, or `nil` when console commands are unavailable.
    var homeAction: (() -> Void)? {
        guard store.consoleCommandsAvailable else {
            return nil
        }
        return goHomeFromMenu
    }

    /// Returns to gameplay and asks the console to go to its Home screen.
    func goHomeFromMenu() {
        returnToGameplay()
        store.send(.goHome)
    }

    /// Records why the stream is stopping, leaves the menu without saving the draft and requests
    /// the stream exit.
    func stopAfterSaving() {
        let source = "the stream menu's \(stopTitle.english)"
        let owner: StreamStopTrace.Stream
        switch store.context {
        case .console, .guest:
            owner = .console
        case .cloud:
            owner = .cloud
        }
        stopTrace.record(owner, source)
        returnToGameplay(save: false)
        store.send(.requestExit(source))
    }
}
