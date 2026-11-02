import ChiakiModels
import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus
import Foundation

/// A full-screen cloud loading scene that stages backdrop, hero art, logo and a status strip with a Cancel
/// button, then animates them away when leaving.
struct CloudLayeredLoadingView: View {
    /// Whether the layers have begun their entrance animation.
    enum Arrival: Equatable {
        /// The layers have not appeared yet, or have appeared and are animating in.
        case pending, arrived
    }

    /// Whether the backdrop's slow zoom loop is running.
    enum Drift: Equatable {
        /// The backdrop is at rest, or zooming slowly back and forth.
        case still, drifting
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @MenuFocusState private var cancelFocused: Bool
    @Environment(\.menuNavigator) private var navigator
    @State private var hostWindow: PlatformWindow?
    @State private var arrival = Arrival.pending
    @State private var drift = Drift.still
    @State private var chromeInFront = CloudLoadingChrome.status
    /// The game artwork to stage: a backdrop plus optional hero and logo layers.
    let layers: GameArtLayers
    /// The game title, shown when there is no logo and used as the logo's accessibility label.
    let title: String
    /// The current launch status line shown in the strip.
    let status: String
    /// A timed service wait shown beneath the status with its live elapsed text, when present.
    var operation: TimedProgress?
    /// Whether the scene is playing its exit animation.
    let leaving: Bool
    /// Which chrome is in front; while the datacenter picker shows, the logo and strip withdraw and Cancel
    /// does nothing.
    var chrome = CloudLoadingChrome.status
    /// Called when the player activates Cancel while the status chrome is showing.
    let cancel: () -> Void
    @Environment(\.screenLayout) private var layout

    private var edge: CGFloat {
        layout.isCompact
            ? 28 + layout.sideInset
            : 56
    }

    private var stage: CloudLoadingStage {
        if leaving {
            return .leaving
        }
        return arrival == .arrived
            ? .shown
            : .arriving
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                backdrop(geometry.size)
                hero(geometry.size)
                shade
                    .cloudLoadingStaged(.shade, stage)
                titleArt
                    .padding(.leading, edge)
                    .padding(.bottom, 138)
                    .cloudLoadingStaged(.logo, stage, chrome: chrome)
                strip
                    .padding(.horizontal, edge)
                    .padding(.bottom, 34)
                    .cloudLoadingStaged(.strip, stage, chrome: chrome)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cloud-layered-loading")
        .onAppear {
            arrival = .arrived
            drift = .drifting
        }
        .background(WindowAccessor { hostWindow = $0 })
        .onChange(of: chrome, initial: true) { _, front in
            chromeInFront = front
        }
        .task(id: chrome) {
            guard chrome == .status else {
                return
            }
            await Task.yield()
            cancelFocused = true
            navigator?.ensureFocus(
                in: { hostWindow },
                reset: {},
                apply: {
                    guard chromeInFront == .status else {
                        return
                    }
                    cancelFocused = true
                }
            )
        }
        .onChange(of: cancelFocused) { _, focused in
            guard focused, chrome != .status else {
                return
            }
            cancelFocused = false
            NotificationCenter.default.post(
                name: .focusLibraryContent,
                object: PlaybackWindowControl.keyWindow
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLibraryContent)) { notification in
            guard chrome == .status, let window = notification.object as? PlatformWindow,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            cancelFocused = true
        }
    }

    @ViewBuilder private var titleArt: some View {
        if let logo = layers.logo {
            ScaledArt(
                image: logo,
                size: ScaledArtCache.fitted(logo, in: CGSize(width: 300, height: 180))
            )
            .accessibilityLabel(title)
        } else {
            Text(title)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
        }
    }

    private func backdrop(_ size: CGSize) -> some View {
        Image(decorative: layers.backdrop, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(drift == .drifting && !reduceMotion
                ? CloudLoadingLayer.driftScale
                : 1)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: CloudLoadingLayer.drift).repeatForever(autoreverses: true)
                            .delay(1.6),
                    value: drift
                )
                .clipped()
                .cloudLoadingStaged(.backdrop, stage)
    }

