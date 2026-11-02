import ChiakiClients
import ChiakiClientsLive
import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus
import PlatformUI
import Security
import SwiftUI
import WebKit

extension AccountsClient {
    /// The live accounts client over the account service, which shows the account sign-in page in a web view and
    /// captures the NPSSO it issues.
    ///
    /// - Parameters:
    ///   - service: The service that owns the open database and core.
    ///   - coordinator: The input coordinator whose menu navigator drives the page with a controller.
    /// - Returns: The live client.
    static func native(_ service: AccountService, coordinator: SDLInputCoordinator) -> Self {
        var client = Self.live(service)
        client.captureSignIn = { stages throws(SignInFailure) in
            try await AccountSignInBrowser.run(stages: stages, coordinator: coordinator)
        }
        return client
    }
}

/// Gives the sign-in screen the web view of the page that is shown.
struct AccountSignInPages: SignInPageViews {
    /// The web view showing the page.
    ///
    /// - Parameter page: The page.
    /// - Returns: The web view, or `nil` when the page closed.
    func view(for page: SignInPage) -> PlatformView? {
        AccountSignInBrowser.webView(for: page)
    }
}

/// One web sign-in: shows the page, keeps it on the allowed sign-in hosts, reads the NPSSO when the user is done and
/// drives the page with a controller.
@MainActor final class AccountSignInBrowser: NSObject, WKNavigationDelegate {
    private enum Phase {
        case signingIn, reading, finished
    }
    private var phase: Phase = .signingIn
    private let stages: @Sendable (SignInStage) -> Void
    private let coordinator: SDLInputCoordinator
    private var continuation: CheckedContinuation<NPSSOCredential, Error>?
    private var webView: WKWebView?
    private var page: SignInPage?
    private var window: PlatformWindow? {
        webView?.window
    }
    private var navigator: PlatformMenuNavigator? {
        coordinator.menuNavigator
    }
    private var focusMoveHandlerID: MenuHandlerID?
    private var activationHandlerID: MenuHandlerID?
    private var backHandlerID: MenuHandlerID?
    private var firstFieldFocus: Task<Void, Never>?
    private static var shown: [SignInPage: WKWebView] = [:]
    private static let cookieURL = URL(string: "https://ca.account.sony.com/api/v1/ssocookie")!
    private let allowedHosts: Set<String> = [
        "my.account.sony.com", "ca.account.sony.com", "web.np.playstation.com",
        "io.playstation.com", "www.playstation.com", "account.sony.com",
        "id.sonyentertainmentnetwork.com", "auth.api.sonyentertainmentnetwork.com"
    ]

    /// The web view showing a sign-in page.
    ///
    /// - Parameter page: The page.
    /// - Returns: The web view, or `nil` when the page closed.
    static func webView(for page: SignInPage) -> WKWebView? {
        shown[page]
    }

    private init(stages: @escaping @Sendable (SignInStage) -> Void, coordinator: SDLInputCoordinator) {
        self.stages = stages
        self.coordinator = coordinator
    }

