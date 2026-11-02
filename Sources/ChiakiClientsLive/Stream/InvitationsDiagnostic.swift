import ChiakiCoreBridge
import ChiakiModels
import Dependencies
import Foundation

/// The `--diagnose-invitations` run: renews each saved PlayStation account and lists its game invitations once, with
/// the session and invitation ids a join would send, so invitations can be compared between accounts outside a
/// stream.
public enum InvitationsDiagnostic {
    /// Runs the diagnostic against the installed account service, then waits briefly so the core's log of the
    /// listing reaches the log file before the process exits.
    ///
    /// - Returns: The lines printed for the run, one block per account.
    public static func run() async -> String {
        @Dependency(\.accountService) var accountService
        do {
            let repository = try await accountService.storage()
            let accounts = try repository.accounts.list().filter {
                $0.method == .npsso
            }
            guard !accounts.isEmpty else {
                return "Invitations diagnostic requires a saved PlayStation account."
            }
            var lines: [String] = []
            for account in accounts {
                lines.append(contentsOf: await block(for: account.accountID))
            }
            try? await Task.sleep(for: .seconds(2))
            return lines.joined(separator: "\n")
        } catch {
            return "Invitations diagnostic could not read the saved accounts."
        }
    }

    private static func block(for account: AccountID) async -> [String] {
        let user: String
        do {
            user = try await UsersBridge().refresh(account).onlineID
        } catch {
            return ["Account sign-in failed."]
        }
        do throws(CloudInvitationFailure) {
            let invitations = try await GameInvitationsBridge().invitations(account: account)
            return ["\(user): \(invitations.count) invitations"] + invitations.map(describe)
        } catch {
            return ["\(user): listing failed: \(error)"]
        }
    }

    private static func describe(_ invitation: CloudGameInvitation) -> String {
        let kind = UUID(uuidString: invitation.id) == nil
            ? "older PS4 session"
            : "SessionManager session"
        let sender = invitation.inviter.isEmpty
            ? "unknown"
            : invitation.inviter
        let invitationID = invitation.invitationID.isEmpty
            ? "none"
            : invitation.invitationID
        return [
            "  from \(sender), unread \(invitation.unread), \(kind)",
            "    session \(invitation.id)",
            "    invitation \(invitationID)",
            "    titles \(invitation.titleIDs.joined(separator: " "))"
        ].joined(separator: "\n")
    }
}