    @ViewBuilder private func hero(_ size: CGSize) -> some View {
        if let hero = layers.layered?.hero {
            Color.clear
                .overlay(alignment: .center) {
                    Image(decorative: hero, scale: 1)
                        .resizable()
                        .frame(
                            width: size.height * CGFloat(hero.width) / CGFloat(max(1, hero.height)),
                            height: size.height
                        )
                        .cloudLoadingStaged(.hero, stage)
                }
        }
    }

    private var shade: some View {
        LinearGradient(
            stops: [
                .init(color: CloudGameDetail.detailPage.opacity(0.9), location: 0),
                .init(color: CloudGameDetail.detailPage.opacity(0.5), location: 0.2),
                .init(color: CloudGameDetail.detailPage.opacity(0), location: 0.44)
            ],
            startPoint: .bottom, endPoint: .top
        )
        .allowsHitTesting(false)
    }

    private var strip: some View {
        HStack(spacing: 18) {
            Text("Starting your stream")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(width: 1, height: 32)
            detail
                .frame(
                    minWidth: layout.isCompact
                        ? 0
                        : 340,
                    maxWidth: layout.isCompact
                        ? .infinity
                        : 340,
                    alignment: .leading
                )
            FocusButton("Cancel") {
                if chrome == .status {
                    cancel()
                }
            }
            .glassControlStyle()
            .focusBorderShape(.capsule)
            .controlSize(.large)
            .menuFocused($cancelFocused)
            .environment(\.menuMove) { direction in
                if direction == .up {
                    cancelFocused = false
                    NotificationCenter.default.post(
                        name: .focusSettingsControl,
                        object: PlaybackWindowControl.keyWindow
                    )
                }
            }
            .accessibilityIdentifier("cloud-loading-cancel")
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(height: 56)
        .glassEffect(AppGlass.control, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 28, y: 12)
    }

    @ViewBuilder private var detail: some View {
        if let operation {
            TimelineView(.periodic(from: operation.receivedAt, by: 1)) { context in
                let wait = CloudLoadingWait(operation.text(at: context.date))
                VStack(alignment: .leading, spacing: 2) {
                    statusLine
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(wait.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize()
                        ScrollingText(text: wait.detail, font: .system(size: 12), trigger: .always)
                            .foregroundStyle(.white.opacity(0.56))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(wait.spoken)
                    .accessibilityIdentifier("operation-progress")
                }
            }
        } else {
            statusLine
        }
    }

    private var statusLine: some View {
        ScrollingText(text: status, font: .system(size: 14), trigger: .always)
            .foregroundStyle(.white.opacity(0.76))
    }
}

/// The headline and joined detail line of an operation wait, as shown in the cloud loading strip.
struct CloudLoadingWait: Equatable {
    /// The text placed between detail fragments.
    static let separator = ", "

    /// The headline of the wait.
    let title: String
    /// The wait's details joined into one line, empty when there are none.
    let detail: String

    /// Builds the display form of an operation progress text.
    /// - Parameter text: The service's progress text at the current moment.
    init(_ text: OperationProgressText) {
        title = text.title
        detail = text.details.joined(separator: Self.separator)
    }

    /// The headline and detail joined for VoiceOver, leaving out an empty detail.
    var spoken: String {
        ([title] + (detail.isEmpty
                ? []
                : [detail])).joined(separator: ", ")
    }
}

/// Where the cloud loading scene is in its lifecycle, which drives each layer's entrance and exit animation.
enum CloudLoadingStage: Equatable {
    /// The layers sit at their pre-entrance transforms, before animating in.
    case arriving
    /// The layers are fully visible and at rest.
    case shown
    /// The layers are animating out as the stream takes over.
    case leaving
}

/// One visual layer of the cloud loading scene, with its own entrance animation, exit timing and per-stage
/// transforms.
enum CloudLoadingLayer {
    /// The backdrop art, hero art, bottom shade, title logo and status strip, from back to front.
    case backdrop, hero, shade, logo, strip

    /// The fade duration in seconds used for every layer when Reduce Motion is on.
    static let plainFade = 0.2
    /// The duration in seconds of fading the logo and strip out for the picker and back in.
    static let chromeFade = 0.3
    /// The opacity of the black dim laid over the scene while the datacenter picker shows.
    static let pickerDim = 0.25
    /// The duration in seconds of one leg of the backdrop's slow zoom loop.
    static let drift = 24.0
    /// The scale the backdrop reaches at the far end of its zoom loop.
    static let driftScale: CGFloat = 1.06

    /// The animation, including its delay, that brings this layer in from the arriving stage.
    var entrance: Animation {
        switch self {
        case .backdrop:
            .timingCurve(0.2, 0.7, 0.2, 1, duration: 1.6)
        case .hero:
            .easeOut(duration: 1.3).delay(0.35)
        case .shade:
            .easeOut(duration: 1.2)
        case .logo:
            .timingCurve(0.2, 0.7, 0.2, 1, duration: 1.1).delay(0.95)
        case .strip:
            .easeOut(duration: 0.7).delay(0.2)
        }
    }

    /// How long in seconds this layer takes to animate out.
    var exitDuration: Double {
        switch self {
        case .strip, .logo, .shade:
            0.6
        case .hero:
            0.8
        case .backdrop:
            1.1
        }
    }

    /// How long in seconds this layer waits before animating out, so the strip leaves first and the backdrop
    /// last.
    var exitDelay: Double {
        switch self {
        case .strip:
            0
        case .logo:
            0.1
        case .hero:
            0.3
        case .shade:
            0.5
        case .backdrop:
            0.6
        }
    }

    /// The time in seconds from the start of the exit until this layer has fully gone.
    var exitEnd: Double {
        exitDelay + exitDuration
    }

    /// Returns this layer's scale at a stage, which is 1 except where the layer zooms during its entrance or
    /// exit.
    func scale(_ stage: CloudLoadingStage) -> CGFloat {
        switch (self, stage) {
        case (.backdrop, .arriving):
            1.08
        case (.logo, .arriving):
            0.96
        case (.hero, .leaving):
            1.04
        default:
            1
        }
    }

    /// Returns this layer's vertical offset in points at a stage, which slides the logo and strip in and out.
    func offset(_ stage: CloudLoadingStage) -> CGFloat {
        switch (self, stage) {
        case (.logo, .arriving):
            14
        case (.strip, .arriving):
            18
        case (.strip, .leaving):
            16
        case (.logo, .leaving):
            -10
        default:
            0
        }
    }

    /// Returns this layer's blur radius at a stage; only the logo and backdrop blur.
    func blur(_ stage: CloudLoadingStage) -> CGFloat {
        switch (self, stage) {
        case (.logo, .arriving):
            8
        case (.logo, .leaving):
            6
        case (.backdrop, .leaving):
            14
        default:
            0
        }
    }

    /// Whether this layer blurs at any stage, so the other layers skip the blur modifier.
    var blurs: Bool {
        self == .logo || self == .backdrop
    }

    /// Returns whether this layer is hidden and ignores input under a chrome, which holds for the logo and
    /// strip while the picker shows.
    func isWithdrawn(for chrome: CloudLoadingChrome) -> Bool {
        switch self {
        case .logo, .strip:
            chrome == .picker
        case .backdrop, .hero, .shade:
            false
        }
    }
}

private struct CloudLoadingStaging: ViewModifier {
    let layer: CloudLoadingLayer
    let stage: CloudLoadingStage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: CloudLoadingStage {
        reduceMotion
            ? .shown
            : stage
    }

    private var animation: Animation {
        if reduceMotion {
            return .easeOut(duration: CloudLoadingLayer.plainFade)
        }
        return stage == .leaving
            ? .easeInOut(duration: layer.exitDuration).delay(layer.exitDelay)
            : layer.entrance
    }

    func body(content: Content) -> some View {
        sharpened(content)
            .scaleEffect(layer.scale(motion))
            .offset(y: layer.offset(motion))
            .opacity(stage == .shown
                ? 1
                : 0)
                .animation(animation, value: stage)
    }

    @ViewBuilder private func sharpened(_ content: Content) -> some View {
        if layer.blurs {
            content.blur(radius: layer.blur(motion))
        } else {
            content
        }
    }
}

private struct CloudLoadingWithdrawal: ViewModifier {
    let withdrawn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(withdrawn
                ? 0
                : 1)
                .animation(
                    .easeInOut(duration: reduceMotion
                        ? CloudLoadingLayer.plainFade
                        : CloudLoadingLayer.chromeFade),
                    value: withdrawn
                )
                .allowsHitTesting(!withdrawn)
    }
}

extension View {
    /// Stages this view as a cloud loading layer, animating it for the stage and withdrawing it while the
    /// picker chrome is in front.
    /// - Parameters:
    ///   - layer: The layer whose timing and transforms apply.
    ///   - stage: The scene's current stage.
    ///   - chrome: The chrome in front, which decides whether the layer withdraws.
    func cloudLoadingStaged(
        _ layer: CloudLoadingLayer, _ stage: CloudLoadingStage,
        chrome: CloudLoadingChrome = .status
    ) -> some View {
        modifier(CloudLoadingStaging(layer: layer, stage: stage))
            .modifier(CloudLoadingWithdrawal(withdrawn: layer.isWithdrawn(for: chrome)))
    }
}

/// Durations in seconds for the cloud loading screen's transitions.
enum CloudLoadingTiming {
    /// How long the card loading view takes to fade out when the stream takes over.
    static let cardExit = 0.6
    /// How long the cross-fade takes when the screen switches between the card and the layered scene.
    static let swap = 0.6
}

/// The cloud loading screen, showing the layered art scene or the plain card, and dimming it under the
/// datacenter picker when that chrome is in front.
struct CloudLoadingScreen<Picker: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether to show the layered art scene or the plain artwork card.
    let screen: StreamLoading.Screen
    /// Whether the status chrome or the datacenter picker is in front.
    let chrome: CloudLoadingChrome
    /// Whether the screen is fading out as the stream takes over; it ignores input while leaving.
    let leaving: Bool
    /// The game title passed to the layered scene.
    let title: String
    /// The cover art URL used as the card's background.
    let artwork: URL?
    /// The current launch status line.
    let status: String
    /// The index of the current startup step shown by the card's step indicator.
    let activeStep: Int
    /// A timed service wait to show beneath the status, if any.
    var operation: TimedProgress?
    /// Called when the player cancels the launch.
    let cancel: () -> Void
    /// Builds the datacenter picker shown while the picker chrome is in front.
    @ViewBuilder var picker: () -> Picker