    /// Runs one sign-in until the user finishes or leaves.
    ///
    /// - Parameters:
    ///   - stages: Receives the page when it is shown and the moment the NPSSO is read.
    ///   - coordinator: The input coordinator whose menu navigator drives the page.
    /// - Returns: The captured NPSSO and its expiry.
    /// - Throws: `SignInFailure.cancelled` when the user leaves or the task is cancelled, or why
    ///   the page could not produce an NPSSO.
    static func run(
        stages: @escaping @Sendable (SignInStage) -> Void,
        coordinator: SDLInputCoordinator
    ) async throws(SignInFailure) -> SignInCapture {
        let controller = AccountSignInBrowser(stages: stages, coordinator: coordinator)
        let credential: NPSSOCredential
        do {
            credential = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation {
                    controller.present($0)
                }
            } onCancel: {
                Task { @MainActor in
                    controller.finish(.failure(SignInFailure.cancelled))
                }
            }
        } catch let failure as SignInFailure {
            throw failure
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unreadableResponse
        }
        guard let npsso = NPSSO(credential.value) else {
            throw .unreadableResponse
        }
        return SignInCapture(
            npsso: npsso,
            expiresAt: credential.expiresAt,
            expirySource: NPSSOExpirySource(rawValue: credential.expirySource.rawValue) ?? .unknown
        )
    }
    /// Draws random bytes from the system generator and writes them as lowercase hex.
    /// - Parameter count: How many random bytes to draw; the text is twice as long.
    /// - Returns: The lowercase hex text.
    /// - Throws: `SignInFailure.browserUnavailable` when the system generator fails.
    static func randomHex(_ count: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw SignInFailure.browserUnavailable
        }
        return Hex.encode(bytes)
    }
    private static func signInURL() throws -> URL {
        var central = URLComponents(string: "https://io.playstation.com/central/auth/login")!
        central.queryItems = [
            URLQueryItem(name: "locale", value: "en_GB"),
            URLQueryItem(name: "postSignInURL", value: "https://www.playstation.com/en-gb/"),
            URLQueryItem(name: "cancelURL", value: "https://www.playstation.com/en-gb/")
        ]
        var session = URLComponents(
            string: "https://web.np.playstation.com/api/session/v1/session"
        )!
        session.queryItems = [
            URLQueryItem(name: "redirect_uri", value: central.url!.absoluteString)
        ]
        var signIn = URLComponents(string: "https://my.account.sony.com/sonyacct/signin/")!
        signIn.queryItems = [
            "duid": "0000000700090100" + (try randomHex(32)),
            "response_type": "code", "client_id": "e4a62faf-4b87-4fea-8565-caaabb3ac918",
            "scope": "web:core", "access_type": "offline", "state": try randomHex(32),
            "service_entity": "urn:service-entity:psn", "ui": "pr", "smcid": "web:pdc",
            "redirect_uri": session.url!.absoluteString, "auth_ver": "v3",
            "cid": UUID().uuidString.lowercased()
        ].sorted {
            $0.key < $1.key
        }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        signIn.fragment = "/signin/input/id"
        return signIn.url!
    }
    private func present(_ continuation: CheckedContinuation<NPSSOCredential, Error>) {
        self.continuation = continuation
        do {
            let url = try Self.signInURL()
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let browser = WKWebView(frame: .zero, configuration: configuration)
            browser.navigationDelegate = self
            browser.underPageBackgroundColor = .clear
            webView = browser
            let page = SignInPage(id: UUID())
            self.page = page
            Self.shown = [page: browser]
            stages(.browsing(page))
            registerControllerHandlers()
            browser.load(URLRequest(url: url, timeoutInterval: 60))
        } catch {
            finish(.failure(SignInFailure.browserUnavailable))
        }
    }
    private func readCookie() {
        guard phase == .signingIn, let browser = webView else {
            return
        }
        phase = .reading
        stages(.completing)
        browser.load(URLRequest(url: Self.cookieURL, timeoutInterval: 30))
    }
    /// Allows only HTTPS navigation without credentials, lets subframes load freely, and fails the
    /// sign-in when the main frame leaves the allowed sign-in hosts.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, url.scheme == "https", url.user == nil,
              url.password == nil
        else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host),
              url.port == nil || url.port == 443
        else {
            decisionHandler(.cancel)
            finish(.failure(SignInFailure.navigationFailed))
            return
        }
        decisionHandler(.allow)
    }
    /// Moves the sign-in on as pages finish: reaching the PlayStation site starts reading the cookie,
    /// Sign-in pages get their first field focused, and the cookie page's NPSSO finishes the session.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard phase != .finished, let url = webView.url else {
            return
        }
        if phase == .signingIn, url.host == "www.playstation.com" {
            readCookie()
            return
        }
        if phase == .signingIn {
            reportCertificate(of: webView, at: url)
            focusFirstField(after: [.milliseconds(300), .seconds(1), .seconds(2)])
        }
        guard phase == .reading else {
            return
        }
        guard url == Self.cookieURL else {
            finish(.failure(SignInFailure.unreadableResponse))
            return
        }

        webView.evaluateJavaScript("document.body.innerText") { [weak self] value, error in
            guard let self, self.phase == .reading, self.webView?.url == Self.cookieURL else {
                return
            }
            guard error == nil, let text = value as? String, let data = text.data(using: .utf8),
                  let credential = try? NPSSOCredential.decodeTokenResponse(data, receivedAt: Date())
            else {
                self.finish(.failure(SignInFailure.unreadableResponse))
                return
            }
            guard credential.expiresAt == nil,
                  let cookies = self.webView?.configuration.websiteDataStore.httpCookieStore
            else {
                self.finish(.success(credential))
                return
            }
            cookies.getAllCookies { [weak self] held in
                self?.finish(.success(credential.adoptingCookieExpiry(from: held, now: Date())))
            }
        }
    }
    /// Fails the sign-in when a navigation fails for any reason other than being cancelled.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            finish(.failure(SignInFailure.navigationFailed))
        }
    }
    /// Fails the sign-in when a page cannot start loading for any reason other than being cancelled.
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if (error as NSError).code != NSURLErrorCancelled {
            finish(.failure(SignInFailure.navigationFailed))
        }
    }
    private func reportCertificate(of webView: WKWebView, at url: URL) {
        guard let page, let trust = webView.serverTrust, let host = url.host?.lowercased(),
              let certificate = SignInCertificateReader.certificate(of: trust, host: host)
        else {
            return
        }
        stages(.secured(page, certificate))
    }
    private func finish(_ result: Result<NPSSOCredential, Error>) {
        guard phase != .finished else {
            return
        }
        phase = .finished
        firstFieldFocus?.cancel()
        firstFieldFocus = nil
        unregisterControllerHandlers()
        dismissAttachedSheet()
        let callback = continuation
        continuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        Self.shown = Self.shown.filter { _, shown in
            shown !== webView
        }
        webView = nil
        callback?.resume(with: result)
    }
}

