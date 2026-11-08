import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The Developer tab: logging, API capture and the error report, with developer previews and Takion versions in
/// debug builds. Release builds call it the Logging tab.
public struct LoggingSettingsView: View {
    /// The persisted log settings whose toggles, verbosity and folder are edited and saved.
    @Bindable public var logging: StoreOf<PersistedSettingFeature<LogSettings>>
    /// The Developer tab feature that owns the Takion version settings and the error report export.
    public let developer: StoreOf<DeveloperSettingsFeature>

    /// Creates a logging settings view.
    ///
    /// - Parameters:
    ///   - logging: The persisted log settings whose toggles, verbosity and folder are edited and saved.
    ///   - developer: The Developer tab feature that owns the Takion version settings and the error report export.
    public init(
        logging: StoreOf<PersistedSettingFeature<LogSettings>>,
        developer: StoreOf<DeveloperSettingsFeature>
    ) {
        self.logging = logging
        self.developer = developer
    }

    @AppStorage(DeveloperPreviewSetting.samplePreorders) private var samplePreorders = false
    @AppStorage(DeveloperPreviewSetting.layeredConsoleCards) private var layeredConsoleCards = true

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                Toggle(.settingsDeveloperShowLiveLog, isOn: $logging.draft.showLiveLogButton)
                Toggle(.settingsDeveloperCaptureApi, isOn: $logging.draft.captureAPI)
                Text(.settingsDeveloperCaptureApiDetail)
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(.settingsDeveloperRedactIdentifiers, isOn: $logging.draft.redactIdentifiers)
                SettingsRow(.settingsDeveloperVerbosity) {
                    Picker(selection: $logging.draft.level) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(Self.title(of: level)).tag(level)
                        }
                    } label: {
                        Text(.settingsDeveloperVerbosity)
                    }
                }
            }
            .disabled(!logging.isEditable)
            #if DEBUG
                Toggle(.settingsDeveloperSamplePreorders, isOn: $samplePreorders)
                Toggle(.settingsDeveloperLayeredConsoleCards, isOn: $layeredConsoleCards)
                SampleConsolesSettingsView()
                DeveloperSettingsView(
                    store: developer.scope(state: \.takion, action: \.takion),
                    choices: developer.state.choices(for:),
                    buildVersion: developer.state.buildTakionVersion(for:)
                )
            #endif
            Text(.settingsDeveloperLogFolder).font(.headline)
            Text(logging.draft.directory).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                #if os(macOS)
                    FocusButton(.settingsDeveloperChooseFolder, action: chooseFolder)
                        .glassControlStyle()
                        .disabled(!logging.isEditable)
                    FocusButton(.settingsDeveloperShowInFinder) {
                        FolderAccess.open(logging.draft.directory, bookmark: logging.draft.directoryBookmark)
                        NSWorkspace.shared.open(URL(
                            fileURLWithPath: logging.draft.directory,
                            isDirectory: true
                        ))
                    }
                    .glassControlStyle()
                #endif
                FocusButton(.settingsDeveloperExportReport) {
                    developer.send(.exportReport)
                }
                .glassControlStyle()
                if case .building = developer.report {
                    ProgressView().controlSize(.small)
                }
            }
            if developer.report == .failed {
                Text(.settingsDeveloperReportBuildFailed)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if developer.logHealth == .unwritable {
                Text(.settingsDeveloperLogUnwritable)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            SettingsPersistenceBanner(
                logging.setting,
                subject: .settingsDeveloperLoggingSubject,
                invalid: .settingsDeveloperLogFolderInvalid
            ) {
                logging.send(.retry)
            }
        }
        .onAppear {
            logging.send(.appeared)
            developer.send(.appeared)
        }
    }

    private static func title(of level: LogLevel) -> LocalizedStringResource {
        switch level {
        case .off:
            .commonOff
        case .error:
            .settingsDeveloperLevelError
        case .warning:
            .settingsDeveloperLevelWarning
        case .info:
            .settingsDeveloperLevelInfo
        case .debug:
            .settingsDeveloperLevelDebug
        }
    }

    #if os(macOS)
        private func chooseFolder() {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = String(localized: .settingsDeveloperUseForLogs)
            panel.directoryURL = URL(fileURLWithPath: logging.draft.directory, isDirectory: true)
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                var value = logging.draft
                value.directory = url.path
                value.directoryBookmark = FolderAccess.bookmark(for: url)
                logging.send(.edit(value))
            }
        }
    #endif
}

