import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// Cloud stream picture settings, for PS5 cloud and PS3 and PS4 cloud streams.
struct CloudPictureSettingsView: View {
    /// Which cloud service's settings are shown.
    enum Service: CaseIterable {
        /// PS5 cloud streaming.
        case psCloud
        /// PS3 and PS4 cloud streaming through PlayStation Now.
        case psNow

        /// The service's name in the segmented picker.
        var title: String {
            switch self {
            case .psCloud:
                "PS5 cloud"
            case .psNow:
                "PS3 and PS4 cloud"
            }
        }
    }

    /// The cloud picture feature holding the saved settings and the measured bandwidth.
    let store: StoreOf<CloudPictureSettingsFeature>
    @State private var service = Service.psCloud

    var body: some View {
        CloudPictureSettingsForm(
            store: store.scope(state: \.picture, action: \.picture),
            service: $service,
            savedBandwidth: store.measuredBandwidth
        )
        .onAppear {
            store.send(.appeared)
        }
    }
}

/// The controls of the cloud picture settings, bound to the saved settings.
private struct CloudPictureSettingsForm: View {
    /// The persisted cloud picture settings being edited.
    @Bindable var store: StoreOf<PersistedSettingFeature<CloudPictureSettings>>
    /// The cloud service whose resolution, bitrate and output controls are shown.
    @Binding var service: CloudPictureSettingsView.Service
    /// The connection bandwidth measured at an earlier launch, used for the automatic PS5 cloud bitrate when
    /// present.
    let savedBandwidth: CloudSavedBandwidth?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            FocusableSegments(
                options: CloudPictureSettingsView.Service.allCases,
                title: \.title,
                selection: $service
            )
            PictureStreamGroup(
                height: service == .psCloud
                    ? $store.draft.psCloudHeight
                    : $store.draft.psNowHeight,
                fps: .constant(60),
                bitrate: service == .psCloud
                    ? $store.draft.psCloudBitrateMbps
                    : $store.draft.psNowBitrateMbps,
                automaticBitrate: service == .psCloud
                    ? $store.draft.psCloudAutomaticBitrate
                    : $store.draft.psNowAutomaticBitrate,
                automaticBitrateMbps: automaticBitrateMbps,
                automaticCaption: service == .psCloud
                    ? measuredCaption
                    : nil,
                resolutions: service == .psCloud
                    ? CloudPictureSettings.psCloudHeights
                    : CloudPictureSettings.psNowHeights,
                fixedFrameRate: true
            )
            if service == .psCloud {
                PictureDynamicRangeGroup(hdr: $store.draft.hdr, height: store.draft.psCloudHeight)
                CloudQualityGroup(quality: $store.draft.psCloudQuality)
                CloudCapturesGroup(
                    saving: $store.draft.captureSaving, folder: $store.draft.captureFolder,
                    bookmark: $store.draft.captureFolderBookmark
                )
            }
            PictureDisplayGroup(
                height: service == .psCloud
                    ? store.draft.psCloudHeight
                    : store.draft.psNowHeight,
                fps: 60,
                output: service == .psCloud
                    ? $store.draft.upscaledOutput
                    : $store.draft.psNowUpscaledOutput,
                upscaler: $store.draft.upscaler,
                presentation: $store.draft.presentationFrameRate
            )
            PictureColourGroup(
                adjustments: $store.draft.adjustments,
                reduceBanding: $store.draft.reduceBanding
            )
            SettingsPersistenceBanner(store.setting, subject: "cloud picture settings") {
                store.send(.retry)
            }
        }
        .disabled(!store.isEditable)
    }

    private var automaticBitrateMbps: Int {
        guard service == .psCloud else {
            return CloudPictureSettings.automaticBitrateMbps(height: store.draft.psNowHeight)
        }
        return savedBandwidth.map { $0.kbps / 1000 }
            ?? CloudPictureSettings.automaticBitrateMbps(height: store.draft.psCloudHeight)
    }

    private var measuredCaption: String {
        if let savedBandwidth {
            return savedBandwidth.caption(now: Date())
        }
        let fallback = CloudPictureSettings.automaticBitrateMbps(height: store.draft.psCloudHeight)
        return "Measures your connection at launch, or uses \(fallback) Mbps if it cannot."
    }
}

