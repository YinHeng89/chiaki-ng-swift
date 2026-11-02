import ChiakiFeatures
import ChiakiClients
import ChiakiClientsLive
import ChiakiDiagnostics
import ChiakiModels
import SwiftUI
import PlatformUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// The app's entry scene: builds the root store with live dependencies, runs any diagnostic requested on the
/// command line, and shows the main window.
struct ChiakiNGApp: App {
    /// The composition root the entry point built, which SwiftUI's parameterless app initialiser reads.
    private(set) static var composition: AppComposition?

    /// The playback diagnostic run by `--diagnose-playback`, over the composition root's stream leases.
    static let playbackDiagnosticRun = PlaybackDiagnostic()

    /// The root store for the whole app, wired to the native stream, couch, microphone, controller, launch
    /// and settings clients.
    static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
    }

    #if os(macOS)
        @NSApplicationDelegateAdaptor(ChiakiApplicationDelegate.self) private var appDelegate
    #else
        @UIApplicationDelegateAdaptor(ChiakiApplicationDelegate.self) private var appDelegate
    #endif
    private let diagnostic = DiagnosticRun(arguments: ProcessInfo.processInfo.arguments)
    /// The composition root, once ``run(_:)`` handed it over.
    static var root: AppComposition {
        guard let composition else {
            fatalError("ChiakiNGApp.run(_:) must hand the app its composition before SwiftUI starts it")
        }
        return composition
    }

    /// The live cloud catalog the screens draw artwork from and the release countdowns read the server time
    /// from.
    static var catalog: CatalogClient {
        @Dependency(\.catalog) var catalog
        return catalog
    }

    /// The live diagnostic log the screens write to.
    static var logger: LoggerClient {
        @Dependency(\.logger) var logger
        return logger
    }

    /// The live network checks the console cards classify addresses with.
    static var network: NetworkClient {
        @Dependency(\.network) var network
        return network
    }

    /// The controller services and menu navigator of the composition root.
    static var input: InputServices {
        root.input
    }

    /// Runs the app over a composition root that has already prepared the process's dependencies.
    ///
    /// - Parameter composition: The composition root.
    static func run(_ composition: AppComposition) {
        self.composition = composition
        main()
    }

    /// Raises the file limit, forwards any pending command-line launch to the store and starts any requested
    /// diagnostic, which prints its result and exits.
    init() {
        FileDescriptorLimit.raise()
        if let request = LaunchCommandLine.takePending() {
            Task { @MainActor in
                Self.store.send(.launchRequested(request))
            }
        }
        if let diagnostic {
            Task {
                print(await diagnostic.run())
                exit(0)
            }
        }
    }
    var body: some Scene {
        WindowGroup("chiaki-ng", id: "main") {
            if diagnostic == .playback {
                ZStack {
                    Color.black
                    if let surface = Self.playbackDiagnosticRun.surface {
                        StreamSurfaceView(surface: surface, videoFit: VideoFit())
                    } else {
                        ProgressView("Checking playback…")
                    }
                }.frame(width: 1280, height: 720)
            } else if let diagnostic {
                Text(diagnostic.status)
            } else {
                RootView(store: Self.store)
                    .tint(Palette.accent)
                    .toggleStyle(AccentCheckboxToggleStyle())
                    .screenLayout()
                #if os(macOS)
                    .frame(minWidth: 480, minHeight: 480)
                #else
                    .preferredColorScheme(.dark)
                #endif
                    .background(WindowOpeningSize())
                    .navigationControllerFamily(Self.input)
                    .menuNavigator(Self.input.menuNavigator)
                    .environment(\.controllerNavigation, Self.input)
                    .environment(\.signInPageViews, AccountSignInPages())
                    .environment(\.catalog, Self.catalog)
                    .environment(\.logger, Self.logger)
                    .environment(\.network, Self.network)
                    .environment(\.virtualGamepadLink, Self.input.virtualGamepadLink)
                    .environment(\.scaledArtCache, Self.root.scaledArt)
                    .environment(\.artContentBounds, Self.root.artBounds)
                    .environment(\.sampleArtStudio, Self.root.sampleArt)
                    .launchNotice(Self.store.scope(state: \.launch, action: \.launch))
                    .onOpenURL { url in
                        if KakusanBuild.included, let block = KakusanBlockFile.read(url) {
                            Self.store.send(.kakusanFileOpened(block))
                            return
                        }
                        LaunchCommandLine.open(url) { request in
                            Self.store.send(.launchRequested(request))
                        }
                    }
                    .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            }
        }
        .defaultSize(width: 1920, height: 1080)
        #if os(macOS)
            .windowStyle(.hiddenTitleBar)
        #endif
            .commands {
                MainWindowCommands(navigator: Self.input.menuNavigator)
                SettingsPanelCommands(navigator: Self.input.menuNavigator)
                #if DEBUG
                    DeveloperCommands()
                #endif
            }
    }
}

