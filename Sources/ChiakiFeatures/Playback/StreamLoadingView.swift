import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus
import ChiakiClients
import ChiakiModels
import ComposableArchitecture

/// What fills the screen behind the stream loading panel.
enum StreamLoadingBackground {
    /// The quiet ambient app background.
    case ambient
    /// Cloud hero artwork from the URL, darkened by a gradient.
    case artwork(URL?)
}

/// The full screen view shown while a stream starts, with the logo, a step progress bar, a status line,
/// optional timed progress and a focused Cancel button.
struct StreamLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout
    @MenuFocusState private var cancelFocused: Bool
    @Environment(\.menuNavigator) private var navigator
    @State private var hostWindow: PlatformWindow?
    /// The backdrop behind the panel.
    var background = StreamLoadingBackground.ambient
    /// The current startup status, animated as it changes.
    let status: String
    /// The zero based index of the startup step in progress.
    let activeStep: Int
    /// The number of startup steps drawn in the progress bar.
    let stepCount: Int
    /// A timed operation shown with its own progress under the status when present.
    var operation: TimedProgress?
    /// Runs when Cancel is pressed.
    let cancel: () -> Void

    private let lime = Palette.accent

    var body: some View {
        ZStack {
            StreamLoadingBackdrop(background: background)
            VStack(spacing: 0) {
                ChiakiLogo(
                    size: layout.isCompact
                        ? 52
                        : 112,
                    isConnecting: true
                )
                .padding(
                    .bottom,
                    layout.isCompact
                        ? 12
                        : 30
                )
                Text("Starting your stream")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.7)
                    .foregroundStyle(.white)
                progress
                    .padding(.top, 24)
                Text(status)
                    .id(status)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 15)
                    .transition(statusTransition)
                if let operation {
                    OperationProgressView(progress: operation)
                        .foregroundStyle(.white)
                        .padding(.top, 12)
                }
                FocusButton(action: cancel) {
                    Text("Cancel")
                        .padding(.horizontal, 16)
                        .frame(minHeight: layout.controlSize)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .focusHighlightShape(.capsule)
                .foregroundStyle(.white.opacity(0.78))
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
                .padding(
                    .top,
                    layout.isCompact
                        ? 16
                        : 32
                )
            }
            .modifier(StreamLoadingPanel(fillsScreen: layout.isCompact))
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: status)
        .accessibilityElement(children: .contain)
        .background(WindowAccessor { hostWindow = $0 })
        .task {
            await Task.yield()
            cancelFocused = true
            navigator?.ensureFocus(
                in: { hostWindow },
                reset: {},
                apply: {
                    cancelFocused = true
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLibraryContent)) { notification in
            guard let window = notification.object as? PlatformWindow,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            cancelFocused = true
        }
    }

    private var progress: some View {
        HStack(spacing: 9) {
            ForEach(0..<stepCount, id: \.self) { step in
                Capsule()
                    .fill(progressColour(step))
                    .frame(width: progressWidth(step), height: 6)
                    .shadow(color: progressGlow(step), radius: 7)
                    .animation(AppMotion.animation(reduced: reduceMotion), value: activeStep)
            }
        }
        .accessibilityHidden(true)
    }

    private var statusTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.98))
    }

    private func progressColour(_ step: Int) -> Color {
        if step < activeStep {
            return lime
        }
        if step == activeStep {
            return .accentColor
        }
        return .secondary.opacity(0.28)
    }

    private func progressWidth(_ step: Int) -> CGFloat {
        if step == activeStep {
            return 34
        }
        return 26
    }

    private func progressGlow(_ step: Int) -> Color {
        if step == activeStep {
            return .accentColor.opacity(0.75)
        }
        return .clear
    }
}

/// Draws a ``StreamLoadingBackground`` behind stream loading content.
struct StreamLoadingBackdrop: View {
    /// The backdrop to draw.
    let background: StreamLoadingBackground

    var body: some View {
        ZStack {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch background {
        case .ambient:
            AmbientBackground(quiet: true)
            Color.black.opacity(0.12)
        case .artwork(let url):
            CloudHeroArtworkView(url: url)
            LinearGradient(
                colors: [
                    .black.opacity(0.30),
                    .black.opacity(0.52),
                    .black.opacity(0.36)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct StreamLoadingPanel: ViewModifier {
    let fillsScreen: Bool

    func body(content: Content) -> some View {
        if fillsScreen {
            content
                .padding(.horizontal, 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.42))
        } else {
            content
                .padding(.horizontal, 56)
                .padding(.vertical, 42)
                .glassPanel(.modal)
                .overlay {
                    RoundedRectangle(cornerRadius: GlassPanel.Radius.modal.points)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.30), radius: 28, y: 12)
        }
    }
}

/// A full-size cloud hero drawn over black, showing a held decode at once when there is one.
private struct CloudHeroArtworkView: View {
    /// The hero's address.
    public let url: URL?
    @Environment(\.catalog) private var catalog
    @State private var image: CGImage?

    /// Creates a hero.
    ///
    /// - Parameter url: The hero's address, or `nil` for black.
    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        Color.black
            .overlay {
                if let image = image ?? url.flatMap({ catalog.heldHero($0) }) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else {
                    image = nil
                    return
                }
                if let cached = catalog.heldHero(url) {
                    image = cached
                    return
                }
                image = nil
                let hero = try? await catalog.hero(url)
                guard !Task.isCancelled else {
                    return
                }
                image = hero
            }
    }
}
