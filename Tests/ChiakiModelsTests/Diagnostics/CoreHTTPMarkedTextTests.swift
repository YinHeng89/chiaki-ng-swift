import ChiakiModels
import Testing

@Suite struct CoreHTTPMarkedTextTests {
    @Test func showsMasksAndDropsAPrefix() {
        let text = CoreHTTPMarkedText("https://h/p?code=ABC&x=1", spans: [
            CoreHTTPSecretSpan(offset: 17, length: 3, kind: .parameter)
        ])
        #expect(text.shown(revealing: { _ in
            false }, mask: { "<\($0.length)>" }) == "https://h/p?code=<3>&x=1")
        #expect(text.shown(revealing: { _ in true }, mask: { _ in "" }) == "https://h/p?code=ABC&x=1")
        let rest = text.dropping(prefix: 9)
        #expect(rest.plain == "/p?code=ABC&x=1")
        #expect(rest.spans == [CoreHTTPSecretSpan(offset: 8, length: 3, kind: .parameter)])
    }

    @Test func unsortedAndOverlappingSpansAreShownWithoutTrapping() {
        let text = CoreHTTPMarkedText("abcdefghij", spans: [
            CoreHTTPSecretSpan(offset: 6, length: 2, kind: .field),
            CoreHTTPSecretSpan(offset: 0, length: 3, kind: .cookie),
            CoreHTTPSecretSpan(offset: 2, length: 2, kind: .body),
            CoreHTTPSecretSpan(offset: 8, length: 99, kind: .session),
            CoreHTTPSecretSpan(offset: 20, length: 1, kind: .body),
            CoreHTTPSecretSpan(offset: 5, length: 0, kind: .body)
        ])
        #expect(text.spans == [
            CoreHTTPSecretSpan(offset: 0, length: 4, kind: .cookie),
            CoreHTTPSecretSpan(offset: 6, length: 4, kind: .field)
        ])
        #expect(text.shown(revealing: { _ in false }, mask: { _ in "*" }) == "*ef*")
        #expect(text.shown(revealing: { _ in true }, mask: { _ in "" }) == "abcdefghij")
        #expect(text.secret(1) == "ghij")
    }

    @Test func aTouchingSpanJoinsTheOneBeforeIt() {
        let text = CoreHTTPMarkedText("abcdef", spans: [
            CoreHTTPSecretSpan(offset: 3, length: 3, kind: .field),
            CoreHTTPSecretSpan(offset: 0, length: 3, kind: .cookie)
        ])
        #expect(text.spans == [CoreHTTPSecretSpan(offset: 0, length: 6, kind: .cookie)])
    }
}