/// The Takion version each connection kind negotiates, and how long a cloud library refresh blocks the next one.
public struct DeveloperSettingsView: View {
    /// The persisted developer settings whose Takion and library refresh choices are edited and saved.
    @Bindable public var store: StoreOf<PersistedSettingFeature<DeveloperSettings>>
    /// Returns the versions offered for a connection kind, automatic first.
    public let choices: (TakionTarget) -> [UInt32]
    /// Returns the version this build negotiates for a connection kind, shown beside the automatic choice.
    public let buildVersion: (TakionTarget) -> UInt32

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(.settingsDeveloperTakionVersion).font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(TakionTarget.allCases.enumerated()), id: \.element) { index, target in
                    if index > 0 {
                        Divider()
                    }
                    SettingsRow(target.title) {
                        Picker(selection: $store.draft[target]) {
                            ForEach(choices(target), id: \.self) { version in
                                Text(DeveloperSettings.versionTitle(
                                    for: version,
                                    build: buildVersion(target)
                                ))
                                .tag(version)
                            }
                        } label: {
                            Text(target.title)
                        }
                    }
                    SettingsRow(.settingsDeveloperNegotiateVersion) {
                        Toggle(.settingsDeveloperNegotiateVersion, isOn: $store.draft[negotiation: target])
                    }
                }
            }
            Text(.settingsDeveloperCloudLibrary).font(.headline)
            SettingsRow(.settingsDeveloperRefreshCooldown) {
                Picker(selection: $store.draft.libraryRefreshCooldownMinutes) {
                    ForEach(DeveloperSettings.libraryRefreshCooldownChoices, id: \.self) { minutes in
                        Text(DeveloperSettings.libraryRefreshCooldownTitle(minutes: minutes))
                            .tag(minutes)
                    }
                } label: {
                    Text(.settingsDeveloperRefreshCooldown)
                }
            }
            SettingsPersistenceBanner(store.setting, subject: .settingsDeveloperDeveloperSubject) {
                store.send(.retry)
            }
        }
        .disabled(!store.isEditable)
    }
}

/// A debug editor for the simulated consoles shown in the library: add or remove sample consoles and set each
/// one's model and recently played state, kept in app storage.
public struct SampleConsolesSettingsView: View {
    @AppStorage(DeveloperPreviewSetting.sampleConsoles) private var samples = SampleConsoleList()

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.settingsDeveloperSampleConsoles).font(.headline)
            ForEach(Array(samples.consoles.enumerated()), id: \.offset) { index, sample in
                VStack(spacing: 0) {
                    SettingsRow(verbatim: samples.name(at: index)) {
                        Picker(selection: Binding(
                            get: { sample.model },
                            set: { samples.setModel($0, at: index) }
                        )) {
                            ForEach(SampleConsole.Model.allCases, id: \.self) { model in
                                Text(model.title).tag(model)
                            }
                        } label: {
                            Text(.settingsDeveloperSampleModel)
                        }
                        .accessibilityIdentifier("sample-console-model-\(index)")
                    }
                    SettingsRow(.settingsDeveloperSampleRecentlyPlayed) {
                        Picker(selection: Binding(
                            get: { sample.shownRecentlyPlayed },
                            set: { samples.setRecentlyPlayed($0, at: index) }
                        )) {
                            ForEach(SampleConsole.RecentlyPlayed.allCases, id: \.self) { state in
                                Text(state.title).tag(state)
                            }
                        } label: {
                            Text(.settingsDeveloperSampleRecentlyPlayed)
                        }
                        .disabled(sample.model == .ps4)
                        .accessibilityIdentifier("sample-console-recently-played-\(index)")
                    }
                    SettingsRow(.commonRemove) {
                        FocusButton(.commonRemove, role: .destructive) {
                            samples.remove(at: index)
                        }
                        .glassControlStyle()
                        .accessibilityLabel(.settingsDeveloperRemoveSample(console: samples.name(at: index)))
                        .accessibilityIdentifier("sample-console-remove-\(index)")
                    }
                    Divider()
                        .padding(.top, 8)
                }
            }
            FocusButton(.settingsDeveloperAddSample) {
                samples.add()
            }
            .glassControlStyle()
            .disabled(samples.isFull)
            .accessibilityIdentifier("sample-console-add")
        }
    }
}
