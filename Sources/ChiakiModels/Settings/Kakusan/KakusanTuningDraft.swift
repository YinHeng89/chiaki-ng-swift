import Foundation

/// The media tuning as typed, one text per field, before it validates.
public struct KakusanTuningDraft: Equatable, Sendable {
    private var text: [KakusanMediaTuning.Field: String]

    /// Fills the draft from a tuning.
    ///
    /// - Parameter tuning: The tuning to show.
    public init(_ tuning: KakusanMediaTuning = KakusanMediaTuning()) {
        text = Dictionary(uniqueKeysWithValues: KakusanMediaTuning.Field.allCases.map { field in
            (field, String(tuning[field]))
        })
    }

    /// The text typed for a field.
    ///
    /// - Parameter field: The field.
    public subscript(field: KakusanMediaTuning.Field) -> String {
        get {
            text[field] ?? ""
        }
        set {
            text[field] = newValue
        }
    }

    /// The value typed for a field, when it is a number in the field's range.
    ///
    /// - Parameter field: The field.
    /// - Returns: The value, or `nil` when the text does not validate.
    public func value(_ field: KakusanMediaTuning.Field) -> Int? {
        guard let number = Int(self[field].trimmingCharacters(in: .whitespaces)),
              field.range.contains(number) else {
            return nil
        }
        return number
    }

    /// The tuning the draft describes, when every field validates.
    public var tuning: KakusanMediaTuning? {
        var result = KakusanMediaTuning()
        for field in KakusanMediaTuning.Field.allCases {
            guard let number = value(field) else {
                return nil
            }
            result[field] = number
        }
        return result
    }
}
