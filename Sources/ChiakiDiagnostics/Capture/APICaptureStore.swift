import ChiakiModels
import Foundation

/// Writes opt-in, redacted PSN API exchanges to `API Captures/api-capture.jsonl` in the log folder.
///
/// Nothing is written unless `LogSettings/captureAPI` is on. Every record passes through
/// ``APICaptureRedactor/redact(_:)`` before it reaches the disk. A failed write is reported once through
/// ``takeWriteFailure()`` and keeps ``writeFailed`` set until a later write succeeds.
public actor APICaptureStore {
    private static let bodyLimit = 16 * 1024 * 1024
    private static let coreRecordLimit = 48 * 1024 * 1024

    private var settings = LogSettings.defaults
    private let maximumBytes: Int
    private var file: RotatingLogFile?
    private let run = UUID().uuidString
    private var failurePending = false

    /// Whether the last capture write failed.
    public private(set) var writeFailed = false

    /// Creates a store.
    ///
    /// - Parameter maximumBytes: The size the capture file may reach before it rotates.
    public init(maximumBytes: Int = 32 * 1024 * 1024) {
        self.maximumBytes = maximumBytes
    }

    /// Returns whether a write failed since the last call, and clears it.
    ///
    /// - Returns: `true` once per run of failures.
    public func takeWriteFailure() -> Bool {
        let pending = failurePending
        failurePending = false
        return pending
    }

    /// Applies new settings, closing the file when the folder changes or capture turns off.
    ///
    /// - Parameter settings: The settings to apply.
    public func configure(_ settings: LogSettings) {
        if settings.directory != self.settings.directory || !settings.captureAPI {
            file = nil
        }
        self.settings = settings
        writeFailed = false
    }

    /// Captures an outgoing request.
    ///
    /// - Parameter request: The request about to be sent.
    /// - Returns: The call id to pass to ``finish(_:status:headers:body:errorCode:durationUS:)``, or `nil`
    ///   when capture is off.
    public func begin(_ request: URLRequest) -> UUID? {
        guard settings.captureAPI else {
            return nil
        }
        let id = UUID()
        var value: [String: Any] = [
            "schema": 1, "source": "native", "call": id.uuidString, "phase": "request",
            "method": request.httpMethod ?? "GET", "url": request.url?.absoluteString ?? "",
            "timeout_ms": Int(request.timeoutInterval * 1000),
            "headers": (request.allHTTPHeaderFields ?? [:]).map { ["name": $0.key, "value": $0.value] }
        ]
        payload(request.httpBody ?? Data(), into: &value)
        if request.httpBodyStream != nil {
            value["body_omitted"] = "streamed request body is unavailable to capture"
        }
        write(value)
        return id
    }

    /// Captures the outcome of a call started with ``begin(_:)``.
    ///
    /// - Parameters:
    ///   - id: The call id, or `nil` when the request was not captured.
    ///   - status: The HTTP status, or `nil` when no response arrived.
    ///   - headers: The response headers.
    ///   - body: The response body.
    ///   - errorCode: The transport error code when no response arrived.
    ///   - durationUS: The call duration in microseconds.
    public func finish(
        _ id: UUID?, status: Int?, headers: [String: String] = [:], body: Data = Data(), errorCode: Int?,
        durationUS: Int64
    ) {
        guard settings.captureAPI, let id else {
            return
        }
        var value: [String: Any] = [
            "schema": 1, "source": "native", "call": id.uuidString,
            "phase": "response", "duration_us": durationUS
        ]
        if let status {
            value["status"] = status
            value["headers"] = headers.map { ["name": $0.key, "value": $0.value] }
            payload(body, into: &value)
        } else {
            value["transport_error"] = errorCode ?? -1
        }
        write(value)
    }

    /// Captures one JSON record produced by the native core, or a loss marker when it cannot be read.
    ///
    /// - Parameter data: The core's JSON object.
    public func recordCore(_ data: Data) {
        guard settings.captureAPI else {
            return
        }
        guard data.count <= Self.coreRecordLimit,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            write(["schema": 1, "source": "core", "phase": "capture_loss", "dropped": 1])
            return
        }
        write(value)
    }

    private func payload(_ data: Data, into value: inout [String: Any]) {
        value["body_bytes"] = data.count
        if data.count <= Self.bodyLimit {
            value["body_base64"] = data.base64EncodedString()
        } else {
            value["body_omitted"] = "exceeds 16 MiB capture limit"
        }
    }

    private func write(_ value: [String: Any]) {
        guard settings.captureAPI else {
            return
        }
        do {
            var safe = APICaptureRedactor.redact(value)
            safe["run"] = run
            safe["captured_at"] = Date().ISO8601Format(.init(includingFractionalSeconds: true))
            var data = try JSONSerialization.data(
                withJSONObject: safe,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            data.append(10)
            try captureFile().append(data)
            writeFailed = false
        } catch {
            file = nil
            if !writeFailed {
                failurePending = true
            }
            writeFailed = true
        }
    }

    private func captureFile() -> RotatingLogFile {
        if let file {
            return file
        }
        let directory = URL(fileURLWithPath: settings.directory, isDirectory: true)
            .appendingPathComponent("API Captures", isDirectory: true)
        let created = RotatingLogFile(
            directory: directory, name: "api-capture", suffix: "jsonl", maximumBytes: maximumBytes
        )
        file = created
        return created
    }
}
