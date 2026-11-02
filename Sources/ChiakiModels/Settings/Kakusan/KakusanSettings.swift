import Foundation

/// The persisted Kakusan preferences: the user's own STUN servers and media tuning.
///
/// The core picks Kakusan's STUN servers itself. ``stunServers`` is the user's override of that choice;
/// an empty list leaves the choice to the core.
public struct KakusanSettings: Equatable, Sendable, Codable {
    /// The most servers allowed.
    public static let maximumStunServers = 8

    /// The list older versions saved before the user chose any servers. Decoding it yields no override.
    static let formerDefaultStunServers = ["stun.l.google.com:19302", "stun.cloudflare.com:3478"]

    /// The user's own STUN servers, as `host:port`; empty to use the core's.
    public var stunServers: [String]

    /// The media tuning.
    public var tuning: KakusanMediaTuning

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - stunServers: The user's own STUN servers; empty to use the core's.
    ///   - tuning: The media tuning.
    public init(
        stunServers: [String] = [],
        tuning: KakusanMediaTuning = KakusanMediaTuning()
    ) {
        self.stunServers = stunServers
        self.tuning = tuning
    }

    /// Decodes settings, defaulting the tuning when an older version did not store it.
    ///
    /// The server list older versions saved as their default is read as no override.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when the servers are missing or malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decode([String].self, forKey: .stunServers)
        stunServers = stored == Self.formerDefaultStunServers
            ? []
            : stored
        tuning = try container
            .decodeIfPresent(KakusanMediaTuning.self, forKey: .tuning) ?? KakusanMediaTuning()
    }

    /// Splits typed text into server entries at whitespace and commas.
    ///
    /// - Parameter text: The typed text.
    /// - Returns: The entries.
    public static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    }

    /// The settings with servers lowercased and de-duplicated and the tuning clamped.
    ///
    /// - Returns: The validated settings.
    /// - Throws: ``KakusanSettingsError`` for an invalid server or too many servers.
    public func validated() throws -> Self {
        var seen = Set<String>()
        var servers: [String] = []
        for entry in stunServers {
            let server = entry.lowercased()
            guard Self.isValidServer(server) else {
                throw KakusanSettingsError.invalidServer(entry)
            }
            if seen.insert(server).inserted {
                servers.append(server)
            }
        }
        guard servers.count <= Self.maximumStunServers else {
            throw KakusanSettingsError.tooManyServers
        }
        return Self(stunServers: servers, tuning: tuning.clamped())
    }

    /// Whether an entry is an ASCII host name or address with a port from 1 to 65535.
    ///
    /// - Parameter server: The entry, as `host:port`.
    /// - Returns: `true` when it is valid.
    public static func isValidServer(_ server: String) -> Bool {
        guard let separator = server.lastIndex(of: ":") else {
            return false
        }
        let host = server[..<separator]
        let port = server[server.index(after: separator)...]
        guard let number = Int(port), (1 ... 65535).contains(number), !host.isEmpty, host.count <= 253 else {
            return false
        }
        return host.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || scalar == "." || scalar == "-"
        } && !host.hasPrefix(".") && !host.hasPrefix("-")
    }
}

/// Why Kakusan settings were refused.
public enum KakusanSettingsError: Error, Equatable, Sendable {
    /// The entry is not a valid `host:port`.
    case invalidServer(String)

    /// More than ``KakusanSettings/maximumStunServers`` servers were given.
    case tooManyServers
}
