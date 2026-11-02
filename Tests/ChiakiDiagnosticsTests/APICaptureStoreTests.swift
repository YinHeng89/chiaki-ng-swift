import Foundation
import Testing
import ChiakiModels
@testable import ChiakiDiagnostics

@Test func apiCaptureIsOptInAndRedactsBeforeWriting() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = APICaptureStore()
    var settings = LogSettings(directory: directory.path, level: .off)
    await capture.configure(settings)
    let request = captureRequest()
    #expect(await capture.begin(request) == nil)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    settings.captureAPI = true
    await capture.configure(settings)
    let id = try #require(await capture.begin(request))
    await capture.finish(
        id, status: 403, headers: ["Set-Cookie": "SECRET_COOKIE"],
        body: Data(#"{"status":403,"error":"SECRET_ERROR"}"#.utf8), errorCode: nil, durationUS: 123
    )
    let folder = directory.appendingPathComponent("API Captures")
    let file = folder.appendingPathComponent("api-capture.jsonl")
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(!text.contains("SECRET"))
    #expect(!text.contains("987654321"))
    #expect(!text.contains(request.httpBody!.base64EncodedString()))
    let records = try text.split(separator: "\n").map {
        try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
    }
    #expect(records.count == 2)
    #expect(records[0]["call"] as? String == id.uuidString)
    #expect(records[1]["call"] as? String == id.uuidString)
    #expect(records[1]["status"] as? Int == 403)
    let body = try #require(records[0]["body"] as? [String: Any])
    #expect(body["state"] as? String == "ready")
    #expect(body["count"] as? Int == 2)
    #expect(body["access_token"] as? String == "[redacted]")
    #expect(try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int == 0o700)
    #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
    settings.captureAPI = false
    await capture.configure(settings)
    await capture.finish(id, status: nil, errorCode: -999, durationUS: 456)
    #expect(try String(contentsOf: file, encoding: .utf8) == text)
}

