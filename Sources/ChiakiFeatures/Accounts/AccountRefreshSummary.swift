import ChiakiDiagnostics
import ChiakiModels
import Foundation

/// Describes for the log what an account refresh changed.
public enum AccountRefreshSummary {
    /// The log line for a refresh that started.
    ///
    /// - Parameters:
    ///   - count: How many accounts are refreshed.
    ///   - reason: Why the refresh runs.
    /// - Returns: The line.
    public static func started(count: Int, reason: AccountsRefreshReason) -> String {
        let accounts = count == 1
            ? "account"
            : "accounts"
        return "Refreshing \(count) \(accounts): " + describe(reason)
    }

    private static func describe(_ reason: AccountsRefreshReason) -> String {
        switch reason {
        case .accountAdded:
            "an account was just added"
        case .firstSinceLoad:
            "first refresh since the accounts were loaded"
        case .periodic(let seconds):
            "periodic check, the last refresh was \(seconds) s ago "
                + "(checked every 60 s, refreshed when at least 60 s old)"
        }
    }

    /// The log line for a finished refresh.
    ///
    /// - Parameters:
    ///   - before: The accounts before the refresh.
    ///   - result: The refresh result.
    /// - Returns: The changed names, PS Plus states and avatars, and the accounts that could not be refreshed.
    public static func message(before: [AccountProfile], after result: AccountRefreshResult) -> String {
        var changes: [String] = []
        for account in result.accounts {
            let name = "\"\(account.onlineID ?? account.name)\""
            guard let old = before.first(where: { $0.id == account.id }) else {
                changes.append("\(name) added")
                continue
            }
            if old.onlineID != account.onlineID {
                changes.append("\(name) online ID was \"\(old.onlineID ?? "unknown")\"")
            }
            if old.isPlus != account.isPlus {
                changes.append("\(name) PS Plus \(flag(old.isPlus)) -> \(flag(account.isPlus))")
            }
            if (old.avatarData == nil) != (account.avatarData == nil) || old.avatarData?.count != account
                .avatarData?
                .count {
                changes.append("\(name) avatar updated")
            }
        }
        for account in before where !result.accounts.contains(where: { $0.id == account.id }) {
            changes.append("\"\(account.onlineID ?? account.name)\" removed")
        }
        let issues = result.issues.map { id, issue in
            let name = result.accounts.first { $0.id == id }.map {
                $0.onlineID ?? $0.name
            } ?? LogFormat.idPrefix(id)
            let state = issue == .signInRequired
                ? "needs sign-in"
                : "unavailable"
            return "\"\(name)\" \(state)"
        }.sorted()
        return "Account refresh finished for \(result.accounts.count) "
            + (result.accounts.count == 1
                ? "account"
                : "accounts")
                + "; changes: " + (changes.isEmpty
                    ? "none"
                    : changes.joined(separator: ", "))
                    + "; problems: " + (issues.isEmpty
                        ? "none"
                        : issues.joined(separator: ", "))
    }

    private static func flag(_ value: Bool?) -> String {
        value.map {
            $0
                ? "yes"
                : "no"
        } ?? "unknown"
    }
}
