import Foundation
import Testing
import WebKit
@testable import ChiakiNG

@MainActor
private final class ScriptPage {
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))

    func load() async {
        view.loadHTMLString("""
        <html><body>
        <input id="email" type="email">
        <button id="next">Next</button>
        <iframe id="challenge" srcdoc="<input id='code'>"></iframe>
        </body></html>
        """, baseURL: nil)
        for _ in 0..<100 where view.isLoading {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? await Task.sleep(for: .milliseconds(100))
    }

    func run(_ script: String) async -> Any? {
        try? await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
    }

    func initialFocus() async -> Bool {
        let result = try? await view.callAsyncJavaScript(
            SignInPageScripts.initialFocus,
            arguments: ["selector": SignInPageScripts.focusableSelector],
            in: nil,
            contentWorld: .defaultClient
        )
        return result as? Bool ?? false
    }

    var active: String {
        get async {
            let element = await run("return document.activeElement.id || document.activeElement.tagName")
            return element as? String ?? ""
        }
    }
}

@MainActor @Test func signInPageFocusLeavesAFrameAndTheBackgroundAlone() async {
    let page = ScriptPage()
    await page.load()
    #expect(await page.initialFocus())
    #expect(await page.active == "email")

    _ = await page.run("document.getElementById('challenge').focus(); return true")
    #expect(await page.active == "challenge")
    #expect(await !page.initialFocus())
    #expect(await page.active == "challenge")

    _ = await page.run("document.getElementById('email').focus(); document.activeElement.blur(); return true")
    #expect(await page.active == "BODY")
    #expect(await !page.initialFocus())
    #expect(await page.active == "BODY")
}

@MainActor @Test func signInPageFocusReturnsWhenThePageRemovesTheFocusedField() async {
    let page = ScriptPage()
    await page.load()
    #expect(await page.initialFocus())
    _ = await page.run("document.getElementById('email').remove(); return true")
    #expect(await page.initialFocus())
    #expect(await page.active == "next")
}