@Test func apiCaptureRetainsCoreFailuresAndReportsOmissions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var settings = LogSettings(directory: directory.path)
    settings.captureAPI = true
    let capture = APICaptureStore()
    await capture.configure(settings)
    await capture
        .recordCore(
            Data(#"""
                {"schema":1,
                "source":"core",
                "attempt":9,
                "call":2,
                "phase":"response",
                "transport_error":1,
                "duration_us":345}
                """#
                .utf8)
        )
    await capture
        .recordCore(
            Data(#"""
                {"schema":1,
                "source":"core",
                "attempt":9,
                "call":3,
                "phase":"response",
                "status":200,
                "body_bytes":3,
                "body_base64":"AP8B"}
                """#
                .utf8)
        )
    await capture.recordCore(Data(#"{"schema":1,"source":"core","phase":"capture_loss","dropped":8}"#.utf8))
    await capture.recordCore(Data("malformed".utf8))
    let text = try String(
        contentsOf: directory.appendingPathComponent("API Captures/api-capture.jsonl"),
        encoding: .utf8
    )
    #expect(text.contains("\"transport_error\":1"))
    #expect(text.contains("\"duration_us\":345"))
    #expect(text.contains("\"attempt\":9"))
    #expect(text.contains("non-JSON body redacted"))
    #expect(text.contains("\"dropped\":8"))
    #expect(text.contains("\"dropped\":1"))
    #expect(!text.contains("AP8B"))
    #expect(await !capture.writeFailed)
}

@Test func apiCaptureRotatesAndSurfacesWriteFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var settings = LogSettings(directory: directory.path)
    settings.captureAPI = true
    let capture = APICaptureStore(maximumBytes: 1)
    await capture.configure(settings)
    for _ in 0..<8 {
        await capture
            .recordCore(Data(#"{"schema":1,"source":"core","phase":"capture_loss","dropped":1}"#.utf8))
    }
    let entries = try FileManager.default
        .contentsOfDirectory(atPath: directory.appendingPathComponent("API Captures").path)
    #expect(entries.sorted() == [
        "api-capture.1.jsonl",
        "api-capture.2.jsonl",
        "api-capture.3.jsonl",
        "api-capture.jsonl"
    ])
    settings.directory = directory.appendingPathComponent("not-a-directory").path
    try Data().write(to: URL(fileURLWithPath: settings.directory))
    await capture.configure(settings)
    await capture.recordCore(Data(#"{"phase":"capture_loss","dropped":1}"#.utf8))
    #expect(await capture.writeFailed)
}

@Test func apiCaptureSettingsDecodeOldInstallAndRoundTrip() throws {
    let old = try JSONDecoder().decode(
        LogSettings.self,
        from: Data(#"{"directory":"/tmp/example","level":"info"}"#.utf8)
    )
    #expect(!old.captureAPI)
    var enabled = old
    enabled.captureAPI = true
    #expect(try JSONDecoder().decode(LogSettings.self, from: JSONEncoder().encode(enabled)) == enabled)
}

@Test func apiCaptureRedactsDynamicKeysAndPrivateHosts() throws {
    let body = Data(#"""
        {"123456789":{"status":200},
        "ABCD1234EFGH5678":{"state":"ready"},
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":"value",
        "email@example.com":true}
        """#
        .utf8)
    let safe = APICaptureRedactor.redact([
        "url": "https://PRIVATE_SESSION.playstation.com/api?token=SECRET",
        "body_base64": body.base64EncodedString()
    ])
    let encoded = try JSONSerialization.data(withJSONObject: safe)
    let text = try #require(String(bytes: encoded, encoding: .utf8))
    for secret in [
        "123456789",
        "ABCD1234EFGH5678",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "email@example.com",
        "PRIVATE_SESSION",
        "SECRET"
    ] {
        #expect(!text.contains(secret))
    }
    #expect(text.contains("redacted key"))
    #expect(text.contains("ready"))
}

@Test func apiCaptureKeepsTrialCountsAndEntitlementDatesButNotOtherText() throws {
    let body = Data(#"""
        {"consumedCount":3,"remainingCount":7,"featureType":7,
        "inactiveDate":"2026-11-02T08:00:00.000Z","activeDate":"not a date",
        "name":"Private Name","titleCount":42}
        """#
        .utf8)
    let safe = APICaptureRedactor.redact(["body_base64": body.base64EncodedString()])
    let kept = try #require(safe["body"] as? [String: Any])
    #expect(kept["consumedCount"] as? Int == 3)
    #expect(kept["remainingCount"] as? Int == 7)
    #expect(kept["featureType"] as? Int == 7)
    #expect(kept["inactiveDate"] as? String == "2026-11-02T08:00:00.000Z")
    #expect(kept["activeDate"] as? String == "[redacted]")
    #expect(kept["name"] as? String == "[redacted]")
    #expect(kept["titleCount"] as? String == "[redacted]")
}

@Test private func apiCaptureKeepsOnlyKnownAppScopes() throws {
    for scope in ["psn:mobile.v2.core psn:clientapp", "psn:clientapp", "SECRET", "psn:clientapp SECRET", ""] {
        let data = try JSONSerialization.data(withJSONObject: ["scope": scope, "access_token": "SECRET"])
        let safe = APICaptureRedactor.redact(["body_base64": data.base64EncodedString()])
        let body = try #require(safe["body"] as? [String: Any])
        let expected = ["psn:mobile.v2.core psn:clientapp", "psn:clientapp"].contains(scope)
            ? scope
            : "[redacted]"
        #expect(body["scope"] as? String == expected)
        #expect(body["access_token"] as? String == "[redacted]")
    }
}

private func captureRequest() -> URLRequest {
    var request =
        URLRequest(
            url: URL(
                string: "https://web.np.playstation.com/api/sessionManager/v1/remotePlaySessions/"
                    + "SECRET_SESSION?token=SECRET_QUERY"
            )!
        )
    request.httpMethod = "POST"
    request.setValue("Bearer SECRET_TOKEN", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request
        .httpBody = Data(#"""
            {"access_token":"SECRET_BODY",
            "accountId":987654321,
            "state":"ready",
            "nested":{"key":"SECRET_KEY"},
            "count":2}
            """#
            .utf8)
    return request
}
