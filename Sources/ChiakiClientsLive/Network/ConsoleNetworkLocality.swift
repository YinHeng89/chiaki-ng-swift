import Darwin
import Foundation
import Network

/// Decides whether a console address is on the local network rather than reached over the internet.
public enum ConsoleNetworkLocality {
    /// How long a host name lookup may take before the address is treated as local.
    public static let resolveTimeout = Duration.seconds(2)

    /// Classifies a literal IPv4 or IPv6 address.
    ///
    /// Private, link-local and loopback IPv4 ranges, IPv6 link-local, unique local and loopback addresses,
    /// and IPv4-mapped local addresses count as local.
    ///
    /// - Parameter address: The address, optionally bracketed or carrying an IPv6 zone.
    /// - Returns: Whether it is local, or `nil` when it is not an IP literal.
    public static func isLocal(literal address: String) -> Bool? {
        let trimmed = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let host = trimmed.split(separator: "%", maxSplits: 1).first.map(String.init) ?? trimmed
        if let ipv4 = IPv4Address(host) {
            return isLocal(ipv4)
        }
        if let ipv6 = IPv6Address(host) {
            return isLocal(ipv6)
        }
        return nil
    }

    /// Classifies an address or host name, resolving names when needed.
    ///
    /// `.local` and single-label names are local. Another name is local unless it resolves to an address that
    /// is not, and a lookup that fails or exceeds ``ConsoleNetworkLocality/resolveTimeout`` counts as local.
    ///
    /// - Parameter address: The address or host name.
    /// - Returns: Whether the console is on the local network.
    public static func isLocal(_ address: String) async -> Bool {
        if let literal = isLocal(literal: address) {
            return literal
        }
        let name = address.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if name.hasSuffix(".local") || !name.contains(".") {
            return true
        }
        let resolved = await withTaskGroup(of: [String]?.self) { group in
            group.addTask {
                await Task.detached {
                    resolve(name)
                }.value
            }
            group.addTask {
                try? await Task.sleep(for: resolveTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
        guard !resolved.isEmpty else {
            return true
        }
        return resolved.allSatisfy {
            isLocal(literal: $0) ?? true
        }
    }

    private static func isLocal(_ address: IPv4Address) -> Bool {
        let bytes = Array(address.rawValue)
        switch (bytes[0], bytes[1]) {
        case (10, _), (127, _), (192, 168), (169, 254):
            return true
        case (172, let second):
            return second & 0xF0 == 16
        default:
            return false
        }
    }

    private static func isLocal(_ address: IPv6Address) -> Bool {
        if address.isLoopback || address.isLinkLocal {
            return true
        }
        if let mapped = address.asIPv4 {
            return isLocal(mapped)
        }
        return Array(address.rawValue)[0] & 0xFE == 0xFC
    }

    private static func resolve(_ name: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else {
            return []
        }
        defer {
            freeaddrinfo(first)
        }
        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0,
                NI_NUMERICHOST
            ) == 0, let address = String(
                bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                encoding: .utf8
            ) {
                addresses.append(address)
            }
            cursor = entry.pointee.ai_next
        }
        return addresses
    }
}
