import Darwin
import Foundation

/// The one size-bounded, rotating, owner-only append file behind both the log and the API capture.
///
/// The live file is `<name>.<suffix>`; when the next write would pass the limit it becomes `<name>.1.<suffix>`,
/// older generations shift up, and the oldest past ``generations`` is removed. The folder is created owner-only
/// and refused when it is a symbolic link; files are opened without following links and kept at mode 0600.
public final class RotatingLogFile {
    /// How many rotated generations are kept beside the live file.
    public static let generations = 3

    private let directory: URL
    private let name: String
    private let suffix: String
    private let maximumBytes: UInt64
    private var handle: FileHandle?
    private var size: UInt64 = 0

    /// Creates a writer; nothing touches the disk until the first ``append(_:)``.
    ///
    /// - Parameters:
    ///   - directory: The folder holding the files.
    ///   - name: The file name before the generation and suffix.
    ///   - suffix: The file extension.
    ///   - maximumBytes: The size a file may reach before it rotates.
    public init(directory: URL, name: String, suffix: String, maximumBytes: Int) {
        self.directory = directory
        self.name = name
        self.suffix = suffix
        self.maximumBytes = UInt64(max(1, maximumBytes))
    }

    deinit {
        try? handle?.close()
    }

    /// The file names, oldest generation first and the live file last.
    public var fileNames: [String] {
        stride(from: Self.generations, through: 1, by: -1).map(generation) + [live]
    }

    /// Appends `data`, rotating first when it would push a non-empty file past the limit.
    ///
    /// - Parameter data: The bytes to append.
    /// - Throws: The file system error when the folder or file cannot be prepared or written; the file is closed
    ///   so the next append starts over.
    public func append(_ data: Data) throws {
        do {
            try openIfNeeded()
            if size > 0, size + UInt64(data.count) > maximumBytes {
                try rotate()
                try openIfNeeded()
            }
            try handle?.write(contentsOf: data)
            size += UInt64(data.count)
        } catch {
            close()
            throw error
        }
    }

    /// Closes the live file; the next append reopens it.
    public func close() {
        try? handle?.close()
        handle = nil
    }

    private var live: String {
        "\(name).\(suffix)"
    }

    private func generation(_ index: Int) -> String {
        "\(name).\(index).\(suffix)"
    }

    private func openIfNeeded() throws {
        guard handle == nil else {
            return
        }
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let path = directory.appendingPathComponent(live).path
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let opened = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard fchmod(descriptor, 0o600) == 0 else {
            try? opened.close()
            throw CocoaError(.fileWriteNoPermission)
        }
        do {
            size = try opened.seekToEnd()
            handle = opened
        } catch {
            try? opened.close()
            throw error
        }
    }

    private func rotate() throws {
        close()
        let manager = FileManager.default
        for index in stride(from: Self.generations, through: 1, by: -1) {
            let target = directory.appendingPathComponent(generation(index))
            let source = directory.appendingPathComponent(
                index == 1
                    ? live
                    : generation(index - 1)
            )
            if manager.fileExists(atPath: target.path) {
                try manager.removeItem(at: target)
            }
            if manager.fileExists(atPath: source.path) {
                try manager.moveItem(at: source, to: target)
            }
        }
        size = 0
    }
}