/// A settings card choosing when PS5 cloud screenshots and clips are saved to this Mac, and where, or on iOS
/// when they are added to the Photos library.
public struct CloudCapturesGroup: View {
    /// When captures are saved.
    @Binding public var saving: CloudCaptureSaving
    /// The chosen folder, or empty for the default one.
    @Binding public var folder: String
    /// The bookmark that reaches the chosen folder again after a relaunch, or `nil` for the default one.
    @Binding public var bookmark: Data?

    /// Creates a cloud captures group.
    ///
    /// - Parameters:
    ///   - saving: When captures are saved.
    ///   - folder: The chosen folder, or empty for the default one.
    ///   - bookmark: The bookmark for the chosen folder, or `nil` for the default one.
    public init(saving: Binding<CloudCaptureSaving>, folder: Binding<String>, bookmark: Binding<Data?>) {
        _saving = saving
        _folder = folder
        _bookmark = bookmark
    }

    public var body: some View {
        SettingsCard("Captures") {
            SettingsRow(saveTitle, detail: detail) {
                Picker(saveTitle, selection: $saving) {
                    ForEach(CloudCaptureSaving.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }
            if saving != .never {
                Text(destination)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                #if os(macOS)
                    HStack {
                        FocusButton("Choose folder…") {
                            chooseFolder()
                        }
                        .glassControlStyle()
                        FocusButton("Show in Finder") {
                            showFolder()
                        }
                        .glassControlStyle()
                    }
                #endif
            }
        }
    }

    private var detail: String {
        switch saving {
        case .followPlayStation:
            "Follows the download setting in your PS5 capture settings."
        case .always:
            "Downloads every screenshot and video clip once the console finishes uploading it."
        case .never:
            "Captures stay in your PlayStation cloud media gallery."
        }
    }

    private var saveTitle: String {
        #if os(macOS)
            "Save captures to this Mac"
        #else
            "Save captures to this device"
        #endif
    }

    private var destination: String {
        #if os(macOS)
            directory.path
        #else
            "Captures are added to your Photos library."
        #endif
    }

    private var directory: URL {
        folder.isEmpty
            ? CloudPictureSettings.defaultCaptureFolder
            : URL(fileURLWithPath: folder, isDirectory: true)
    }

    #if os(macOS)
        private func chooseFolder() {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Use for captures"
            panel.directoryURL = directory
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                folder = url.path
                bookmark = FolderAccess.bookmark(for: url)
            }
        }

        private func showFolder() {
            FolderAccess.open(folder, bookmark: bookmark)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            PlatformWorkspace.open(directory)
        }
    #endif
}

extension CloudCaptureSaving {
    /// The label shown for this choice in the settings picker.
    public var title: String {
        switch self {
        case .followPlayStation:
            "Follow PlayStation"
        case .always:
            "Always"
        case .never:
            "Never"
        }
    }
}

/// A settings card choosing whether PS5 cloud streams favour picture quality or steady performance.
public struct CloudQualityGroup: View {
    /// The chosen stream quality.
    @Binding public var quality: CloudStreamQuality

    /// Creates a cloud quality group.
    ///
    /// - Parameter quality: The chosen stream quality.
    public init(quality: Binding<CloudStreamQuality>) {
        _quality = quality
    }

    public var body: some View {
        SettingsCard("Stream quality") {
            SettingsRow("Quality", detail: detail) {
                Picker("Quality", selection: $quality) {
                    ForEach(CloudStreamQuality.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }
        }
    }

    private var detail: String {
        switch quality {
        case .high:
            "Asks the service for higher picture quality, which uses more data."
        case .stable:
            "Asks the service to favour steady performance over picture quality."
        }
    }
}

extension CloudStreamQuality {
    /// The label shown for this quality in the settings picker.
    public var title: String {
        switch self {
        case .high:
            "High quality"
        case .stable:
            "Stable"
        }
    }
}
