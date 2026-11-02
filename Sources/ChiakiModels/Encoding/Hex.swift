/// The one hexadecimal codec for bytes.
///
/// Every place that writes bytes as hex text or reads them back goes through ``Hex/encode(_:letterCase:)``
/// and ``Hex/decode(_:)``, so the alphabet and the validation rules exist once.
public enum Hex {
    /// The letter case used for the digits `a` to `f`.
    public enum LetterCase: Sendable {
        /// Lowercase digits, the form stored in the database.
        case lower

        /// Uppercase digits, the form shown for discovered consoles.
        case upper
    }

    /// Writes bytes as hexadecimal text, two digits per byte, most significant nibble first.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to write.
    ///   - letterCase: The case of the digits `a` to `f`.
    /// - Returns: The hex text, empty when `bytes` is empty.
    public static func encode(_ bytes: some Sequence<UInt8>, letterCase: LetterCase = .lower) -> String {
        let alphabet = switch letterCase {
        case .lower:
            lowerDigits
        case .upper:
            upperDigits
        }
        let bytes = Array(bytes)
        return String(unsafeUninitializedCapacity: bytes.count * 2) { text in
            for (index, byte) in bytes.enumerated() {
                text[2 * index] = alphabet[Int(byte >> 4)]
                text[2 * index + 1] = alphabet[Int(byte & 0x0F)]
            }
            return bytes.count * 2
        }
    }

    /// Reads hexadecimal text back into bytes.
    ///
    /// Both letter cases are accepted. Nothing else is: no prefix, separators or whitespace.
    ///
    /// - Parameter text: An even number of ASCII hex digits.
    /// - Returns: The bytes, or `nil` when the text has an odd length or holds a character that is not an
    ///   ASCII hex digit.
    public static func decode(_ text: some StringProtocol) -> [UInt8]? {
        decode(utf8: text.utf8)
    }

    /// Reads hexadecimal text, given as UTF-8 code units, back into bytes.
    ///
    /// The rules are those of ``decode(_:)``.
    ///
    /// - Parameter utf8: An even number of code units, each an ASCII hex digit.
    /// - Returns: The bytes, or `nil` when the count is odd or a code unit is not an ASCII hex digit.
    public static func decode(utf8: some Collection<UInt8>) -> [UInt8]? {
        let digits = Array(utf8)
        guard digits.count.isMultiple(of: 2) else {
            return nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = value(of: digits[index]), let low = value(of: digits[index + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    /// Reports whether a UTF-8 code unit is an ASCII hex digit in either case.
    ///
    /// - Parameter codeUnit: The code unit to check.
    /// - Returns: `true` for `0`–`9`, `a`–`f` and `A`–`F`.
    public static func isDigit(_ codeUnit: UInt8) -> Bool {
        value(of: codeUnit) != nil
    }

    private static let lowerDigits = Array("0123456789abcdef".utf8)

    private static let upperDigits = Array("0123456789ABCDEF".utf8)

    private static func value(of codeUnit: UInt8) -> UInt8? {
        switch codeUnit {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"):
            codeUnit - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"):
            codeUnit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"):
            codeUnit - UInt8(ascii: "A") + 10
        default:
            nil
        }
    }
}
