import ChiakiModels
import Foundation
import GRDB

/// The region and stated context of one profile, from the `account_context` table.
///
/// The row is deleted with its profile.
struct AccountContextRow: Sendable {
    /// Writes a profile's region, keeping its stated context.
    static let upsertRegion = """
    INSERT INTO account_context(profile_id, country, language) VALUES (?, ?, ?)
    ON CONFLICT(profile_id) DO UPDATE SET country = excluded.country, language = excluded.language
    """

    /// Writes a profile's stated context, keeping its region.
    static let upsertContext = """
    INSERT INTO account_context(profile_id, legal_country, locale, age, is_child, issued_at) VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(profile_id) DO UPDATE SET
        legal_country = excluded.legal_country,
        locale = excluded.locale,
        age = excluded.age,
        is_child = excluded.is_child,
        issued_at = excluded.issued_at
    """

    /// The country and language, when both are stored.
    let region: AccountRegion?

    /// The stated context.
    let context: StatedAccountContext

    /// Decodes the `account_context` columns of a joined row.
    ///
    /// - Parameter row: A row selecting the `account_context` columns, all `NULL` when the profile has none.
    /// - Throws: GRDB's decoding error when a column has the wrong type.
    init(joined row: Row) throws {
        let country = try row.decode(String?.self, forColumn: "country")
        let language = try row.decode(String?.self, forColumn: "language")
        region = if let country, let language {
            AccountRegion(country: country, language: language)
        } else {
            nil
        }
        let age = try row.decode(Int64?.self, forColumn: "age")
        let isChild = try row.decode(Int64?.self, forColumn: "is_child")
        context = try StatedAccountContext(
            legalCountry: row.decode(String?.self, forColumn: "legal_country"),
            locale: row.decode(String?.self, forColumn: "locale"),
            age: age.map(Int.init),
            isChild: isChild.map {
                $0 != 0
            },
            issuedAt: row.decode(Int64?.self, forColumn: "issued_at").map(Timestamp.date(milliseconds:))
        )
    }

    /// The arguments of ``upsertContext`` for a stated context.
    ///
    /// - Parameters:
    ///   - context: The context.
    ///   - profileID: The profile's row id.
    /// - Returns: The statement arguments.
    static func contextArguments(_ context: StatedAccountContext, profileID: String) -> StatementArguments {
        [
            profileID, context.legalCountry, context.locale, context.age.map { Int64($0) },
            context.isChild.map {
                $0
                    ? Int64(1)
                    : Int64(0)
            },
            context.issuedAt.map(Timestamp.milliseconds(of:))
        ]
    }
}
