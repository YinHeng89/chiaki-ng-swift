import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Foundation
import Testing

@Suite struct HTTPCallsBridgeTests {
    private static func view(_ text: String, spans: [chiaki_bridge.SecretSpanFacts]) -> (
        [UInt8],
        chiaki_bridge.SecretSpans
    ) {
        var list = chiaki_bridge.SecretSpans()
        for span in spans {
            list.push_back(span)
        }
        return (Array(text.utf8), list)
    }

    @Test func anExchangeMapsEveryBridgeField() {
        let url = "https://m.np.playstation.com/api/one?code=SECRET1"
        let (bytes, spans) = Self.view(
            url,
            spans: [chiaki_bridge.SecretSpanFacts(offset: 42, length: 7, kind: .parameter)]
        )
        let exchange = bytes.withUnsafeBufferPointer { held in
            var call = chiaki_bridge.HttpCallView()
            call.sequence = 7
            call.area = .catalog
            call.credentials.push_back(.account_token)
            call.credentials.push_back(.store_session)
            call.credential_label = std.string("commerce bearer")
            call.label = std.string("test.label")
            call.attempt = 3
            call.method = std.string("POST")
            call.started_at_ms = 1_700_000_000_000
            call.duration_us = 2500
            call.base = std.string("https://m.np.playstation.com")
            call.url = chiaki_bridge.MarkedTextView(text: held.baseAddress, size: held.count, spans: spans)
            call.status = .init(404)
            call.reason = std.string("Not Found")
            call.failed = true
            call.bytes_sent = 3
            call.bytes_received = 9
            return HTTPCallsBridge.exchange(of: call)
        }
        #expect(exchange.id == 7)
        #expect(exchange.area == .catalog)
        #expect(exchange.credentials == [.accountToken, .storeSession])
        #expect(exchange.credentialLabel == "commerce bearer")
        #expect(exchange.label == "test.label")
        #expect(exchange.attempt == 3)
        #expect(exchange.method == "POST")
        #expect(exchange.startedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(exchange.duration == .microseconds(2500))
        #expect(exchange.base == "https://m.np.playstation.com")
        #expect(exchange.url.plain == url)
        #expect(exchange.url.spans == [CoreHTTPSecretSpan(offset: 42, length: 7, kind: .parameter)])
        #expect(exchange.url.secret(0) == "SECRET1")
        #expect(exchange.status == 404 && exchange.reason == "Not Found")
        #expect(exchange.transportError == nil && exchange.failed)
        #expect(exchange.bytesSent == 3 && exchange.bytesReceived == 9)
    }

    @Test func aTransportFailureCarriesItsErrorAndClippedSpans() {
        let (bytes, spans) = Self.view("abcdef", spans: [
            chiaki_bridge.SecretSpanFacts(offset: 0, length: 3, kind: .cookie),
            chiaki_bridge.SecretSpanFacts(offset: 4, length: 99, kind: .field)
        ])
        let exchange = bytes.withUnsafeBufferPointer { held in
            var call = chiaki_bridge.HttpCallView()
            call.area = .other
            call.url = chiaki_bridge.MarkedTextView(text: held.baseAddress, size: held.count, spans: spans)
            call.transport_error = .init(libchiaking.platform.HttpError.timed_out)
            call.failed = true
            return HTTPCallsBridge.exchange(of: call)
        }
        #expect(exchange.area == .other)
        #expect(exchange.credentials.isEmpty)
        #expect(exchange.status == nil)
        #expect(exchange.transportError == .timedOut)
        #expect(exchange.url.spans == [
            CoreHTTPSecretSpan(offset: 0, length: 3, kind: .cookie),
            CoreHTTPSecretSpan(offset: 4, length: 2, kind: .field)
        ])
        #expect(HTTPCallsBridge.marked(of: chiaki_bridge.MarkedTextView()).isEmpty)
    }

    @Test func totalsCarryEveryCredentialAndBase() {
        var facts = chiaki_bridge.HttpTotalsFacts()
        facts.revision = 9
        facts.all = chiaki_bridge.HttpTallyFacts(
            requests: 10,
            http_errors: 1,
            transport_errors: 2,
            bytes_sent: 3,
            bytes_received: 4
        )
        facts.anonymous.requests = 6
        var gkSession = chiaki_bridge.HttpCredentialTallyFacts()
        gkSession.credential = .gk_session
        gkSession.tally.requests = 4
        facts.credentials.push_back(gkSession)
        var base = chiaki_bridge.HttpBaseTallyFacts()
        base.base = std.string("https://cc.prod.gaikai.com")
        base.tally = chiaki_bridge.HttpTallyFacts(
            requests: 4,
            http_errors: 1,
            transport_errors: 2,
            bytes_sent: 5,
            bytes_received: 6
        )
        facts.bases.push_back(base)
        let totals = HTTPCallsBridge.totals(of: facts)
        #expect(totals.all == CoreHTTPTally(
            requests: 10,
            httpErrors: 1,
            transportErrors: 2,
            bytesSent: 3,
            bytesReceived: 4
        ))
        #expect(totals.anonymous.requests == 6)
        #expect(totals.credentials.count == CoreHTTPCredential.allCases.count)
        #expect(totals.credentials[.gkSession]?.requests == 4)
        #expect(totals.credentials[.accountToken]?.requests == 0)
        #expect(totals.bases == ["https://cc.prod.gaikai.com": CoreHTTPTally(
            requests: 4,
            httpErrors: 1,
            transportErrors: 2,
            bytesSent: 5,
            bytesReceived: 6
        )])
    }
}