extension AccountSignInBrowser {
    private func registerControllerHandlers() {
        focusMoveHandlerID = navigator?.handlers.registerFocusMove { [weak self] window, direction in
            guard let self, self.acceptsControllerInput(in: window) else {
                return false
            }
            let offset = direction == .up || direction == .left
                ? -1
                : 1
            self.moveWebFocus(by: offset)
            return true
        }
        activationHandlerID = navigator?.handlers.registerModalActivation { [weak self] window in
            guard let self, self.acceptsControllerInput(in: window) else {
                return false
            }
            self.activateWebFocus()
            return true
        }
        backHandlerID = navigator?.handlers.registerBack { [weak self] window in
            guard let self, self.acceptsControllerInput(in: window) else {
                return false
            }
            self.finish(.failure(SignInFailure.cancelled))
            return true
        }
    }

    private func unregisterControllerHandlers() {
        if let focusMoveHandlerID {
            navigator?.handlers.unregister(focusMoveHandlerID)
        }
        if let activationHandlerID {
            navigator?.handlers.unregister(activationHandlerID)
        }
        if let backHandlerID {
            navigator?.handlers.unregister(backHandlerID)
        }
        focusMoveHandlerID = nil
        activationHandlerID = nil
        backHandlerID = nil
    }

    private func acceptsControllerInput(in window: PlatformWindow) -> Bool {
        phase == .signingIn && window === self.window && !hasAttachedSheet(window) && webView != nil
    }

    private func hasAttachedSheet(_ window: PlatformWindow) -> Bool {
        #if os(macOS)
            window.attachedSheet != nil
        #else
            window.rootViewController?.presentedViewController != nil
        #endif
    }

    private func dismissAttachedSheet() {
        #if os(macOS)
            if let sheet = window?.attachedSheet {
                window?.endSheet(sheet)
            }
        #else
            window?.rootViewController?.presentedViewController?.dismiss(animated: true)
        #endif
    }

    private func makeFirstResponder(_ browser: WKWebView) {
        #if os(macOS)
            window?.makeFirstResponder(browser)
        #else
            browser.becomeFirstResponder()
        #endif
    }