/// Receives application lifecycle events: starts and stops controller input and sleep observation, and lets
/// running streams close before the app quits.
@MainActor
final class ChiakiApplicationDelegate: NSObject {
    /// Watches system sleep and wake and tells the root store, which stops streams before sleep.
    static let power: SystemPowerObserver = SystemPowerObserver(
        willSleep: { notification in
            _ = ChiakiNGApp.store.send(.systemWillSleep(notification))
        },
        didWake: {
            _ = ChiakiNGApp.store.send(.systemDidWake)
        }
    )

    /// Watches the network the device uses and tells the root store when it changes.
    static let network = NetworkPathObserver {
        _ = ChiakiNGApp.store.send(.networkChanged)
    }
}

#if os(macOS)
    extension ChiakiApplicationDelegate: NSApplicationDelegate {
        /// Puts the whole app in dark mode before its first window opens, whatever the system appearance is.
        func applicationWillFinishLaunching(_ notification: Notification) {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        /// Starts controller input, sleep and network observation, clears retired cover art and finishes saving cloud
        /// captures left from before, in the background.
        func applicationDidFinishLaunching(_ notification: Notification) {
            ChiakiNGApp.input.start()
            Self.power.start()
            Self.network.start()
            Task.detached(priority: .background) {
                RetiredCoverStore.remove()
            }
            Task.detached(priority: .utility) {
                @Dependency(\.streamSession) var captures
                await captures.resumeCaptures()
            }
        }

        /// Quits at once when nothing is running, otherwise asks the store to shut streams down and replies
        /// once it has finished.
        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            let store = ChiakiNGApp.store
            switch store.termination {
            case .ready:
                return .terminateNow
            case .stopping:
                return .terminateLater
            case .running:
                let shutdown = store.send(.terminationRequested)
                Task { @MainActor in
                    await shutdown.finish()
                    sender.reply(toApplicationShouldTerminate: store.termination == .ready)
                }
                return .terminateLater
            }
        }

        /// Stops controller input, shuts the controller backend down and stops sleep and network observation.
        func applicationWillTerminate(_ notification: Notification) {
            ChiakiNGApp.input.stop()
            Self.power.stop()
            Self.network.stop()
        }

        /// Quits the app when its last window closes.
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }
    }
#else
    extension ChiakiApplicationDelegate: UIApplicationDelegate {
        /// Starts controller input, sleep and network observation, clears retired cover art and finishes saving cloud
        /// captures left from before, in the background.
        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            ChiakiNGApp.input.start()
            Self.power.start()
            Self.network.start()
            Task.detached(priority: .background) {
                RetiredCoverStore.remove()
            }
            Task.detached(priority: .utility) {
                @Dependency(\.streamSession) var captures
                await captures.resumeCaptures()
            }
            return true
        }

        /// Stops controller input, shuts the controller backend down and stops background and network observation.
        func applicationWillTerminate(_ application: UIApplication) {
            ChiakiNGApp.input.stop()
            Self.power.stop()
            Self.network.stop()
        }

        /// Limits the app to landscape orientations.
        func application(
            _ application: UIApplication,
            supportedInterfaceOrientationsFor window: UIWindow?
        ) -> UIInterfaceOrientationMask {
            .landscape
        }
    }
#endif

#if DEBUG
    private struct DeveloperCommands: Commands {
        @AppStorage(DeveloperPreviewSetting.samplePS5) private var samplePS5 = false
        @AppStorage(DeveloperPreviewSetting.samplePS4) private var samplePS4 = false

        var body: some Commands {
            CommandMenu("Developer") {
                Toggle("Show sample PS5", isOn: $samplePS5)
                Toggle("Show sample PS4", isOn: $samplePS4)
                Divider()
                FocusButton("Show both sample consoles") {
                    samplePS5 = true
                    samplePS4 = true
                }
                FocusButton("Hide sample consoles") {
                    samplePS5 = false
                    samplePS4 = false
                }
                .disabled(!samplePS5 && !samplePS4)
            }
        }
    }
#endif

