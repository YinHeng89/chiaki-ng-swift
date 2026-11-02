import CInput
import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import Dependencies
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Polls SDL controller events every 4 ms and routes each one either to menu navigation or to the attached
/// stream, choosing which controller drives menus and when the stream owns input.
///
/// The poll stays on the main actor because routing reads windows, focus and menus. The stream's time-driven
/// input and feedback run on the real-time input clock of ``GameInputPipeline`` instead.
@MainActor final class SDLInputCoordinator {
    private let backend: SDLControllerBackend
    private let pipeline: GameInputPipeline
    private let lights: ControllerLights

    /// Creates the coordinator over the app's controller layer.
    ///
    /// - Parameters:
    ///   - backend: The connected controllers and their events.
    ///   - pipeline: The game input pipeline the native listener feeds once input starts.
    ///   - lights: The idle lightbar colours, repainted when controllers come and go.
    init(backend: SDLControllerBackend, pipeline: GameInputPipeline, lights: ControllerLights) {
        self.backend = backend
        self.pipeline = pipeline
        self.lights = lights
        polledEvents.reserveCapacity(256)
        forwardedEvents.reserveCapacity(256)
        secondaryEvents.reserveCapacity(256)
    }

    /// Whether button edges are written to the log, which only happens while the log level is debug.
    enum ButtonTracing: Equatable {
        /// Button edges are not traced.
        case off
        /// Every button edge and what the menu did with it is logged.
        case on
    }

    /// The preference key of the controller the user picked for menus outside a stream, or the keyboard-only
    /// key to ignore controllers.
    var preferredControllerKey: String?
    /// The controls settings; changing the stream menu shortcut updates navigation, changing a
    /// controller's button layout re-chooses the menu controller and changing background input tells the
    /// playing stream whether it can still be played while the app is hidden.
    var controlsConfiguration = ControlsConfiguration() {
        didSet {
            navigation.streamMenuChord = controlsConfiguration.streamMenuShortcut.chord
            if controlsConfiguration.backgroundInput != oldValue.backgroundInput {
                streamControls?.backgroundInputChanged()
            }
            if controlsConfiguration.controllers.mapValues(\.buttonLayout)
                != oldValue.controllers.mapValues(\.buttonLayout) {
                refreshDevice()
            }
        }
    }
    /// Whether the stream menu is open, which hands controller input to menu navigation instead of the
    /// stream.
    var streamNavigationActive = false
    /// Whether the Create button is read as PS5 cloud gestures instead of being sent as a button, as in
    /// cloud streams.
    var createButtonCaptures = false {
        didSet {
            createGesture.reset()
        }
    }
    private var createGesture = CreateButtonGesture()
    /// The live player's controls, which receive the Create presses of a cloud stream.
    weak var streamControls: StreamPlayerControls?
    /// Whether a PS button press hands the controller back to the console, press included, while menus have
    /// the controller.
    var systemButtonReachesStream: Bool {
        get {
            navigation.systemButtonReachesStream
        }
        set {
            navigation.systemButtonReachesStream = newValue
        }
    }
    /// Whether the PS button opens the stream menu instead of reaching the stream, as in cloud streams.
    var systemButtonOpensStreamMenu: Bool {
        get {
            navigation.systemButtonOpensStreamMenu
        }
        set {
            navigation.systemButtonOpensStreamMenu = newValue
        }
    }

