/// The PlayStation Plus membership tier of a signed-in account.
///
/// The library header shows it beside the cloud status. An account whose tier PSN has not reported has no
/// tier at all rather than a placeholder case.
public enum PlusTier: Hashable, Sendable, CaseIterable {
    /// The account has no PlayStation Plus membership.
    case none
    /// PlayStation Plus Essential.
    case essential
    /// PlayStation Plus Extra.
    case extra
    /// PlayStation Plus Premium, which includes cloud streaming.
    case premium

    /// The name shown for the tier, such as `"PS Plus Premium"`.
    public var label: String {
        switch self {
        case .none:
            "No PS Plus"
        case .essential:
            "PS Plus Essential"
        case .extra:
            "PS Plus Extra"
        case .premium:
            "PS Plus Premium"
        }
    }
}
