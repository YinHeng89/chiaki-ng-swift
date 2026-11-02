import Foundation

/// The file form of a Kakusan block, so an invitation or reply can be shared as an attachment.
public enum KakusanBlockFile {
    /// The extension of a block file.
    public static let fileExtension = "kakusan"

    /// The file name, without extension, a block is shared under.
    ///
    /// - Parameter block: The block.
    /// - Returns: A name that says what the block is.
    public static func name(for block: KakusanBlock) -> String {
        switch block.kind {
        case .invitation:
            "Kakusan invitation"
        case .reply:
            "Kakusan reply"
        case .unrecognised:
            "Kakusan"
        }
    }

    /// Reads a block from a file the system opened with the app.
    ///
    /// - Parameter url: The file.
    /// - Returns: The block, or `nil` when the file is not a block file, is too large, or does not hold a block.
    public static func read(_ url: URL) -> KakusanBlock? {
        guard url.isFileURL, url.pathExtension.lowercased() == fileExtension else {
            return nil
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= KakusanBlock.maximumPastedLength,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return KakusanBlock(pasted: text)
    }
}
