import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels
import ChiakiPersistence
import Foundation
import Testing

extension CoreSessionSuites {
    @Suite struct CredentialStoreAdapterTests {
        let account = AccountID(value: 0x0A0B_0C0D_0E0F_1011)
        let obtainedAtMs: Int64 = 1_760_000_000_123

        func secret(_ text: String) -> SecretBytes {
            var bytes = Array(text.utf8)
            return SecretBytes(wiping: &bytes)
        }

        func seed(_ harness: CoreSessionHarness) throws {
            let obtained = Date(timeIntervalSince1970: TimeInterval(obtainedAtMs) / 1000)
            let refresh = StoredToken(
                value: secret("refresh-token"),
                obtainedAt: obtained,
                expiresAt: obtained.addingTimeInterval(86400)
            )
            let signIn = StoredSignIn(
                account: account,
                onlineID: "Player",
                npsso: secret("seed-npsso"),
                npssoObtainedAt: obtained,
                tokens: [.remotePlayRefresh: refresh]
            )
            try harness.repositories.credentials.save(signIn)
        }

        @Test func aSavedSignInIsWelcomedBackWithItsDatesAndSecrets() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            try seed(harness)
            let session = try harness.open()
            defer {
                session.close()
            }
            let welcomed = try #require(session.users.welcomeBack())
            #expect(welcomed.admitted == 1)
            #expect(welcomed.rejected == 0)
            let held = try #require(session.credentials.held(by: account))
            let renewal = try #require(held.first { $0.kind == .remotePlayRefreshToken })
            #expect(renewal.held)
            #expect(renewal.obtainedAt == Date(timeIntervalSince1970: TimeInterval(obtainedAtMs) / 1000))
            let revealed = try session.credentials.reveal(.signInSeed, of: account)
            #expect(revealed.text == "seed-npsso")
            #expect(throws: NotRevealed(.notHeld)) {
                try session.credentials.reveal(.appToken, of: account)
            }
        }

        @Test func signingOutInTheCoreRemovesTheSavedAccount() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            try seed(harness)
            let session = try harness.open()
            defer {
                session.close()
            }
            _ = session.users.welcomeBack()
            #expect(session.users.signOut(account))
            #expect(try harness.repositories.credentials.savedSignIns().isEmpty)
        }

        @Test func aHomeUserAddedInTheCoreIsSavedAndComesBack() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let first = try harness.open()
            let added = first.users.addHomeUser(account, name: "Den")
            first.close()
            #expect(added?.onlineID == "Den")
            #expect(added?.state == .signedOut)
            let saved = try harness.repositories.credentials.homeUsers()
            #expect(saved == [StoredHomeUser(account: account, name: "Den")])

            let second = try harness.open()
            defer {
                second.close()
            }
            #expect(second.users.welcomeBack()?.admitted == 1)
            #expect(second.users.find(account)?.hasPSNAccount == false)
            #expect(second.users.everyone().map(\.accountID) == [account])
            #expect(throws: NotRevealed(.signedOut)) {
                try second.credentials.reveal(.signInSeed, of: account)
            }
        }
    }
}
