import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func accountRefreshSummaryNamesChangesAndProblems() {
    let first = AccountProfile(
        id: UUID(), name: "One", method: .npsso, accountID: AccountID(value: 0), onlineID: "One"
    )
    var plus = first
    plus.isPlus = true
    let second = AccountProfile(
        id: UUID(), name: "Two", method: .npsso, accountID: AccountID(value: 0), onlineID: "Two"
    )
    let result = AccountRefreshResult(accounts: [plus, second], issues: [second.id: .signInRequired])
    #expect(
        AccountRefreshSummary.message(before: [first, second], after: result)
            == "Account refresh finished for 2 accounts; changes: \"One\" PS Plus unknown -> yes; "
            + "problems: \"Two\" needs sign-in"
    )
    #expect(
        AccountRefreshSummary.message(before: [second], after: .init(accounts: [second]))
            == "Account refresh finished for 1 account; changes: none; problems: none"
    )
}
