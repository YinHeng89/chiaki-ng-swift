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
                Toggle("Show live log button", isOn: $logging.draft.showLiveLogButton)
                Toggle("Capture API requests and responses", isOn: $logging.draft.captureAPI)
                Text(
                    """
                    Local JSON captures with sensitive values redacted. \
                    Stream capture starts with your next connection. \
                    Saved in API Captures inside the log folder.
                    """
                )
                .font(.callout).foregroundStyle(.secondary)
                Toggle("Redact identifiers in logs", isOn: $logging.draft.redactIdentifiers)
                SettingsRow("Verbosity") {
                    Picker("Verbosity", selection: $logging.draft.level) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue.capitalized).tag(level)
                        }
                    }
                }
            }
            .disabled(!logging.isEditable)
            #if DEBUG
                Toggle("Show sample pre-orders", isOn: $samplePreorders)
                Toggle("Layered console cards", isOn: $layeredConsoleCards)
                SampleConsolesSettingsView()
                DeveloperSettingsView(
                    store: developer.scope(state: \.takion, action: \.takion),
                    choices: developer.state.choices(for:),
                    buildVersion: developer.state.buildTakionVersion(for:)
                )
            #endif
            Text("Log folder").font(.headline)
            Text(logging.draft.directory).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                #if os(macOS)
                    FocusButton("Choose folder…", action: chooseFolder)
                        .glassControlStyle()
                        .disabled(!logging.isEditable)
                    FocusButton("Show in Finder") {
                        FolderAccess.open(logging.draft.directory, bookmark: logging.draft.directoryBookmark)
                        NSWorkspace.shared.open(URL(
                            fileURLWithPath: logging.draft.directory,
                            isDirectory: true
                        ))
                    }
                    .glassControlStyle()
                #endif
                FocusButton("Export error report…") {
                    developer.send(.exportReport)
                }
                .glassControlStyle()
                if case .building = developer.report {
                    ProgressView().controlSize(.small)
                }
            }
            if developer.report == .failed {
                Text("Couldn’t build the error report. Check the log folder and try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if developer.logHealth == .unwritable {
                Text("Couldn’t write the log file. Choose a writable folder.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            SettingsPersistenceBanner(
                logging.setting,
                subject: "logging settings",
                invalid: "Couldn’t use that log folder. Check its write access and try again."
            ) {
                logging.send(.retry)
            }
        }
        .onAppear {
            logging.send(.appeared)
            developer.send(.appeared)
        }
    }

    #if os(macOS)
        private func chooseFolder() {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Use for logs"
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
            Text("Takion version").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(TakionTarget.allCases.enumerated()), id: \.element) { index, target in
                    if index > 0 {
                        Divider()
                    }
                    SettingsRow(target.title) {
                        Picker(target.title, selection: $store.draft[target]) {
                            ForEach(choices(target), id: \.self) { version in
                                Text(DeveloperSettings.versionTitle(
                                    for: version,
                                    build: buildVersion(target)
                                ))
                                .tag(version)
                            }
                        }
                    }
                    SettingsRow("Negotiate version") {
                        Toggle("Negotiate version", isOn: $store.draft[negotiation: target])
                    }
                }
            }
            Text("Cloud library").font(.headline)
            SettingsRow("Refresh cooldown") {
                Picker("Refresh cooldown", selection: $store.draft.libraryRefreshCooldownMinutes) {
                    ForEach(DeveloperSettings.libraryRefreshCooldownChoices, id: \.self) { minutes in
                        Text(DeveloperSettings.libraryRefreshCooldownTitle(minutes: minutes))
                            .tag(minutes)
                    }
                }
            }
            SettingsPersistenceBanner(store.setting, subject: "Developer settings") {
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
            Text("Sample consoles").font(.headline)
            ForEach(Array(samples.consoles.enumerated()), id: \.offset) { index, sample in
                VStack(spacing: 0) {
                    SettingsRow(samples.name(at: index)) {
                        Picker("Model", selection: Binding(
                            get: { sample.model },
                            set: { samples.setModel($0, at: index) }
                        )) {
                            ForEach(SampleConsole.Model.allCases, id: \.self) { model in
                                Text(model.title).tag(model)
                            }
                        }
                        .accessibilityIdentifier("sample-console-model-\(index)")
                    }
                    SettingsRow("Recently played") {
                        Picker("Recently played", selection: Binding(
                            get: { sample.shownRecentlyPlayed },
                            set: { samples.setRecentlyPlayed($0, at: index) }
                        )) {
                            ForEach(SampleConsole.RecentlyPlayed.allCases, id: \.self) { state in
                                Text(state.title).tag(state)
                            }
                        }
                        .disabled(sample.model == .ps4)
                        .accessibilityIdentifier("sample-console-recently-played-\(index)")
                    }
                    SettingsRow("Remove") {
                        FocusButton("Remove", role: .destructive) {
                            samples.remove(at: index)
                        }
                        .glassControlStyle()
                        .accessibilityLabel("Remove \(samples.name(at: index))")
                        .accessibilityIdentifier("sample-console-remove-\(index)")
                    }
                    Divider()
                        .padding(.top, 8)
                }
            }
            FocusButton("Add sample console") {
                samples.add()
            }
            .glassControlStyle()
            .disabled(samples.isFull)
            .accessibilityIdentifier("sample-console-add")
        }
    }
}
