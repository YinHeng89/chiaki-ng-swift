#if os(iOS)
    import ChiakiModels
    import Foundation
    import Photos

    /// Adds saved cloud captures to the device's Photos library, asking only for permission to add.
    enum CloudCapturePhotos {
        /// Adds a downloaded capture to Photos under its saved name and removes the downloaded file.
        ///
        /// - Parameters:
        ///   - downloaded: The downloaded file, which is moved into the library.
        ///   - name: The name the capture keeps in the library.
        ///   - video: Whether the capture is a video clip.
        /// - Throws: ``CloudCaptureDownloadFailure/photos(denied:)`` when access is refused or the library
        ///   rejects the file.
        static func add(
            _ downloaded: URL,
            name: CloudCaptureFileName,
            video: Bool
        ) async throws(CloudCaptureDownloadFailure) {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(name.value)
            defer {
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            }
            do {
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: downloaded, to: file)
            } catch {
                try? FileManager.default.removeItem(at: downloaded)
                throw .photos(denied: false)
            }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw .photos(denied: true)
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = name.value
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset().addResource(
                        with: video
                            ? .video
                            : .photo,
                        fileURL: file,
                        options: options
                    )
                }
            } catch {
                throw .photos(denied: false)
            }
        }
    }
#endif