    private func focusFirstField(after delays: [Duration]) {
        guard let browser = webView else {
            return
        }
        firstFieldFocus?.cancel()
        firstFieldFocus = Task { @MainActor [weak self] in
            for delay in delays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.phase == .signingIn, self.webView === browser else {
                    return
                }
                if let window = self.window, window.isKeyWindow, !self.hasAttachedSheet(window) {
                    self.makeFirstResponder(browser)
                }
                browser.callAsyncJavaScript(
                    SignInPageScripts.initialFocus,
                    arguments: ["selector": SignInPageScripts.focusableSelector],
                    in: nil,
                    in: .defaultClient,
                    completionHandler: nil
                )
            }
        }
    }

    private func moveWebFocus(by offset: Int) {
        guard let browser = webView else {
            return
        }
        makeFirstResponder(browser)
        browser.callAsyncJavaScript(
            SignInPageScripts.moveFocus,
            arguments: ["selector": SignInPageScripts.focusableSelector, "offset": offset],
            in: nil,
            in: .defaultClient,
            completionHandler: nil
        )
    }

    private func activateWebFocus() {
        guard let browser = webView else {
            return
        }
        browser.callAsyncJavaScript(
            SignInPageScripts.activate,
            arguments: [:],
            in: nil,
            in: .defaultClient
        ) { [weak self] result in
            guard let self, self.phase == .signingIn, self.webView === browser,
                  let window = self.window, !self.hasAttachedSheet(window),
                  case .success(let value) = result,
                  let details = value as? [String: Any],
                  let kind = details["kind"] as? String else {
                return
            }
            switch kind {
            case "text":
                self.presentKeyboard(for: details, in: window, browser: browser)
            case "none":
                self.moveWebFocus(by: 1)
            default:
                break
            }
        }
    }

    private func presentKeyboard(for details: [String: Any], in window: PlatformWindow, browser: WKWebView) {
        let label = String((details["label"] as? String ?? "Text").prefix(60))
        let title = label.isEmpty
            ? "Text"
            : label
        ControllerKeyboardSheet.present(
            in: window,
            navigator: navigator,
            glyphs: ControllerGlyphs.promptGlyphs(
                family: coordinator.navigationFamily,
                layout: coordinator.navigationButtonLayout,
                connected: coordinator.navigationConnected
            ),
            request: ControllerKeyboardSheet.Request(
                title: title,
                text: details["value"] as? String ?? "",
                secure: details["secure"] as? Bool ?? false
            ),
            update: { [weak self] value in
                guard let self, self.phase == .signingIn, self.webView === browser else {
                    return
                }
                browser.callAsyncJavaScript(
                    SignInPageScripts.setText,
                    arguments: ["value": value],
                    in: nil,
                    in: .defaultClient,
                    completionHandler: nil
                )
            },
            dismissed: { [weak self] advance in
                guard let self, self.phase == .signingIn, self.webView === browser else {
                    return
                }
                self.makeFirstResponder(browser)
                if advance {
                    self.moveWebFocus(by: 1)
                }
            }
        )
    }
}