    /// The left stick of the controller driving menus, each axis from -1 to 1.
    var navigationStick: CGVector {
        CGVector(
            dx: Double(navigation.axes[0]) / Double(Int16.max),
            dy: Double(navigation.axes[1]) / Double(Int16.max)
        )
    }
    private var labelLayouts: Set<UInt32> = []
    private var timer: Timer?
    private var lastRouteReason = ""
    private var navigation = ControllerNavigationState()
    private var device: UInt32?
    private var navigationOverride: UInt32?
    private var menuFollow = MenuControllerFollow()
    private var lastCommand: RecentCommand?
    private var handedToStream = false
    private var navigationDevice: UInt32? {
        navigationOverride ?? device
    }
    private var ticks = 0
    private var polledEvents: [nx_input_event] = []
    private var forwardedEvents: [nx_input_event] = []
    private var secondaryEvents: [nx_input_event] = []
    private var buttonTracing = ButtonTracing.off
    private var buttonTracingRequest = 0
    private var stream: Stream?
    private weak var lastWindow: PlatformWindow?
    private var buttonCapture: ButtonCapture?
    /// The family of the controller driving menus, used to pick button glyphs.
    private(set) var navigationFamily = ControllerFamily.playStation
    /// Whether the menu controller's face buttons follow their position or their printed labels.
    private(set) var navigationButtonLayout = ButtonLayout.position
    /// Whether any controller currently drives menus.
    private(set) var navigationConnected = false
    /// Whether at least one controller is connected, as last reported to the menu input mode.
    var controllerAttached = false
    /// The platform menu navigator that receives menu commands and owns focus.
    var menuNavigator: PlatformMenuNavigator?

    /// Whether an open settings panel or other input gate is blocking menu navigation.
    var menuInputBlocked: Bool {
        menuNavigator?.inputGate.isBlocking ?? false
    }

    /// Whether controller input currently goes to menus rather than the stream.
    var acceptsMenuInput: Bool {
        route == .menu
    }

    /// Maps a key to the previous or next tab command while menus have input.
    /// - Parameter keyCode: The Mac key code that was pressed.
    /// - Returns: The tab command, or `nil` when menus do not have input or the key is not bound to a
    ///   shoulder button.
    func menuTabCommand(for keyCode: Int) -> MenuCommand? {
        guard route == .menu else {
            return nil
        }
        return Self.keyboardTabCommand(for: keyCode, configuration: controlsConfiguration)
    }

    private struct ButtonCapture {
        let id: UUID
        let device: UInt32?
        var state = ControllerButtonCaptureState()
        let receive: (ControllerButtonCaptureState.Outcome) -> Void
    }

    /// Starts capturing the next controller button press for a button binding, replacing any capture in
    /// progress.
    /// - Parameters:
    ///   - device: The controller to listen to, or `nil` for the menu controller.
    ///   - receive: Called with the captured button, or when the capture expires.
    /// - Returns: A token that identifies this capture for ``SDLInputCoordinator/endButtonCapture(_:)``.
    func beginButtonCapture(
        device: UInt32?,
        receive: @escaping (ControllerButtonCaptureState.Outcome) -> Void
    ) -> UUID {
        let id = UUID()
        buttonCapture = ButtonCapture(id: id, device: device, receive: receive)
        return id
    }

    /// Cancels a button capture if it is still the current one.
    /// - Parameter id: The token returned by ``SDLInputCoordinator/beginButtonCapture(device:receive:)``.
    func endButtonCapture(_ id: UUID) {
        guard buttonCapture?.id == id else {
            return
        }
        buttonCapture = nil
    }

    private struct Stream {
        let id: UUID
        var preferredKey: String?
        let window: () -> PlatformWindow?
        let receive: ([nx_input_event], Bool) -> Void
        let secondary: ([nx_input_event], Bool) -> Void
        let seated: () -> Set<UInt32>
    }

    /// Changes the preferred controller of the attached stream and re-chooses the menu controller; ignored
    /// when no stream is attached.
    /// - Parameter key: The preference key of the controller player one uses.
    func updateStreamPreferredKey(_ key: String?) {
        guard stream != nil else {
            return
        }
        stream?.preferredKey = key
        refreshDevice()
    }

    /// Hands menu navigation to another controller, for example one answering a prompt, or returns it to
    /// player one's controller.
    /// - Parameter next: The SDL instance id of the controller to use, or `nil` to return to player one's
    ///   controller.
    func overrideNavigation(_ next: UInt32?) {
        guard navigationOverride != next else {
            return
        }
        navigationOverride = next
        navigation.reset()
        let message = next.map { "menu navigation handed to controller \($0)" }
            ?? "menu navigation returned to player 1's controller"
        @Dependency(\.logger) var logger
        logger.enqueue(.controllerDiagnostic(message))
    }

