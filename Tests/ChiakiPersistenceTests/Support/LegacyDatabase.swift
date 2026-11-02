import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB

struct LegacyDatabase {
    let queue: DatabaseQueue
    let cipher: CredentialCipher

    init(
        version: Int,
        keys: KeychainKeyStore = KeychainKeyStore(source: .memory()),
        path: String? = nil
    ) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        queue = if let path {
            try DatabaseQueue(path: path, configuration: configuration)
        } else {
            try DatabaseQueue(configuration: configuration)
        }
        cipher = CredentialCipher(keys: keys)
        try MigrationRunner.apply(Array(MigrationRunner.bundled().prefix(version)), to: queue, cipher: cipher)
    }

    func execute(_ sql: String, _ arguments: StatementArguments = []) throws {
        try queue.write { database in
            try database.execute(sql: sql, arguments: arguments)
        }
    }

    func migrate(to version: Int? = nil) throws {
        let steps = try MigrationRunner.bundled()
        try MigrationRunner.apply(Array(steps.prefix(version ?? steps.count)), to: queue, cipher: cipher)
    }

    func rows(_ sql: String, _ arguments: StatementArguments = []) throws -> [Row] {
        try queue.read { database in
            try Row.fetchAll(database, sql: sql, arguments: arguments)
        }
    }

    func version() throws -> Int? {
        try queue.read { database in
            try Int.fetchOne(database, sql: "PRAGMA user_version")
        }
    }

    func seal(_ text: String, context: String) throws -> Data {
        var bytes = Array(text.utf8)
        return try cipher.seal(SecretBytes(wiping: &bytes), context: context, allowKeyCreation: true)
    }

    static func referenceSeconds(_ milliseconds: Int64) -> Double {
        Double(milliseconds) / 1000 - Date.timeIntervalBetween1970AndReferenceDate
    }
}
