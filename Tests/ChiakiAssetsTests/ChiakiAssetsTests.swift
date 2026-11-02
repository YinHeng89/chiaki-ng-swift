import AppKit
import ChiakiAssets
import Foundation
import Testing

private let sourceAssets = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Assets")

private let sourceOnly: Set<String> = [
    "ChiakiAssets.swift",
    "ChiakiAssets.docc/ChiakiAssets.md",
    "UPSTREAM-COPYING",
    "Images/Branding/chiaki.svg",
    "ThirdParty/FSRCNNX/FSRCNNX_x2_16-0-4-1.glsl"
]

private let copiedDirectories = [
    "Licenses": "Licenses"
]

private func sourceFiles() throws -> [String] {
    let enumerator = try #require(FileManager.default.enumerator(
        at: sourceAssets, includingPropertiesForKeys: [.isRegularFileKey]
    ))
    return try enumerator.compactMap { item -> String? in
        let url = try #require(item as? URL)
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            return nil
        }
        return String(url.standardizedFileURL.path.dropFirst(sourceAssets.standardizedFileURL.path.count + 1))
    }
}

private func resolve(_ name: String, _ ext: String) throws -> URL {
    try #require(ChiakiAssets.url(forResource: name, withExtension: ext), "\(name).\(ext)")
}

@Test func everyProcessedAssetResolvesThroughTheAccessor() throws {
    let processed = try sourceFiles().filter { path in
        !sourceOnly.contains(path) && !copiedDirectories.keys.contains { path.hasPrefix($0 + "/") }
    }
    #expect(processed.count == 15)
    for path in processed {
        let file = URL(fileURLWithPath: path)
        let url = try resolve(file.deletingPathExtension().lastPathComponent, file.pathExtension)
        let shipped = try Data(contentsOf: url)
        let source = try Data(contentsOf: sourceAssets.appendingPathComponent(path))
        #expect(shipped == source, "\(path)")
    }
}

@Test func copiedDirectoriesKeepTheirLayout() throws {
    let root = try #require(ChiakiAssets.bundle.resourceURL)
    let copied = try sourceFiles().compactMap { path -> (String, String)? in
        copiedDirectories.first { path.hasPrefix($0.key + "/") }.map {
            (path, $0.value + path.dropFirst($0.key.count))
        }
    }
    #expect(copied.contains { $0.0 == "Licenses/AGPL-3.0-only-OpenSSL.txt" })
    #expect(copied.contains { $0.0 == "Licenses/Attributions/Controller-CREDITS.txt" })
    #expect(copied.contains { $0.0 == "Licenses/Attributions/Zacksly-Controllers-CREDITS.txt" })
    for (path, shippedPath) in copied {
        let shipped = try Data(contentsOf: root.appendingPathComponent(shippedPath))
        let source = try Data(contentsOf: sourceAssets.appendingPathComponent(path))
        #expect(shipped == source, "\(path)")
    }
    let licenses = try #require(ChiakiAssets.licensesURL)
    #expect(licenses.standardizedFileURL.path == root.appendingPathComponent("Licenses").standardizedFileURL
        .path)
}

@Test func sourceOnlyFilesAreNotShipped() throws {
    let root = try #require(ChiakiAssets.bundle.resourceURL)
    for path in sourceOnly {
        let name = URL(fileURLWithPath: path).lastPathComponent
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), "\(path)")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "\(path)")
    }
}

@Test func runtimeAssetsLoad() throws {
    for name in ["chiaki", "chiaking-color", "chiaking-white", "console-ps4", "console-ps5", "dualsense",
                 "binding-dualsense", "binding-dualshock4", "binding-xbox", "binding-generic",
                 "binding-pro-controller"] {
        let image = NSImage(contentsOf: try resolve(name, "png"))
        #expect(image?.isValid == true, "\(name)")
    }
    #expect(NSImage(contentsOf: try resolve("console", "svg"))?.isValid == true)
    let shader = try String(contentsOf: try resolve("VideoColour", "txt"), encoding: .utf8)
    #expect(!shader.isEmpty)
    let weights = try Data(contentsOf: try resolve("FSRCNNX16", "bin"))
    #expect(!weights.isEmpty)
    let notice = try String(contentsOf: try resolve("FSRCNNX16", "NOTICE"), encoding: .utf8)
    #expect(notice.contains("FSRCNNX"))
}