/// The one diagnostic a launch runs instead of the app, chosen by the first `--diagnose-…` argument.
enum DiagnosticRun: Equatable {
    /// `--diagnose-registration`: checks registration with the saved console.
    case registration
    /// `--diagnose-playback`: streams the saved console and reports the frames.
    case playback
    /// `--diagnose-account`: renews the saved account and fetches its cloud catalog.
    case account
    /// `--diagnose-cloud-catalog`: reports on the first saved account's cloud catalog.
    case cloudCatalog
    /// `--diagnose-invitations`: lists each saved account's game invitations.
    case invitations

    /// Picks the diagnostic named by the first `--diagnose-…` argument.
    ///
    /// - Parameter arguments: The process's command-line arguments.
    /// - Returns: The diagnostic, or `nil` when no argument names one and the app runs normally.
    init?(arguments: [String]) {
        guard let run = arguments.lazy.compactMap(Self.init(flag:)).first else {
            return nil
        }
        self = run
    }

    private init?(flag: String) {
        switch flag {
        case "--diagnose-registration":
            self = .registration
        case "--diagnose-playback":
            self = .playback
        case "--diagnose-account":
            self = .account
        case "--diagnose-cloud-catalog":
            self = .cloudCatalog
        case "--diagnose-invitations":
            self = .invitations
        default:
            return nil
        }
    }

    /// What the window says while the diagnostic runs.
    var status: String {
        switch self {
        case .registration:
            "Checking registration…"
        case .playback:
            "Checking playback…"
        case .account:
            "Checking account services…"
        case .cloudCatalog:
            "Checking cloud catalog…"
        case .invitations:
            "Reading game invitations…"
        }
    }

    /// Runs the diagnostic.
    ///
    /// - Returns: The report to print.
    @MainActor
    func run() async -> String {
        switch self {
        case .registration:
            await RegistrationDiagnostic.run()
        case .playback:
            await ChiakiNGApp.playbackDiagnosticRun.run()
        case .account:
            await AccountDiagnostic.run()
        case .cloudCatalog:
            await CloudLibraryDiagnostic.run()
        case .invitations:
            await InvitationsDiagnostic.run()
        }
    }
}

private struct MainWindowCommands: Commands {
    /// The menu navigator that receives the stream menu command.
    let navigator: PlatformMenuNavigator
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Show chiaki-ng") {
                openWindow(id: "main")
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Stream Controls") {
                navigator.commands.send(.streamMenu, to: nil)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Stream Diagnostics Detail") {
                NotificationCenter.default.post(
                    name: .cycleStreamDiagnosticsLevel,
                    object: WindowFocus.keyWindow
                )
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Stream Diagnostics Glass") {
                NotificationCenter.default.post(
                    name: .cycleStreamDiagnosticsGlass,
                    object: WindowFocus.keyWindow
                )
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Live Developer Log") {
                NotificationCenter.default.post(name: .toggleLiveLog, object: WindowFocus.keyWindow)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Virtual Touchpad") {
                NotificationCenter.default.post(name: .toggleVirtualTouchpad, object: WindowFocus.keyWindow)
            }
        }
    }
}

#if os(macOS)
    /// Sizes the main window once, when it first appears, to 1920 by 1080 scaled down to fit the screen and
    /// centred.
    private struct WindowOpeningSize: NSViewRepresentable {
        /// Creates the invisible view that applies the size once it joins a window.
        func makeNSView(context: Context) -> SizingView {
            SizingView()
        }
        /// Leaves the view unchanged, since the size is applied only once.
        func updateNSView(_ nsView: SizingView, context: Context) {
        }

        /// An invisible view that ignores clicks and resizes and centres its window the first time it is
        /// attached.
        final class SizingView: NSView {
            /// Returns `nil` so clicks pass through to the views beneath.
            override func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }

            private var applied = false
            /// Applies the opening size on the next main-queue turn after the view first joins a window.
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window, !applied else {
                    return
                }
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, !self.applied else {
                        return
                    }
                    self.applied = true
                    let screen =
                        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
                    let scale = min(1, screen.width / 1920, screen.height / 1080)
                    let size = CGSize(
                        width: max(window.minSize.width, (1920 * scale).rounded(.down)),
                        height: max(window.minSize.height, (1080 * scale).rounded(.down))
                    )
                    let origin = CGPoint(
                        x: screen.midX - size.width / 2, y: screen.midY - size.height / 2
                    )
                    window.setFrame(CGRect(origin: origin, size: size), display: true)
                }
            }
        }
    }
#else
    /// A placeholder that does nothing on platforms where the system sizes the window.
    private struct WindowOpeningSize: View {
        var body: some View {
            EmptyView()
        }
    }
#endif