/// JavaScript run in the sign-in page so a controller can move between fields, press buttons
/// and type through the controller keyboard.
enum SignInPageScripts {
    /// The CSS selector for elements that controller focus can land on.
    static let focusableSelector = [
        "input:not([type=hidden]):not([disabled])", "button:not([disabled])", "a[href]",
        "select:not([disabled])", "textarea:not([disabled])", "[tabindex]:not([tabindex='-1'])"
    ].joined(separator: ", ")
    private static let elementHelpers = """
    const visible = (element) => {
        const bounds = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return bounds.width > 0 && bounds.height > 0 && style.visibility !== 'hidden'
            && style.display !== 'none' && style.opacity !== '0';
    };
    const textual = (element) => {
        const types = ['', 'text', 'email', 'password', 'search', 'tel', 'url', 'number'];
        const type = (element.getAttribute('type') || '').toLowerCase();
        return (element.tagName === 'INPUT' && types.includes(type))
            || element.tagName === 'TEXTAREA' || element.isContentEditable;
    };
    const items = Array.from(document.querySelectorAll(selector)).filter(visible);
    """
    /// Focuses the first visible text field, or failing that an action button, and keeps doing so when the page
    /// replaces its controls. Focus already on a listed element or inside a frame is kept, and so is focus left
    /// on the page background while the element that last had focus is still shown; returns whether it moved
    /// focus.
    static let initialFocus = """
    const focus = () => {
    """ + elementHelpers + """
        const active = document.activeElement;
        if (active && active !== document.body) {
            if (items.includes(active) || active.tagName === 'IFRAME') {
                return false;
            }
        } else {
            const last = window.__chiakiLastFocus;
            if (last && last.isConnected && visible(last)) {
                return false;
            }
        }
        const field = items.find(textual);
        const action = items.find((element) => element.tagName === 'BUTTON'
            && !/close|back|cancel/i.test(element.getAttribute('aria-label') || element.innerText || ''));
        const target = field || action || items[0];
        if (!target) {
            return false;
        }
        target.focus();
        target.scrollIntoView({ block: 'nearest' });
        return true;
    };
    if (!window.__chiakiFocusObserver) {
        document.addEventListener('focusin', (event) => {
            window.__chiakiLastFocus = event.target;
        }, true);
        let scheduled = false;
        const observer = new MutationObserver(() => {
            if (scheduled) {
                return;
            }
            scheduled = true;
            requestAnimationFrame(() => {
                scheduled = false;
                if (document.hasFocus()) {
                    focus();
                }
            });
        });
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['class', 'style', 'hidden', 'disabled', 'aria-hidden']
        });
        window.__chiakiFocusObserver = observer;
    }
    return focus();
    """
    /// Moves focus by `offset` through the visible focusable elements, starting from the first text
    /// field when nothing has focus.
    static let moveFocus = elementHelpers + """
    if (items.length === 0) {
        return false;
    }
    const current = items.indexOf(document.activeElement);
    const firstField = items.findIndex(textual);
    const next = current < 0
        ? Math.max(0, firstField)
        : Math.max(0, Math.min(items.length - 1, current + offset));
    items[next].focus();
    items[next].scrollIntoView({ block: 'nearest' });
    return true;
    """
    /// Clicks the focused element, or for a text field marks it and returns its label, value and
    /// whether it is a password so the controller keyboard can edit it.
    static let activate = """
    const element = document.activeElement;
    if (!element || element === document.body) {
        return { kind: 'none' };
    }
    const textTypes = ['', 'text', 'email', 'password', 'search', 'tel', 'url', 'number'];
    const type = (element.getAttribute('type') || '').toLowerCase();
    const textual = (element.tagName === 'INPUT' && textTypes.includes(type))
        || element.tagName === 'TEXTAREA' || element.isContentEditable;
    if (!textual) {
        element.click();
        return { kind: 'activated' };
    }
    document.querySelectorAll('[data-chiaki-keyboard]').forEach((item) => {
        item.removeAttribute('data-chiaki-keyboard');
    });
    element.setAttribute('data-chiaki-keyboard', '');
    const firstLabel = (element.labels && element.labels[0] && element.labels[0].innerText) || '';
    const label = element.getAttribute('aria-label') || element.getAttribute('placeholder')
        || firstLabel || 'Text';
    const value = element.isContentEditable
        ? element.textContent
        : element.value;
    return { kind: 'text', secure: type === 'password', label: label, value: value || '' };
    """
    /// Writes `value` into the field marked by `activate` and fires its input and change events.
    static let setText = """
    const element = document.querySelector('[data-chiaki-keyboard]');
    if (!element) {
        return false;
    }
    element.focus();
    if (element.isContentEditable) {
        element.textContent = value;
    } else {
        const prototype = element.tagName === 'TEXTAREA'
            ? HTMLTextAreaElement.prototype
            : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(prototype, 'value').set.call(element, value);
    }
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
    """
}
