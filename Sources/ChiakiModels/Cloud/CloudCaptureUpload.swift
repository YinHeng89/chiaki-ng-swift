import Foundation

/// A screenshot or clip a PS5 cloud console finished uploading to the account's cloud media gallery.
public struct CloudCaptureUpload: Equatable, Sendable {
    /// The console's id for the capture, as in ``CloudCaptureThumbnail/id``.
    public let id: String

    /// The capture's id in the cloud media gallery, which the download is asked for by.
    public let galleryID: String

    /// The file extension, such as `.jpg`; empty when the console gave none.
    public let fileExtension: String

    /// The file size in bytes; zero when unknown.
    public let size: UInt64

    /// Whether it is a video clip rather than a screenshot.
    public let video: Bool

    /// When it was taken, or `nil` when the console gave no readable time.
    public let created: Date?

    /// Describes an upload.
    ///
    /// - Parameters:
    ///   - id: The console's id for the capture.
    ///   - galleryID: The capture's id in the cloud media gallery.
    ///   - fileExtension: The file extension.
    ///   - size: The file size in bytes.
    ///   - video: Whether it is a video clip.
    ///   - created: When it was taken.
    public init(
        id: String,
        galleryID: String,
        fileExtension: String,
        size: UInt64,
        video: Bool,
        created: Date?
    ) {
        self.id = id
        self.galleryID = galleryID
        self.fileExtension = fileExtension
        self.size = size
        self.video = video
        self.created = created
    }
}

/// A cloud capture waiting to be saved to a folder on this device, remembered across launches.
public struct PendingCloudCapture: Equatable, Sendable {
    /// The upload the console reported.
    public let upload: CloudCaptureUpload

    /// The account whose gallery holds the capture.
    public let account: AccountID

    /// The game's name, which names the saved file.
    public let title: String

    /// The folder the capture is saved to.
    public let folder: URL

    /// How many saves have failed so far.
    public let attempts: Int

    /// Describes a capture to save.
    ///
    /// - Parameters:
    ///   - upload: The upload the console reported.
    ///   - account: The account whose gallery holds it.
    ///   - title: The game's name.
    ///   - folder: The folder to save to.
    ///   - attempts: How many saves have failed so far.
    public init(
        upload: CloudCaptureUpload,
        account: AccountID,
        title: String,
        folder: URL,
        attempts: Int = 0
    ) {
        self.upload = upload
        self.account = account
        self.title = title
        self.folder = folder
        self.attempts = attempts
    }
}

/// Where one capture in the account's cloud media gallery can be downloaded.
///
/// The address carries its own access token, so it is kept out of logs and used at once.
public struct CloudCaptureFile: Equatable, Sendable {
    /// The address of the full file.
    public let url: URL

    /// The file type, such as `jpg` or `mp4`; empty when PSN gave none.
    public let fileType: String

    /// The size in bytes; zero when PSN gave none.
    public let size: UInt64

    /// Describes a downloadable capture.
    ///
    /// - Parameters:
    ///   - url: The address of the full file.
    ///   - fileType: The file type.
    ///   - size: The size in bytes.
    public init(url: URL, fileType: String, size: UInt64) {
        self.url = url
        self.fileType = fileType
        self.size = size
    }
}

/// The name a saved cloud capture gets: the game's name, when it was taken and its file extension, as in
/// `Astro Bot 2026-10-18 at 11.31.08.jpg`.
public struct CloudCaptureFileName: Equatable, Sendable {
    /// The characters a file name must not carry.
    private static let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)

    /// The file name.
    public let value: String

    /// Names a capture.
    ///
    /// - Parameters:
    ///   - title: The game's name; when empty the capture is named as a screenshot or video clip.
    ///   - created: When the capture was taken, in the device's time zone.
    ///   - fileExtension: The file extension, with or without its dot; when empty or not one to five letters or
    ///     digits, `jpg` or `mp4`.
    ///   - video: Whether it is a video clip.
    public init(title: String, created: Date, fileExtension: String, video: Bool) {
        let writer = DateFormatter()
        writer.locale = Locale(identifier: "en_US_POSIX")
        writer.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let cleaned = Self.shortened(String(
            title.components(separatedBy: Self.forbidden).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .drop { $0 == "." || $0.isWhitespace }
        ))
        let name = cleaned.isEmpty
            ? (video
                ? "Video clip"
                : "Screenshot")
            : cleaned
        let suffix = Self.normalized(fileExtension)
        let resolved = Self.keeps(fileExtension)
            ? suffix
            : (video
                ? "mp4"
                : "jpg")
        value = "\(name) \(writer.string(from: created)).\(resolved)"
    }

    /// The most bytes of the game's name a file name keeps, which leaves room for the date and extension within
    /// the 255-byte limit on a file name.
    private static let maximumTitleBytes = 200

    /// Whether a file extension is one a capture's name keeps: one to five ASCII letters or digits, with or
    /// without its dot, so it can't add folders to the path.
    ///
    /// - Parameter fileExtension: The file extension.
    /// - Returns: Whether the name would keep it.
    public static func keeps(_ fileExtension: String) -> Bool {
        let suffix = normalized(fileExtension)
        return (1...5).contains(suffix.count) && suffix
            .allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func normalized(_ fileExtension: String) -> String {
        (fileExtension.hasPrefix(".")
            ? String(fileExtension.dropFirst())
            : fileExtension).lowercased()
    }

    private static func shortened(_ title: String) -> String {
        var kept = title
        while kept.utf8.count > maximumTitleBytes {
            kept.removeLast()
        }
        return kept.trimmingCharacters(in: .whitespaces)
    }
}

/// Why a cloud capture could not be saved to this device.
public enum CloudCaptureDownloadFailure: Error, Equatable, Sendable {
    /// The account must sign in again before its gallery can be read.
    case signInRequired

    /// PSN did not name the capture or did not answer.
    case notFound

    /// The download failed with an HTTP status, or zero when no response arrived.
    case transfer(status: Int, signed: Bool)

    /// The folder could not be created or the file could not be moved into it.
    case folder

    /// The capture could not be added to the Photos library, because access to add was refused or the
    /// library rejected it.
    case photos(denied: Bool)

    /// PSN gave a download address that isn't https, so the capture is not fetched.
    case insecureAddress
}

/// The preview of a screenshot or clip a PS5 cloud console just took, shown in its toast.
public struct CloudCaptureThumbnail: Equatable, Sendable {
    /// The console's id for the capture.
    public let id: String

    /// Whether it is a video clip rather than a screenshot.
    public let video: Bool

    /// The preview as JPEG data; empty when the console sent none.
    public let jpeg: Data

    /// Describes a preview.
    ///
    /// - Parameters:
    ///   - id: The console's id for the capture.
    ///   - video: Whether it is a video clip.
    ///   - jpeg: The preview as JPEG data.
    public init(id: String, video: Bool, jpeg: Data) {
        self.id = id
        self.video = video
        self.jpeg = jpeg
    }
}
