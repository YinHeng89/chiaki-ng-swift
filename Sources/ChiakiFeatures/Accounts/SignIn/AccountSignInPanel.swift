import ChiakiClients
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The modal panel that shows the account sign-in page while ``SignInFeature`` browses or reads the NPSSO.
///
/// On a compact screen the panel fills the screen apart from a small margin and its header is tighter.
public struct AccountSignInPanel: View {
    /// The sign-in feature that supplies the page to show and receives the cancel request.
    let store: StoreOf<SignInFeature>
    /// The window's size, which bounds the panel's width and height.
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout
    @Environment(\.menuNavigator) private var navigator
    @State private var certificateShown = false

    /// Creates the panel.
    ///
    /// - Parameters:
    ///   - store: The sign-in feature.
    ///   - size: The window's size, which bounds the panel.
    public init(store: StoreOf<SignInFeature>, size: CGSize) {
        self.store = store
        self.size = size
    }

    /// The panel.
    public var body: some View {
        ZStack {
            if let page = store.page {
                Dimming.standard.color
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                Group {
                    if touchScreen {
                        touchPanel(page, completing: store.isCompleting)
                    } else {
                        panel(page, completing: store.isCompleting)
                    }
                }
                .transition(AppMotion.transition(reduced: reduceMotion))
            }
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: store.phase)
        .animation(AppMotion.animation(reduced: reduceMotion), value: store.certificate)
    }

    private var touchScreen: Bool {
        #if os(iOS)
            layout.touch && navigator?.inputMode.mode != .controller
        #else
            false
        #endif
    }

    private func touchPanel(_ page: SignInPage, completing: Bool) -> some View {
        VStack(spacing: 0) {
            touchHeader
            ZStack {
                SignInWebView(page: page)
                    .opacity(
                        completing
                            ? 0
                            : 1
                    )
                if completing {
                    completingProgress
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .padding([.horizontal, .bottom], 8)
        }
        .glassPanel(.modal)
        .padding(.horizontal, sideMargin)
        .padding(.vertical, 8)
    }

    private var touchHeader: some View {
        HStack(spacing: 12) {
            Button {
                store.send(.view(.closePage))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(.accountsPanelCancel)
            VStack(alignment: .leading, spacing: 1) {
                Text(.accountsPanelTitle).font(.headline)
                Text(.accountsPanelPasskeyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let certificate = store.certificate {
                Button {
                    certificateShown = true
                } label: {
                    Label(certificate.host, systemImage: "lock.fill")
                        .font(.callout.monospaced().weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.glass)
                .accessibilityHint(.accountsPanelCertificateHint)
                .popover(isPresented: $certificateShown) {
                    ScrollView {
                        SignInCertificateBar(certificate: certificate)
                            .padding(12)
                    }
                    .frame(idealWidth: 460, maxHeight: 320)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func panel(_ page: SignInPage, completing: Bool) -> some View {
        VStack(spacing: 0) {
            header
            if let certificate = store.certificate {
                SignInCertificateBar(certificate: certificate)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            ZStack {
                SignInWebView(page: page)
                    .opacity(
                        completing
                            ? 0
                            : 1
                    )
                if completing {
                    completingProgress
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .padding([.horizontal, .bottom], 12)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .glassPanel(.modal)
        .shadow(color: .black.opacity(0.24), radius: 30, y: 14)
        .frame(
            maxHeight: .infinity,
            alignment: layout.sheetsFillWidth
                ? .bottom
                : .center
        )
        .padding(
            .bottom,
            layout.sheetsFillWidth
                ? Self.fillMargin
                : 0
        )
    }

    /// The margin a panel that fills the window keeps from its sides and bottom.
    static let fillMargin: CGFloat = 16

    private var sideMargin: CGFloat {
        max(Self.fillMargin, layout.sideInset)
    }

    private var panelSize: CGSize {
        if layout.sheetsFillWidth {
            return CGSize(
                width: max(0, size.width - 2 * sideMargin),
                height: max(
                    0,
                    size.height - layout.topChromeInset - layout.controlSize - layout.controlSpacing - Self
                        .fillMargin
                )
            )
        }
        return CGSize(
            width: min(660, max(420, size.width - 80)),
            height: min(780, max(480, size.height - 120))
        )
    }

    private var completingProgress: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(.accountsPanelCompleting)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(.accountsPanelTitle).font(.headline)
                Text(.accountsPanelPasskeyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(
                        layout.isCompact
                            ? 2
                            : nil
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            FocusButton {
                store.send(.view(.closePage))
            } label: {
                Image(systemName: "xmark").frame(width: 24, height: 24)
            }
            .glassControlStyle()
            .focusBorderShape(.circle)
            .keyboardShortcut(.cancelAction)
            .help(Text(.accountsPanelCancel))
            .accessibilityLabel(.accountsPanelCancel)
        }
        .padding(.horizontal, 20)
        .padding(
            .vertical,
            layout.isCompact
                ? 8
                : 14
        )
    }
}

/// Supplies the view that shows a web sign-in page, which the app owns.
@MainActor
public protocol SignInPageViews {
    /// The view showing a page.
    ///
    /// - Parameter page: The page.
    /// - Returns: The view, or `nil` when the page is no longer shown.
    func view(for page: SignInPage) -> PlatformView?
}

extension EnvironmentValues {
    /// The views of the web sign-in pages, which the app supplies at its root.
    @Entry public var signInPageViews: (any SignInPageViews)?
}

#if os(macOS)
    /// Hosts the view the app shows a `SignInPage` in.
    struct SignInWebView: NSViewRepresentable {
        /// The sign-in page whose view is embedded.
        let page: SignInPage

        /// Returns the app's own view of the page rather than creating a new one.
        func makeNSView(context: Context) -> NSView {
            context.environment.signInPageViews?.view(for: page) ?? NSView()
        }

        /// Does nothing, because the page drives its web view directly.
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
#else
    /// Hosts the view the app shows a `SignInPage` in.
    struct SignInWebView: UIViewRepresentable {
        /// The sign-in page whose view is embedded.
        let page: SignInPage

        /// Returns the app's own view of the page rather than creating a new one.
        func makeUIView(context: Context) -> UIView {
            context.environment.signInPageViews?.view(for: page) ?? UIView()
        }

        /// Does nothing, because the page drives its web view directly.
        func updateUIView(_ uiView: UIView, context: Context) {}
    }
#endif
