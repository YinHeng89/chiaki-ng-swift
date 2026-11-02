/// Everything one pairing attempt needs, validated before it reaches the core.
///
/// The request owns the PIN for a home pairing, so it cannot be copied and its PIN is wiped when the request
/// is consumed.
public struct PairingRequest: ~Copyable, Sendable {
    /// The longest address accepted, in UTF-8 bytes: the longest DNS name.
    public static let longestAddress = 253

    /// The account the pairing is for.
    public let account: AccountID

    /// The console to pair and how it is reached.
    public let target: PairingTarget

    /// The console's PIN, present exactly when ``target`` needs one.
    public let pin: PairingPIN?

    /// Validates the parts of a request.
    ///
    /// - Parameters:
    ///   - account: The account the pairing is for.
    ///   - target: The console to pair.
    ///   - pin: The PIN for a home pairing; `nil` for an internet pairing.
    /// - Throws: ``PairingFailure/invalidInput`` when a home target has no PIN, an internet target has one,
    ///   or the address is empty, longer than ``longestAddress`` or holds a character no host name or IP
    ///   literal uses.
    public init(account: AccountID, target: PairingTarget,
                pin: consuming PairingPIN?) throws(PairingFailure) {
        switch target {
        case .atHome(let address, _):
            guard pin != nil, Self.isAcceptable(address) else {
                throw .invalidInput
            }
        case .overInternet:
            guard pin == nil else {
                throw .invalidInput
            }
        }
        self.account = account
        self.target = target
        self.pin = pin
    }

    private static func isAcceptable(_ address: String) -> Bool {
        let bytes = address.utf8
        return !bytes.isEmpty && bytes.count <= longestAddress && bytes.allSatisfy { byte in
            (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
                || Array(".:-[]".utf8).contains(byte)
        }
    }
}
