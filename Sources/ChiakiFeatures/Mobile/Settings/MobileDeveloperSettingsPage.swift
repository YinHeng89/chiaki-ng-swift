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
                    SettingsPersistenceBanner(takion.setting, subject: .mobileDeveloperPersistenceSubject) {
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
            .mobileDeveloperLogging,
            footer: .mobileDeveloperLoggingFooter
        ) {
            MobileToggleRow(.mobileDeveloperShowLiveLog, isOn: $logging.draft.showLiveLogButton)
            MobileToggleRow(.mobileDeveloperCaptureAPI, isOn: $logging.draft.captureAPI)
            MobileToggleRow(.mobileDeveloperRedactIdentifiers, isOn: $logging.draft.redactIdentifiers)
            MobilePickerRow(
                .mobileDeveloperVerbosity,
                selection: $logging.draft.level,
                choices: LogLevel.allCases,
                verbatimLabel: { level in
                    level.rawValue.capitalized
                }
            )
        }
        .disabled(!logging.isEditable)
    }

    private var folderGroup: some View {
        MobileSettingsGroup(.mobileDeveloperLogFolder) {
            MobileValueRow(.mobileDeveloperLocation, verbatim: logging.draft.directory)
            MobileButtonRow(.mobileDeveloperExportReport) {
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
                errorRow(.mobileDeveloperReportFailed)
            }
            if developer.logHealth == .unwritable {
                errorRow(.mobileDeveloperLogUnwritable)
            }
        }
    }

    private var loggingBanner: some View {
        SettingsPersistenceBanner(
            logging.setting,
            subject: .mobileDeveloperLoggingPersistenceSubject,
            invalid: .mobileDeveloperLoggingInvalid
        ) {
            logging.send(.retry)
        }
    }

    private func errorRow(_ message: LocalizedStringResource) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mobileRowPadding()
    }

    #if DEBUG
        private var previewsGroup: some View {
            MobileSettingsGroup(.mobileDeveloperPreviews) {
                MobileToggleRow(.mobileDeveloperSamplePreorders, isOn: $samplePreorders)
                MobileToggleRow(.mobileDeveloperLayeredCards, isOn: $layeredConsoleCards)
            }
        }

        @ViewBuilder
        private var sampleConsoleGroups: some View {
            ForEach(Array(samples.consoles.enumerated()), id: \.offset) { index, sample in
                MobileSettingsGroup(verbatim: samples.name(at: index)) {
                    MobilePickerRow(.mobileDeveloperModel, selection: Binding(
                        get: { sample.model },
                        set: { samples.setModel($0, at: index) }
                    ),
                    choices: SampleConsole.Model.allCases) { model in
                        model.title
                    }
                    .accessibilityIdentifier("sample-console-model-\(index)")
                    MobilePickerRow(.mobileDeveloperRecentlyPlayed, selection: Binding(
                        get: { sample.shownRecentlyPlayed },
                        set: { samples.setRecentlyPlayed($0, at: index) }
                    ),
                    choices: SampleConsole.RecentlyPlayed.allCases) { state in
                        state.title
                    }
                    .disabled(sample.model == .ps4)
                    .accessibilityIdentifier("sample-console-recently-played-\(index)")
                    MobileButtonRow(.commonRemove, destructive: true) {
                        samples.remove(at: index)
                    }
                    .accessibilityLabel(Text(.mobileDeveloperRemoveSample(name: samples.name(at: index))))
                    .accessibilityIdentifier("sample-console-remove-\(index)")
                }
            }
            MobileSettingsGroup(
                samples.consoles.isEmpty
                    ? .mobileDeveloperSampleConsoles
                    : nil
            ) {
                MobileButtonRow(.mobileDeveloperAddSample) {
                    samples.add()
                }
                .disabled(samples.isFull)
                .accessibilityIdentifier("sample-console-add")
            }
        }

        private var takionGroup: some View {
            MobileSettingsGroup(.mobileDeveloperTakionVersion) {
                ForEach(TakionTarget.allCases, id: \.self) { target in
                    MobilePickerRow(
                        target.title,
                        selection: $takion.draft[target],
                        choices: developer.state.choices(for: target)
                    ) { version in
                        DeveloperSettings.versionTitle(
                            for: version,
                            build: developer.state.buildTakionVersion(for: target)
                        )
                    }
                    MobileToggleRow(
                        .mobileDeveloperNegotiateVersion,
                        detail: target.title,
                        isOn: $takion.draft[negotiation: target]
                    )
                }
            }
        }

        private var libraryGroup: some View {
            MobileSettingsGroup(.mobileDeveloperCloudLibrary) {
                MobilePickerRow(
                    .mobileDeveloperRefreshCooldown,
                    selection: $takion.draft.libraryRefreshCooldownMinutes,
                    choices: DeveloperSettings.libraryRefreshCooldownChoices
                ) { minutes in
                    DeveloperSettings.libraryRefreshCooldownTitle(minutes: minutes)
                }
            }
        }
    #endif
}
