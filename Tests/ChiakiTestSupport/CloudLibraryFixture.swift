import ChiakiModels
import Foundation

extension CloudLibrarySnapshot {
    /// Decodes a library snapshot from a JSON fixture with a `games` array of catalog rows.
    ///
    /// - Parameter data: The fixture's JSON.
    /// - Returns: The snapshot the fixture describes.
    /// - Throws: `CloudLibraryFailure.invalidCatalog` when the rows are missing, unnamed or repeated.
    public static func decode(_ data: Data) throws -> CloudLibrarySnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["games"] as? [[String: Any]] else {
            throw CloudLibraryFailure.invalidCatalog
        }
        let games = rows.map(CloudGame.init(fixture:))
        guard Set(games.map(\.id)).count == games.count,
              games.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }) else {
            throw CloudLibraryFailure.invalidCatalog
        }
        return CloudLibrarySnapshot(settledLocale: root["settledLocale"] as? String ?? "en-US", games: games)
    }
}

extension CloudGame {
    /// A cloud game built from one catalog row of a JSON fixture.
    ///
    /// - Parameter row: The row's fields by name; a missing field takes the catalog's default.
    public init(fixture row: [String: Any]) {
        let platform = row["platform"] as? String ?? "PS5"
        let owned = row["isOwned"] as? Bool ?? false
        let plus = row["plusCatalog"] as? Bool ?? false
        let service = row["streamServiceType"] as? String ?? "pscloud"
        let native = platform.lowercased() == "ps5"
        let included = !native || service == "psnow" || plus
        let marked = !((row["unstreamableKey"] as? String) ?? "").isEmpty
        let standing: CloudStanding
        if marked {
            standing = .mayStream
        } else if native, owned {
            standing = .inLibrary
        } else if included {
            standing = .included
        } else {
            standing = .store
        }
        let needsAdd = service == "pscloud" && !owned
        let release: CloudReleaseDate
        switch (row["availableFromMs"] as? NSNumber)?.int64Value {
        case .some(Int64.max):
            release = .unannounced
        case .some(let value) where value > 0:
            release = .scheduled(Date(timeIntervalSince1970: TimeInterval(value) / 1000))
        default:
            release = .unrestricted
        }
        var refusal: CloudLaunchRefusal?
        if needsAdd {
            refusal = included
                ? .addToLibrary
                : .buyToStream
        }
        self.init(
            productId: row["productId"] as? String ?? "",
            name: row["name"] as? String ?? "",
            imageUrl: row["imageUrl"] as? String,
            landscapeImageUrl: row["landscapeImageUrl"] as? String,
            platform: platform, isOwned: owned, plusCatalog: plus, streamServiceType: service,
            conceptUrl: row["conceptUrl"] as? String, conceptId: row["conceptId"] as? String,
            visible: row["visible"] as? Bool ?? true, hideReason: row["hideReason"] as? String,
            standing: standing, launchRefusal: refusal, needsLibraryAdd: needsAdd,
            canBeAddedToLibrary: needsAdd && included, needsStorefrontCheck: service == "pscloud" && native,
            release: release
        )
    }
}
