import Foundation
import Testing

@Test func theBridgeReachesTheCoreOnlyThroughItsFaces() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let faces = ["chiaki", "users", "consoles", "catalog", "trophies", "play", "kakusan", "messages"]
        .flatMap {
            $0 == "chiaki"
                ? ["libchiaking/chiaki_ng.hpp"]
                : ["libchiaking/\($0).hpp", "libchiaking/\($0)_types.hpp"]
        } + [
            "libchiaking/platform/platform.hpp",
            "libchiaking/platform/defaults.hpp",
            "libchiaking/platform/stock_providers.hpp",
            "libchiaking/version.hpp"
        ]
    var offences: [String] = []
    var seen = 0
    for (folder, isTest) in [
        ("lib/bridge", false),
        ("Tests/Native", true),
        ("Sources/Video", false),
        ("Sources/ChiakiStoreAdapters", false)
    ] {
        let files = try #require(
            FileManager.default.enumerator(
                at: root.appendingPathComponent(folder),
                includingPropertiesForKeys: nil
            )
        )
        for case let file as URL in files
            where ["cpp", "hpp", "h", "c", "m", "mm"].contains(file.pathExtension) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n")
                where line.hasPrefix("#include") && line.contains("libchiaking/") {
                let path = line.drop { $0 != "<" && $0 != "\"" }.dropFirst()
                    .prefix { $0 != ">" && $0 != "\"" }
                seen += 1
                let allowed = faces.contains(String(path))
                    || (isTest && path.hasPrefix("libchiaking/testing/"))
                if !allowed || path.contains("/detail/") {
                    offences.append("\(file.lastPathComponent): \(path)")
                }
            }
        }
    }
    #expect(seen > 10)
    #expect(offences.sorted() == [])
}
