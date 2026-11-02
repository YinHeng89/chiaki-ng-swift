/// A settings value that is loaded, edited and saved as one unit.
///
/// A conforming type names its ``settingKey``, folds equivalent values together in ``normalized()`` and
/// rejects values that must never be stored in ``validated()``. ``PersistedSetting`` commits an edit only
/// when the edited value validates.
public protocol PersistedSettingValue: Codable, Equatable, Sendable {
    /// Why a value is rejected.
    associatedtype ValidationFailure: Error = Never

    /// The key the value is stored under.
    static var settingKey: SettingKey<Self> { get }

    /// The value with equivalent forms folded together, such as clamped ranges.
    ///
    /// - Returns: The normalised value.
    func normalized() -> Self

    /// The value checked for storage.
    ///
    /// - Returns: The value to store.
    /// - Throws: `ValidationFailure` when the value must not be stored.
    func validated() throws(ValidationFailure) -> Self
}

public extension PersistedSettingValue {
    /// The value unchanged.
    ///
    /// - Returns: `self`.
    func normalized() -> Self {
        self
    }
}

public extension PersistedSettingValue where ValidationFailure == Never {
    /// The value unchanged; a value with no rules is always valid.
    ///
    /// - Returns: `self`.
    func validated() -> Self {
        self
    }
}

public extension PersistedSettingValue {
    /// The name the value is stored under.
    static var settingName: String {
        settingKey.name
    }

    /// The value before one is saved.
    static var defaultSetting: any PersistedSettingValue {
        settingKey.defaultValue
    }

    /// The name this value is stored under.
    var settingName: String {
        Self.settingKey.name
    }

    /// Whether the value can be stored.
    var isValid: Bool {
        do {
            _ = try validated()
            return true
        } catch {
            return false
        }
    }
}
