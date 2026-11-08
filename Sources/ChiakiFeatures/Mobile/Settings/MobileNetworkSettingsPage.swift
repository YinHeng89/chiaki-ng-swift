import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The touch Network settings page: console discovery, the NAT type check and privacy in the first column, then
/// the cloud and internet settings and console power in the second.
///
/// The cloud and internet settings show only while an account is signed in to PlayStation Network.
struct MobileNetworkSettingsPage: View {
    /// The settings feature that owns every tab's state.
    let settings: StoreOf<SettingsFeature>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings feature that owns every tab's state.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    var body: some View {
        MobileSettingsForm {
            discovery
            natType
            privacy
        } trailing: {
            if settings.psnReach == .signedIn {
                #if DEBUG
                    cloudLaunch
                #endif
                internetConnection
            } else {
                Text(.mobileNetworkSignInNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            consolePower
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var discovery: some View {
        @Bindable var network = settings.scope(state: \.network, action: \.network)
        return VStack(alignment: .leading, spacing: 8) {
            MobileSettingsGroup(
                .mobileNetworkDiscovery,
                footer: .mobileNetworkDiscoveryFooter
            ) {
                MobileToggleRow(.mobileNetworkUnicastSweep, isOn: $network.discovery.draft.unicastEnabled)
                    .accessibilityIdentifier("network-unicast-sweep")
                MobileTextEntryRow(
                    title: .mobileNetworkSubnets,
                    prompt: .mobileNetworkSubnetsPrompt,
                    text: $network.subnets,
                    kind: .address,
                    multiline: true,
                    invalid: network.subnetsRejected
                )
                .accessibilityLabel(Text(.mobileNetworkSubnetsAccessibility))
            }
            .disabled(Self.discoveryLoadFailed(network.discovery.setting))
            if network.subnetsRejected {
                Label(.mobileNetworkSubnetsRejected, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            SettingsPersistenceBanner(
                network.discovery.setting,
                subject: .mobileNetworkPersistenceSubject,
                reportsInvalid: false
            ) {
                network.send(.discovery(.retry))
            }
        }
        .onAppear {
            network.send(.appeared)
        }
    }

    private var natType: some View {
        let nat = settings.scope(state: \.natType, action: \.natType)
        return MobileSettingsGroup(.mobileNetworkNatType, footer: NatTypeSettingsView.detail(nat.check)) {
            MobileValueRow(.mobileNetworkNatType, value: Self.natValue(nat.check))
            MobileButtonRow(
                nat.isChecking
                    ? .mobileNetworkNatChecking
                    : .mobileNetworkNatCheck
            ) {
                nat.send(.checkTapped)
            }
            .disabled(nat.isChecking)
            .accessibilityIdentifier("nat-type-check")
        }
        .onDisappear {
            nat.send(.stopped)
        }
    }

    private var privacy: some View {
        @Bindable var logging = settings.scope(state: \.logging, action: \.logging)
        return MobileSettingsGroup(
            .mobileNetworkPrivacy,
            footer: .mobileNetworkPrivacyFooter
        ) {
            MobileToggleRow(.mobileNetworkStreamerMode, isOn: $logging.draft.streamerMode)
                .accessibilityIdentifier("network-streamer-mode")
                .disabled(!logging.isEditable)
        }
        .onAppear {
            logging.send(.appeared)
        }
    }

    private var cloudLaunch: some View {
        let cloud = settings.scope(state: \.cloudLaunch, action: \.cloudLaunch)
        return VStack(alignment: .leading, spacing: 8) {
            MobileSettingsGroup(.mobileNetworkCloudDatacenter, footer: CloudLaunchSettingsReducer.detail) {
                MobileToggleRow(
                    .mobileNetworkSelectDatacenter,
                    isOn: Binding(
                        get: {
                            cloud.displayedValue
                        },
                        set: {
                            cloud.send(.setSelectAtLaunch($0))
                        }
                    )
                )
                .disabled(cloud.busy || cloud.phase == .idle)
            }
            if case .failed(let message) = cloud.phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }
        }
        .onAppear {
            cloud.send(.load)
        }
    }

    private var internetConnection: some View {
        @Bindable var internet = settings.scope(state: \.internetConnection, action: \.internetConnection)
        return VStack(alignment: .leading, spacing: 8) {
            MobileSettingsGroup(
                .mobileNetworkInternetConnections,
                footer: .mobileNetworkInternetFooter
            ) {
                MobileToggleRow(.mobileNetworkAlwaysGuessPorts, isOn: $internet.draft.forcePortGuessing)
                    .accessibilityIdentifier("internet-force-port-guessing")
                MobileSliderRow(
                    title: .mobileNetworkPortGuesses,
                    verbatimValue: "\(internet.draft.portGuessCount)",
                    value: Self.portGuesses($internet.draft.portGuessCount),
                    range: Double(InternetConnectionSettings.portGuessRange.lowerBound)...Double(
                        InternetConnectionSettings.portGuessRange.upperBound
                    ),
                    step: Double(InternetConnectionSettings.portGuessStep)
                )
                .accessibilityValue(
                    Text(.mobileNetworkPortGuessesValue(count: internet.draft.portGuessCount))
                )
            }
            .disabled(!internet.isEditable)
            SettingsPersistenceBanner(internet.setting, subject: .mobileNetworkInternetPersistenceSubject) {
                internet.send(.retry)
            }
        }
        .onAppear {
            internet.send(.appeared)
        }
    }

    private var consolePower: some View {
        @Bindable var power = settings.scope(state: \.consolePower, action: \.consolePower)
        return VStack(alignment: .leading, spacing: 20) {
            MobileSettingsGroup(
                .mobileNetworkConsolePower,
                footer: ConsolePowerSettingsView.detail(power.draft.leaveAction)
            ) {
                MobilePickerRow(
                    .mobileNetworkLeaveAction,
                    selection: $power.draft.leaveAction,
                    choices: ConsoleLeaveAction.allCases
                ) { action in
                    ConsolePowerSettingsView.title(action)
                }
            }
            .disabled(!power.isEditable)
            MobileSettingsGroup(
                footer: .mobileNetworkSleepFooter
            ) {
                MobileToggleRow(
                    .mobileNetworkRestOnSleep,
                    isOn: $power.draft.restOnMacSleep
                )
                MobileToggleRow(.mobileNetworkReconnectAfterWake, isOn: $power.draft.resumeAfterWake)
            }
            .disabled(!power.isEditable)
            MobileSettingsGroup(
                footer: .mobileNetworkDropFooter
            ) {
                MobileToggleRow(.mobileNetworkReconnectAfterDrop, isOn: $power.draft.reconnectAfterDrop)
            }
            .disabled(!power.isEditable)
            SettingsPersistenceBanner(power.setting, subject: .mobileNetworkPowerPersistenceSubject) {
                power.send(.retry)
            }
        }
        .onAppear {
            power.send(.appeared)
        }
    }

    private static func discoveryLoadFailed(_ setting: PersistedSetting<DiscoverySettings>) -> Bool {
        if case .loadFailed = setting {
            return true
        }
        return false
    }

    private static func natValue(_ check: NatTypeFeature.Check) -> LocalizedStringResource {
        switch check {
        case .idle:
            .mobileNetworkNatNotChecked
        case .checking:
            .mobileNetworkNatChecking
        case .found(let type):
            .mobileNetworkNatTypeValue(type: String(type.rawValue))
        case .failed:
            .commonUnknown
        }
    }

    private static func portGuesses(_ count: Binding<Int>) -> Binding<Double> {
        Binding(
            get: {
                Double(count.wrappedValue)
            },
            set: { newValue in
                let step = Double(InternetConnectionSettings.portGuessStep)
                let snapped = Int((newValue / step).rounded() * step)
                count.wrappedValue = min(
                    max(snapped, InternetConnectionSettings.portGuessRange.lowerBound),
                    InternetConnectionSettings.portGuessRange.upperBound
                )
            }
        )
    }
}