    /// Reports whether the window shows the attached stream.
    /// - Parameter window: The window to test.
    /// - Returns: `true` when the attached stream lives in that window.
    func hostsStream(_ window: PlatformWindow) -> Bool {
        stream?.window() === window
    }

    /// Describes the last menu commands a controller sent if they arrived recently, for diagnosing why a
    /// stream stopped.
    /// - Parameter seconds: How far back in time to look.
    /// - Returns: A description of the controller and commands, or `nil` when nothing was sent in that
    ///   window.
    func recentCommand(within seconds: TimeInterval) -> String? {
        guard let lastCommand,
              ProcessInfo.processInfo.systemUptime - lastCommand.time <= seconds else {
            return nil
        }
        let names = lastCommand.commands.map { "\($0)" }.joined(separator: ", ")
        return "controller \(lastCommand.device) sent \(names)"
    }

    /// Starts the menu navigator, installs the game input pipeline and begins polling controllers, doing
    /// nothing if already running.
    func start() {
        guard timer == nil else {
            return
        }
        menuNavigator?.start()
        pipeline.install()
        refreshDevice()
        reloadButtonTracing()
        let timer = Timer(timeInterval: 0.004, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        timer.tolerance = 0.001
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops polling and the menu navigator, releases the stream's held input and forgets the stream,
    /// navigation override and any button capture.
    func stop() {
        timer?.invalidate()
        timer = nil
        menuNavigator?.stop()
        stream?.receive([], false)
        stream?.secondary([], false)
        stream = nil
        navigationOverride = nil
        navigation.reset()
        streamNavigationActive = false
        buttonCapture = nil
    }

    /// Attaches a stream that receives controller input when it has the route, and starts polling.
    /// - Parameters:
    ///   - preferredKey: The preference key of player one's controller.
    ///   - window: Returns the window that shows the stream.
    ///   - receive: Called each poll with player one's events and whether the stream owns input.
    ///   - secondary: Called each poll with connection events and other controllers' events, and whether
    ///     input is routed anywhere.
    ///   - seated: Returns the controllers already seated as other players, which are never chosen for menus.
    /// - Returns: A token for ``SDLInputCoordinator/detachStream(_:)``.
    func attachStream(preferredKey: String?, window: @escaping () -> PlatformWindow?,
                      receive: @escaping ([nx_input_event], Bool) -> Void,
                      secondary: @escaping ([nx_input_event], Bool) -> Void = { _, _ in
                      },
                      seated: @escaping () -> Set<UInt32> = {
                          []
                      }) -> UUID {
        stream?.receive([], false)
        stream?.secondary([], false)
        navigationOverride = nil
        menuFollow.reset()
        let id = UUID()
        stream = Stream(
            id: id,
            preferredKey: preferredKey,
            window: window,
            receive: receive,
            secondary: secondary,
            seated: seated
        )
        navigation.setRoute(.inactive)
        refreshDevice()
        reloadButtonTracing()
        start()
        return id
    }

    /// Detaches the stream if the token still matches, returning input to menus.
    /// - Parameter id: The token returned by
    ///   ``SDLInputCoordinator/attachStream(preferredKey:window:receive:secondary:seated:)``.
    func detachStream(_ id: UUID) {
        guard stream?.id == id else {
            return
        }
        stream = nil
        navigationOverride = nil
        navigation.setRoute(.inactive)
        streamNavigationActive = false
        refreshDevice()
    }
}

extension SDLInputCoordinator {
    private var route: ControllerNavigationState.Route {
        let (route, reason) = routeWithReason
        if reason != lastRouteReason {
            lastRouteReason = reason
            @Dependency(\.logger) var logger
            if stream != nil {
                logger.enqueue(.controllerDiagnostic("Stream controller route \(route): \(reason)"))
            } else {
                logger.enqueue(.diagnostic(.controller, .debug, "Menu controller route \(route): \(reason)"))
            }
        }
        return route
    }

    private var menusFollowUse: Bool {
        stream == nil || navigation.route == .menu
    }

    private var routeWithReason: (ControllerNavigationState.Route, String) {
        guard PlaybackWindowControl.isApplicationActive else {
            return backgroundRoute
        }
        guard let window = menuNavigator?.activeWindow else {
            return (.inactive, "no key or main window")
        }
        #if os(macOS)
            guard !(window.firstResponder is KeyBindingCapture.CaptureView) else {
                return (.inactive, "a key binding is being captured")
            }
        #endif
        guard stream?.window() === window else {
            return (.menu, "the key window is not the stream window (\(type(of: window)))")
        }
        guard !menuInputBlocked else {
            return (.menu, "a settings panel is open")
        }
        guard !(menuNavigator?.isTrackingMenu ?? false) else {
            return (.menu, "a menu is being tracked")
        }
        guard !PlaybackWindowControl.hasAttachedSheet(window) else {
            return (.menu, "a sheet is attached")
        }
        return streamNavigationActive
            ? (.menu, "stream navigation is active")
            : (.stream, "the stream has input")
    }

    private var backgroundRoute: (ControllerNavigationState.Route, String) {
        guard controlsConfiguration.backgroundInput, let window = stream?.window() else {
            return (.inactive, "the app is not active")
        }
        guard !streamNavigationActive, !menuInputBlocked,
              !PlaybackWindowControl.hasAttachedSheet(window) else {
            return (.inactive, "the app is not active and the stream menu is open")
        }
        return (.stream, "the app is in the background and background controller input is on")
    }

    private func refreshDevice() {
        let timing = SlowStep("choosing the menu controller")
        defer {
            timing.finish()
        }
        let key: String?
        if let stream {
            key = stream.preferredKey
        } else if preferredControllerKey == ControlsConfiguration.keyboardOnlyKey {
            key = nil
        } else {
            key = preferredControllerKey
        }
        let seated = stream?.seated() ?? []
        let devices = try? backend.devices()
        let available = devices?.filter { !seated.contains($0.id) } ?? []
        let fallback = key == ControlsConfiguration.keyboardOnlyKey
            ? nil
            : available.first
        let preferred = available.first { key == nil || $0.preferenceKey == key } ?? fallback
        let chosen = menuFollow.choose(from: available, preferred: preferred, menusOnly: menusFollowUse)
        let family = chosen?.family ?? .playStation
        labelLayouts = Set((devices ?? []).filter { layout(for: $0) == .label }.map(\.id))
        let buttonLayout = chosen.map(layout(for:)) ?? .position
        publishNavigation(family: family, layout: buttonLayout, connected: chosen != nil)
        if let devices {
            let attached = SlowStep("updating the input mode")
            noteControllerAttached(!devices.isEmpty)
            attached.finish()
        }
        let next = chosen?.id
        if next != device {
            let release = SlowStep("releasing the stream's held input")
            stream?.receive([], false)
            release.finish()
            navigation.switchController()
            device = next
            let message = chosen.map { "menu navigation follows \"\($0.name)\" (controller \($0.id))" }
                ?? "menu navigation has no controller"
            @Dependency(\.logger) var logger
            logger.enqueue(.controllerDiagnostic(message))
        }
    }

    private func poll() {
        ticks += 1
        if ticks % 250 == 0 {
            refreshDevice()
        }
        let activeWindow = menuNavigator?.activeWindow
        if lastWindow !== activeWindow {
            navigation.setRoute(.inactive)
            lastWindow = activeWindow
        }
        navigation.setRoute(route)
        if !menusFollowUse, menuFollow.state != .preferred {
            menuFollow.reset()
            refreshDevice()
        }
        let initialRoute = navigation.route
        handedToStream = false
        let seated = stream?.seated() ?? []
        forwardedEvents.removeAll(keepingCapacity: true)
        secondaryEvents.removeAll(keepingCapacity: true)
        backend.readEvents(into: &polledEvents)
        let now = ProcessInfo.processInfo.systemUptime
        for event in polledEvents.lazy.map({ self.labelled($0) }) {
            if !seated.contains(event.instance), menuFollow.adopt(
                event,
                current: device,
                menusOnly: menusFollowUse && navigationOverride == nil
            ) {
                refreshDevice()
            }
            if event.kind == ControllerInputEvent.removed || event.kind == ControllerInputEvent.added
                || (event.instance != navigationDevice && event.instance != device) {
                secondaryEvents.append(event)
            }
            if process(event, now: now) {
                forwardedEvents.append(event)
            }
        }
        expireTimedInput(now: now)
        navigation.setRoute(route)
        if initialRoute != navigation.route, !handedToStream {
            forwardedEvents.removeAll {
                $0.kind != ControllerInputEvent.added && $0.kind != ControllerInputEvent.removed
            }
        }
        stream?.receive(forwardedEvents, navigation.route == .stream)
        stream?.secondary(secondaryEvents, navigation.route != .inactive)
    }

    private func expireTimedInput(now: TimeInterval) {
        if let press = createGesture.expire(now: now) {
            streamControls?.pressCreate(press)
        }
        if var capture = buttonCapture, let outcome = capture.state.expire(now: now) {
            buttonCapture = nil
            capture.receive(outcome)
        }
        if let command = navigation.repeatCommand(now: now) {
            menuNavigator?.perform(command)
        }
    }

    private func controllersChanged() {
        refreshDevice()
        lights.controllersChanged()
    }

    private func process(_ event: nx_input_event, now: TimeInterval) -> Bool {
        if event.kind == ControllerInputEvent.added || event.kind == ControllerInputEvent.removed {
            traceConnection(event)
            controllersChanged()
            return true
        }
        if let forwarded = forwardsMotionOrTouch(event) {
            return forwarded
        }
        if captureButton(event, now: now) {
            return false
        }
        if navigationOverride != nil, event.instance == device {
            traceButton(event, outcome: "kept for the stream while another controller answers a prompt")
            return navigation.route == .stream
        }
        guard event.instance == navigationDevice else {
            traceButton(
                event,
                outcome: "ignored: controller \(navigationDevice.map(String.init) ?? "none") drives menus"
            )
            return false
        }
        if createButtonCaptures, navigation.route == .stream, event.kind == ControllerInputEvent.button,
           Int(event.control) == CreateButtonGesture.button {
            if let press = createGesture.button(down: event.value != 0, now: now) {
                streamControls?.pressCreate(press)
            }
            traceButton(event, outcome: "Create gesture for the cloud console")
            return false
        }
        if handsControllerToStream(event) {
            return true
        }
        let entered = Self.isDeliberate(event) && (menuNavigator?.inputMode.controllerInput() ?? false)
        var commands = navigationCommands(for: event, now: now)
        if !commands.isEmpty {
            lastCommand = RecentCommand(commands: commands, device: event.instance, time: now)
        }
        var restored = false
        if entered, navigation.route == .menu, let window = menuNavigator?.activeWindow,
           menuNavigator?.restoreFocus(in: window) == true {
            restored = commands.contains { Self.focusCommands.contains($0) }
            commands.removeAll { Self.focusCommands.contains($0) }
        }
        traceButton(event, outcome: restored
            ? "used to bring back the focus highlight after pointer input"
            : "route \(navigation.route), commands \(commands)")
        perform(commands)
        switch event.kind {
        case ControllerInputEvent.button:
            return navigation.permitsStreamButton(Int(event.control))
        case ControllerInputEvent.axis:
            return navigation.permitsStreamAxis(Int(event.control))
        default:
            return false
        }
    }

    private func handsControllerToStream(_ event: nx_input_event) -> Bool {
        guard event.kind == ControllerInputEvent.button,
              navigation.handsControllerToStream(Int(event.control), down: event.value != 0) else {
            return false
        }
        streamNavigationActive = false
        navigation.setRoute(route)
        handedToStream = true
        traceButton(event, outcome: "PS button hands the controller back to the console")
        return true
    }

    private func forwardsMotionOrTouch(_ event: nx_input_event) -> Bool? {
        if ControllerInputEvent.isSensor(event) {
            return event.instance == device
        }
        if ControllerInputEvent.isTouch(event) {
            return event.instance == device && navigation.route == .stream
        }
        return nil
    }

    private func captureButton(_ event: nx_input_event, now: TimeInterval) -> Bool {
        guard var capture = buttonCapture, route == .menu, event.kind == ControllerInputEvent.button,
              event.instance == capture.device ?? navigationDevice else {
            return false
        }
        let result = capture.state.button(Int(event.control), down: event.value != 0, now: now)
        if let outcome = result.outcome {
            buttonCapture = nil
            capture.receive(outcome)
        } else {
            buttonCapture = capture
        }
        return result.consumed
    }

    private func navigationCommands(
        for event: nx_input_event,
        now: TimeInterval
    ) -> [MenuCommand] {
        switch event.kind {
        case ControllerInputEvent.button:
            navigation.button(Int(event.control), down: event.value != 0, now: now)
        case ControllerInputEvent.axis:
            navigation.axis(Int(event.control), value: Int(event.value), now: now)
        default:
            []
        }
    }

    private func perform(_ commands: [MenuCommand]) {
        for command in commands {
            if command == .streamMenu {
                streamNavigationActive = navigation.route != .menu
            }
            if command == .streamMenu || command == .settings {
                stream?.receive([], false)
            }
            menuNavigator?.perform(command)
            navigation.setRoute(route)
        }
    }
}

extension SDLInputCoordinator {
    /// Returns the button layout configured for a controller, which only Nintendo controllers can change from
    /// position.
    /// - Parameter device: The controller to look up.
    /// - Returns: The configured layout, or position by default.
    func layout(for device: ControllerDevice) -> ButtonLayout {
        guard device.family == .nintendo else {
            return .position
        }
        return controlsConfiguration.controllers[device.preferenceKey]?.buttonLayout ?? .position
    }

    /// Remaps a button event from a controller set to the label layout so its control matches the printed
    /// label.
    /// - Parameter event: The raw controller event.
    /// - Returns: The remapped event, or the event unchanged when no remapping applies.
    func labelled(_ event: nx_input_event) -> nx_input_event {
        guard event.kind == ControllerInputEvent.button, labelLayouts.contains(event.instance) else {
            return event
        }
        var remapped = event
        remapped.control = Int32(ButtonLayout.label.code(Int(event.control), family: .nintendo))
        return remapped
    }

    /// Records the menu controller's family, layout and connection, resetting navigation when the layout
    /// changes and posting a controller family change so glyphs refresh.
    /// - Parameters:
    ///   - family: The family of the menu controller.
    ///   - layout: Its button layout.
    ///   - connected: Whether any controller drives menus.
    func publishNavigation(family: ControllerFamily, layout: ButtonLayout, connected: Bool) {
        guard family != navigationFamily || connected != navigationConnected || layout !=
            navigationButtonLayout
        else {
            return
        }
        if layout != navigationButtonLayout {
            navigation.switchController()
        }
        navigationFamily = family
        navigationButtonLayout = layout
        navigationConnected = connected
        let glyphs = SlowStep("updating controller glyphs")
        NotificationCenter.default.post(name: .controllerFamilyChanged, object: nil)
        glyphs.finish()
    }
}

extension SDLInputCoordinator {
    /// The last menu commands a controller produced, kept so ``SDLInputCoordinator/recentCommand(within:)``
    /// can report what preceded a stream stop.
    struct RecentCommand {
        /// The commands that were produced.
        let commands: [MenuCommand]
        /// The SDL instance id of the controller that produced them.
        let device: UInt32
        /// The system uptime in seconds when they were produced.
        let time: TimeInterval
    }

    /// Mac key codes that already navigate menus, such as Return, Tab, Space, Escape, Enter and the arrow
    /// keys, so they are never treated as tab switches.
    static let menuNavigationKeyCodes: Set<Int> = [36, 48, 49, 53, 76, 123, 124, 125, 126]

    /// Maps a key bound to a shoulder button in the controls preset to the previous or next menu tab command.
    /// - Parameters:
    ///   - keyCode: The Mac key code that was pressed.
    ///   - configuration: The controls configuration whose preset supplies key bindings.
    /// - Returns: `previous` or `next` for keys bound to the left or right shoulder, otherwise `nil`.
    static func keyboardTabCommand(
        for keyCode: Int,
        configuration: ControlsConfiguration
    ) -> MenuCommand? {
        guard !menuNavigationKeyCodes.contains(keyCode),
              let binding = configuration.keyboardPreset.bindings.first(where: {
                  $0.source == .macKey && $0.code == keyCode
              }) else {
            return nil
        }
        switch binding.target {
        case .leftShoulder:
            return .previous
        case .rightShoulder:
            return .next
        default:
            return nil
        }
    }

    /// The menu commands that move or act on focus.
    static let focusCommands: Set<MenuCommand> = [
        .up, .down, .left, .right, .confirm, .back
    ]

    /// Reports whether an event is a deliberate press, meaning a button going down or a stick pushed well
    /// past its dead zone.
    /// - Parameter event: The raw controller event.
    /// - Returns: `true` for a pressed button or an axis beyond 8000.
    static func isDeliberate(_ event: nx_input_event) -> Bool {
        switch event.kind {
        case ControllerInputEvent.button:
            event.value != 0
        case ControllerInputEvent.axis:
            abs(Int(event.value)) > 8000
        default:
            false
        }
    }
}

extension SDLInputCoordinator {
    /// Logs a debug line describing a controller button edge and what the menu did with it, only while
    /// ``SDLInputCoordinator/ButtonTracing/on`` is in force, so a stream builds no message and starts no task
    /// per press otherwise.
    /// - Parameters:
    ///   - event: The raw controller event; non-button events are ignored.
    ///   - outcome: A short description of how the menu handled the press, built only when it is logged.
    func traceButton(_ event: nx_input_event, outcome: @autoclosure () -> String) {
        guard buttonTracing == .on, event.kind == ControllerInputEvent.button else {
            return
        }
        let edge = event.value != 0
            ? "down"
            : "up"
        let message = "Menu input: button \(event.control) \(edge) on controller \(event.instance) at "
            + "\(event.timestamp_us / 1000) ms: \(outcome())"
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.controller, .debug, message))
    }

