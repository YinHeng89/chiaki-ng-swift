import Foundation

/// The 64-bit number PlayStation Network assigns to an account.
///
/// It is the stable identity of a user: pairings, saved sign-ins and a console's account list are keyed by
/// it. On the wire and in the `profiles.psn_account_id` column it is eight bytes, least significant byte
/// first. Users type it as the Base64 text of those eight bytes, and PSN's web APIs write it in decimal.
/// Every initialiser validates its input, so an ``AccountID`` always holds exactly eight bytes.
public struct AccountID: Hashable, Sendable {
    /// The number of bytes in the wire form.
    public static let byteCount = 8

    /// The most decimal digits an account id can have: the length of the largest 64-bit unsigned number.
    public static let maximumDecimalDigits = 20

    /// The account number.
    public let value: UInt64

    /// Wraps an account number.
    ///
    /// - Parameter value: The number PSN assigned.
    public init(value: UInt64) {
        self.value = value
    }

    /// Reads an account id from its eight-byte wire form, least significant byte first.
    ///
    /// - Parameter bytes: The wire form.
    /// - Returns: `nil` unless `bytes` holds exactly ``byteCount`` bytes.
    public init?(bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else {
            return nil
        }
        value = bytes.enumerated().reduce(0) { result, element in
            result | UInt64(element.element) << (8 * UInt64(element.offset))
        }
    }

    /// Reads an account id from the Base64 text of its eight-byte wire form.
    ///
    /// The text must be standard padded Base64 with nothing around it; callers trim user input first.
    ///
    /// - Parameter base64: The Base64 text, such as `"FQ3NWwAAAAA="`.
    /// - Returns: `nil` when the text is not Base64 or does not decode to exactly eight bytes.
    public init?(base64: some StringProtocol) {
        guard let data = Data(base64Encoded: String(base64)) else {
            return nil
        }
        self.init(bytes: data)
    }

    /// Reads an account id a user typed as Base64, ignoring surrounding whitespace.
    ///
    /// This is the one validator for typed account ids.
    ///
    /// - Parameter typed: The text as typed.
    /// - Returns: `nil` when the trimmed text is not the Base64 text of exactly eight bytes.
    public init?(typed: String) {
        self.init(base64: typed.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Reads an account id written in decimal, the form PSN's web APIs use.
    ///
    /// - Parameter decimal: One to ``maximumDecimalDigits`` ASCII digits, with no sign or spaces.
    /// - Returns: `nil` when the text is empty, too long, holds anything but digits or does not fit in 64
    ///   bits.
    public init?(decimal: some StringProtocol) {
        let digits = decimal.utf8
        guard !digits.isEmpty, digits.count <= Self.maximumDecimalDigits,
              digits.allSatisfy({ (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }),
              let value = UInt64(decimal, radix: 10)
        else {
            return nil
        }
        self.value = value
    }

    /// The eight-byte wire form, least significant byte first.
    public var bytes: [UInt8] {
        (0 ..< Self.byteCount).map {
            UInt8(truncatingIfNeeded: value >> (8 * UInt64($0)))
        }
    }

    /// The wire form as `Data`, as stored in `profiles.psn_account_id`.
    public var data: Data {
        Data(bytes)
    }

    /// The standard padded Base64 text of the wire form, the form users type.
    public var base64: String {
        data.base64EncodedString()
    }

    /// The account number in decimal, the form PSN's web APIs use.
    public var decimal: String {
        String(value)
    }
}
