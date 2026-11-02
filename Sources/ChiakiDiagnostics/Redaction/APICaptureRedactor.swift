import Foundation

/// Redacts API capture records before they are written: header values, URLs and JSON bodies are reduced to
/// what an allow-list proves safe.
public enum APICaptureRedactor {
    /// Redacts one API capture record before it is written.
    ///
    /// Header values survive only for allow-listed names and values, the URL keeps only public hosts and known
    /// static path parts, and a base64 body is decoded and reduced to allow-listed JSON scalars.
    ///
    /// - Parameter input: The capture record.
    /// - Returns: The record safe to write.
    public static func redact(_ input: [String: Any]) -> [String: Any] {
        var out = input
        out["privacy"] = "redacted: header allowlist, URL values, conservative JSON scalar allowlist"
        if let url = input["url"] as? String {
            out["url"] = redactCaptureURL(url)
        }
        if input["reason"] != nil {
            out["reason"] = LogRedactor.secretPlaceholder
        }
        if let headers = input["headers"] as? [[String: String]] {
            out["headers"] = headers.map { header in
                let name = header["name"] ?? ""
                return ["name": name, "value": captureHeaderValue(name: name, value: header["value"] ?? "")]
            }
        }
        if let encoded = out.removeValue(forKey: "body_base64") as? String,
           let data = Data(base64Encoded: encoded) {
            if data.isEmpty {
                out["body"] = ""
            } else if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                out["body"] = captureBody(json)
            } else {
                out["body_omitted"] = "non-JSON body redacted; original byte count retained"
            }
        }
        return out
    }

    private static let captureNumericFields: Set<String> = [
        "status", "statuscode", "httpstatus", "errorcode", "code", "port", "localport", "mappedport",
        "timeout", "timeoutms", "retryafter", "pollinterval", "duration", "count", "total", "offset",
        "limit", "width", "height", "fps", "bitrate", "mtu", "version", "protocolversion",
        "consumedcount", "remainingcount", "featuretype", "entitlementtype"
    ]

    private static let captureDateFields: Set<String> = [
        "activedate", "inactivedate", "playabilitydate"
    ]

    private static let captureEnumFields: Set<String> = [
        "state",
        "status",
        "type",
        "platform",
        "codec",
        "method"
    ]

    private static let captureEnumValues: Set<String> = [
        "ready", "pending", "waiting", "active", "inactive", "failed", "error", "success", "ok", "busy",
        "ps4", "ps5", "psnow", "pscloud", "h264", "h265", "hevc", "offer", "answer", "result",
        "accept", "get", "post", "delete", "true", "false"
    ]

    private static let captureHeaderNames: Set<String> = [
        "content-type", "content-length", "retry-after", "accept", "cache-control"
    ]

    private static let captureHeaderValues: Set<String> = [
        "application/json", "application/x-www-form-urlencoded", "text/plain", "no-cache", "no-store", "*/*"
    ]

    private static let capturePublicHosts: Set<String> = [
        "web.np.playstation.com", "asm.np.community.playstation.net",
        "mobile-pushcl.np.communication.playstation.net", "ca.account.sony.com",
        "cc.prod.gaikai.com", "config.cc.prod.gaikai.com", "psnow.playstation.com",
        "commerce.api.np.km.playstation.net", "accounts.api.playstation.com",
        "raw.githubusercontent.com"
    ]

    private static let captureStaticPathParts: Set<String> = [
        "", "api", "v1", "v2", "v3", "users", "me", "sessions", "start", "authorize", "authorizeCheck",
        "lock", "datacenters", "select", "allocate", "client_ids", "config", "sessionManager",
        "remotePlaySessions", "members", "sessionMessage", "cloudAssistedNavigation", "commands",
        "oauth", "authz", "np", "serveraddr", "kamaji", "pcnow", "store", "buynow", "preview",
        "user", "session", "accounts", "attributes", "commerce", "internal_entitlements"
    ]

    private static func captureHeaderValue(name: String, value: String) -> String {
        let lowered = name.lowercased()
        if ["content-length", "retry-after"].contains(lowered), Int(value) != nil {
            return value
        }
        if captureHeaderNames.contains(lowered), captureHeaderValues.contains(value.lowercased()) {
            return value
        }
        return LogRedactor.secretPlaceholder
    }

    private static func captureBody(_ value: Any, key: String = "", depth: Int = 0) -> Any {
        guard depth < 48 else {
            return "[redacted: nesting limit]"
        }
        if let object = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (name, item) in object {
                let safeName = isSafeCaptureKey(name)
                    ? name
                    : "[redacted key \(result.count)]"
                result[safeName] = captureBody(item, key: name, depth: depth + 1)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map {
                captureBody($0, key: key, depth: depth + 1)
            }
        }
        if value is NSNull {
            return value
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() || captureNumericFields
                .contains(LogRedactor.normalizedKey(key)) {
                return number
            }
            return LogRedactor.secretPlaceholder
        }
        if let text = value as? String {
            return captureText(text, key: key)
        }
        return LogRedactor.secretPlaceholder
    }

    private static func captureText(_ text: String, key: String) -> String {
        let normalized = LogRedactor.normalizedKey(key)
        if captureEnumFields.contains(normalized), captureEnumValues.contains(text.lowercased()) {
            return text
        }
        if key == "scope", isKnownAppScope(text) {
            return text
        }
        if captureDateFields.contains(normalized),
           (try? Date.ISO8601FormatStyle(includingFractionalSeconds: text.contains(".")).parse(text)) != nil {
            return text
        }
        return LogRedactor.secretPlaceholder
    }

    private static func isKnownAppScope(_ text: String) -> Bool {
        let scopes = text.split(separator: " ", omittingEmptySubsequences: false)
        return !scopes.isEmpty
            && scopes.allSatisfy {
                $0 == "psn:mobile.v2.core" || $0 == "psn:clientapp"
            }
    }

    private static func isSafeCaptureKey(_ name: String) -> Bool {
        name.count <= 64 && name.contains(where: \.isLetter)
            && name.allSatisfy {
                $0.isASCII && ($0.isLetter || $0 == "_" || $0 == "-")
            }
            && !(name.count >= 16 && name.allSatisfy(\.isHexDigit))
    }

    private static func redactCaptureURL(_ text: String) -> String {
        guard var url = URLComponents(string: text), let host = url.host else {
            return LogRedactor.secretPlaceholder
        }
        guard capturePublicHosts.contains(host.lowercased()) else {
            return "[redacted URL]"
        }
        url.user = nil
        url.password = nil
        url.fragment = nil
        url.path = url.path.components(separatedBy: "/").map {
            captureStaticPathParts.contains($0)
                ? $0
                : "REDACTED"
        }
        .joined(separator: "/")
        url.queryItems = url.queryItems?.map {
            URLQueryItem(name: $0.name, value: "REDACTED")
        }
        return url.string ?? "[redacted URL]"
    }
}