    /// Reads the log level and turns button tracing on only while it is debug; a reading overtaken by a later
    /// one is dropped.
    func reloadButtonTracing() {
        buttonTracingRequest &+= 1
        let request = buttonTracingRequest
        Task { [weak self] in
            @Dependency(\.logSettings) var logSettings
            let level = (try? await logSettings.load().level) ?? .info
            guard let self, buttonTracingRequest == request else {
                return
            }
            buttonTracing = level == .debug
                ? .on
                : .off
        }
    }

    /// Logs a debug line when a controller connects or disconnects.
    /// - Parameter event: The raw add or remove event.
    func traceConnection(_ event: nx_input_event) {
        let change = event.kind == ControllerInputEvent.added
            ? "connected"
            : "disconnected"
        let message = "Controller \(event.instance) \(change)"
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.controller, .debug, message))
    }
}

extension SDLInputCoordinator {
    /// Records whether any controller is attached and, when that flips the menu input mode, releases menu
    /// focus on detach or restores it in the active window on attach.
    /// - Parameter attached: Whether at least one controller is now connected.
    func noteControllerAttached(_ attached: Bool) {
        guard attached != controllerAttached else {
            return
        }
        controllerAttached = attached
        let message = attached
            ? "A controller is attached"
            : "No controller is attached"
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.controller, .debug, message))
        guard menuNavigator?.inputMode.controllerConnection(attached) == true else {
            return
        }
        guard attached else {
            #if os(macOS)
                menuNavigator?.releaseFocus(in: NSApp.windows)
            #else
                menuNavigator?.releaseFocus(in: menuNavigator?.activeWindow.map { [$0] } ?? [])
            #endif
            return
        }
        if let window = menuNavigator?.activeWindow {
            _ = menuNavigator?.restoreFocus(in: window)
        }
    }
}
