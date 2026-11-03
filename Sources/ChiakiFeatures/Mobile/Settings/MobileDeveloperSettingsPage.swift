import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// The Developer page in the touch library: logging, API capture, the log folder and the error report, with
/// developer previews, sample consoles and Takion versions in debug builds.
struct MobileDeveloperSettingsPage: View {
    @Bindable private var logging: StoreOf<PersistedSettingFeature<LogSettings>>
    private let developer: StoreOf<DeveloperSettingsFeature>
    #if DEBUG
        @Bindable private var takion: StoreOf<PersistedSettingFeature<DeveloperSettings>>
    #endif

    @AppStorage(DeveloperPreviewSetting.samplePreorders) private var samplePreorders = false
    @AppStorage(DeveloperPreviewSetting.layeredConsoleCards) private var layeredConsoleCards = true
    @AppStorage(DeveloperPreviewSetting.sampleConsoles) private var samples = SampleConsoleList()

    /// Creates the page.
    ///
    /// - Parameter settings: The settings, scoped to the log settings and the Developer tab feature.
    init(settings: StoreOf<SettingsFeature>) {
        let developer = settings.scope(state: \.developer, action: \.developer)
        logging = settings.scope(state: \.logging, action: \.logging)
        self.developer = developer
        #if DEBUG
            takion = developer.scope(state: \.takion, action: \.takion)
        #endif
    }

    var body: some View {
        form
            .onAppear {
                logging.send(.appeared)
                developer.send(.appeared)
            }
    }

    @ViewBuilder
    private var form: some View {
        #if DEBUG
            MobileSettingsForm {
                loggingGroup
                folderGroup
                loggingBanner
                previewsGroup
            } trailing: {
                sampleConsoleGroups
                Group {
                    takionGroup
                    libraryGroup
                    SettingsPersistenceBanner(takion.setting, subject: "Developer settings") {
                        takion.send(.retry)
                    }
                }
                .disabled(!takion.isEditable)
            }
        #else
            MobileSettingsForm {
                loggingGroup
                folderGroup
                loggingBanner
            }
        #endif
    }

    private var loggingGroup: some View {
        MobileSettingsGroup(
            "Logging",
            footer: "Local JSON captures with sensitive values redacted. "
                + "Stream capture starts with your next connection. "
                + "Saved in API Captures inside the log folder."
        ) {
            MobileToggleRow("Show Live Log Button", isOn: $logging.draft.showLiveLogButton)
            MobileToggleRow("Capture API Requests and Responses", isOn: $logging.draft.captureAPI)
            MobileToggleRow("Redact Identifiers in Logs", isOn: $logging.draft.redactIdentifiers)
            MobilePickerRow("Verbosity", selection: $logging.draft.level) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized).tag(level)
                }
            }
        }
        .disabled(!logging.isEditable)
    }

    private var folderGroup: some View {
        MobileSettingsGroup("Log Folder") {
            MobileValueRow("Location", value: logging.draft.directory)
            MobileButtonRow("Export Error Report…") {
                developer.send(.exportReport)
            }
            .overlay(alignment: .trailing) {
                if case .building = developer.report {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 16)
                }
            }
            if developer.report == .failed {
                errorRow("Couldn’t build the error report. Check the log folder and try again.")
            }
            if developer.logHealth == .unwritable {
                errorRow("Couldn’t write the log file. Choose a writable folder.")
            }
        }
    }

    private var loggingBanner: some View {
        SettingsPersistenceBanner(
            logging.setting,
            subject: "logging settings",
            invalid: "Couldn’t use that log folder. Check its write access and try again."
        ) {
            logging.send(.retry)
        }
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mobileRowPadding()
    }

    #if DEBUG
        private var previewsGroup: some View {
            MobileSettingsGroup("Developer Previews") {
                MobileToggleRow("Show Sample Pre-Orders", isOn: $samplePreorders)
                MobileToggleRow("Layered Console Cards", isOn: $layeredConsoleCards)
            }
        }

        @ViewBuilder
        private var sampleConsoleGroups: some View {
            ForEach(Array(samples.consoles.enumerated()), id: \.offset) { index, sample in
                MobileSettingsGroup(samples.name(at: index)) {
                    MobilePickerRow("Model", selection: Binding(
                        get: { sample.model },
                        set: { samples.setModel($0, at: index) }
                    )) {
                        ForEach(SampleConsole.Model.allCases, id: \.self) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .accessibilityIdentifier("sample-console-model-\(index)")
                    MobilePickerRow("Recently Played", selection: Binding(
                        get: { sample.shownRecentlyPlayed },
                        set: { samples.setRecentlyPlayed($0, at: index) }
                    )) {
                        ForEach(SampleConsole.RecentlyPlayed.allCases, id: \.self) { state in
                            Text(state.title).tag(state)
                        }
                    }
                    .disabled(sample.model == .ps4)
                    .accessibilityIdentifier("sample-console-recently-played-\(index)")
                    MobileButtonRow("Remove", destructive: true) {
                        samples.remove(at: index)
                    }
                    .accessibilityLabel("Remove \(samples.name(at: index))")
                    .accessibilityIdentifier("sample-console-remove-\(index)")
                }
            }
            MobileSettingsGroup(
                samples.consoles.isEmpty
                    ? "Sample Consoles"
                    : nil
            ) {
                MobileButtonRow("Add Sample Console") {
                    samples.add()
                }
                .disabled(samples.isFull)
                .accessibilityIdentifier("sample-console-add")
            }
        }

        private var takionGroup: some View {
            MobileSettingsGroup("Takion Version") {
                ForEach(TakionTarget.allCases, id: \.self) { target in
                    MobilePickerRow(target.title, selection: $takion.draft[target]) {
                        ForEach(developer.state.choices(for: target), id: \.self) { version in
                            Text(DeveloperSettings.versionTitle(
                                for: version,
                                build: developer.state.buildTakionVersion(for: target)
                            ))
                            .tag(version)
                        }
                    }
                    MobileToggleRow(
                        "Negotiate Version",
                        detail: target.title,
                        isOn: $takion.draft[negotiation: target]
                    )
                }
            }
        }

        private var libraryGroup: some View {
            MobileSettingsGroup("Cloud Library") {
                MobilePickerRow(
                    "Refresh Cooldown",
                    selection: $takion.draft.libraryRefreshCooldownMinutes
                ) {
                    ForEach(DeveloperSettings.libraryRefreshCooldownChoices, id: \.self) { minutes in
                        Text(DeveloperSettings.libraryRefreshCooldownTitle(minutes: minutes))
                            .tag(minutes)
                    }
                }
            }
        }
    #endif
}