    var body: some View {
        ZStack {
            ZStack {
                switch screen {
                case .layered(let layers):
                    CloudLayeredLoadingView(
                        layers: layers, title: title, status: status, operation: operation, leaving: leaving,
                        chrome: chrome, cancel: cancel
                    )
                    .transition(.opacity)
                case .card:
                    card
                        .opacity(leaving
                            ? 0
                            : 1)
                            .animation(
                                .easeInOut(duration: fade(CloudLoadingTiming.cardExit)),
                                value: leaving
                            )
                            .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: fade(CloudLoadingTiming.swap)), value: isLayered)
            Color.black
                .opacity(chrome == .picker
                    ? CloudLoadingLayer.pickerDim
                    : 0)
                    .animation(
                        isLayered
                            ? .easeInOut(duration: fade(CloudLoadingLayer.chromeFade))
                            : nil,
                        value: chrome
                    )
                    .allowsHitTesting(false)
            if chrome == .picker {
                picker()
            }
        }
        .allowsHitTesting(!leaving)
    }

    @ViewBuilder private var card: some View {
        if chrome == .picker {
            StreamLoadingBackdrop(background: .artwork(artwork))
        } else {
            StreamLoadingView(
                background: .artwork(artwork), status: status, activeStep: activeStep,
                stepCount: CloudStartStep.allCases.count, operation: operation, cancel: cancel
            )
        }
    }

    private var isLayered: Bool {
        if case .layered = screen {
            return true
        }
        return false
    }

    private func fade(_ duration: Double) -> Double {
        reduceMotion
            ? CloudLoadingLayer.plainFade
            : duration
    }
}

/// What the cloud loading screen shows beside the title: the start status, or the datacenter picker.
public enum CloudLoadingChrome: Equatable, Sendable {
    /// The start status and progress.
    case status

    /// The datacenter picker.
    case picker
}
