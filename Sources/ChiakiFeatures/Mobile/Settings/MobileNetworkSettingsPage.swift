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

    private static let signInNote = "Cloud streaming, playing over the internet and their settings need "
        + "an account signed in to PlayStation Network."

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
                Text(Self.signInNote)
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
                "Console Discovery",
                footer: "Local networks are discovered automatically. Add other subnets to search them directly. "
                    + "One subnet per line, /24–/32. Up to 1,024 addresses. Local subnets use broadcast."
            ) {
                MobileToggleRow("Unicast Sweep", isOn: $network.discovery.draft.unicastEnabled)
                    .accessibilityIdentifier("network-unicast-sweep")
                MobileTextEntryRow(
                    title: "Subnets",
                    prompt: "192.168.2.0/24",
                    text: $network.subnets,
                    kind: .address,
                    multiline: true,
                    invalid: network.subnetsRejected
                )
                .accessibilityLabel("Discovery subnets")
            }
            .disabled(Self.discoveryLoadFailed(network.discovery.setting))
            if network.subnetsRejected {
                Label(
                    "Enter IPv4 subnets from /24 to /32, up to 1,024 addresses, for example 192.168.2.0/24.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            }
            SettingsPersistenceBanner(
                network.discovery.setting,
                subject: "network settings",
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
        return MobileSettingsGroup("NAT Type", footer: NatTypeSettingsView.detail(nat.check)) {
            MobileValueRow("NAT Type", value: Self.natValue(nat.check))
            MobileButtonRow(
                nat.isChecking
                    ? "Checking"
                    : "Check NAT Type"
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
            "Privacy",
            footer: "Hides console addresses and hardware IDs on screen while you stream or record this device. "
                + "The log follows the Developer tab’s identifier setting."
        ) {
            MobileToggleRow("Streamer Mode", isOn: $logging.draft.streamerMode)
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
            MobileSettingsGroup("Cloud Datacenter", footer: CloudLaunchSettingsReducer.detail) {
                MobileToggleRow(
                    "Select Datacenter at Launch",
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
                "Internet Connections",
                footer: "Connections through the PlayStation Network guess ports only when the router needs it. "
                    + "Turn this on if Internet connections fail behind a strict router. "
                    + "More guesses can get through stricter routers but take longer to connect."
            ) {
                MobileToggleRow("Always Guess Ports", isOn: $internet.draft.forcePortGuessing)
                    .accessibilityIdentifier("internet-force-port-guessing")
                MobileSliderRow(
                    title: "Port Guesses",
                    valueText: "\(internet.draft.portGuessCount)",
                    value: Self.portGuesses($internet.draft.portGuessCount),
                    range: Double(InternetConnectionSettings.portGuessRange.lowerBound)...Double(
                        InternetConnectionSettings.portGuessRange.upperBound
                    ),
                    step: Double(InternetConnectionSettings.portGuessStep)
                )
                .accessibilityValue("\(internet.draft.portGuessCount) ports")
            }
            .disabled(!internet.isEditable)
            SettingsPersistenceBanner(internet.setting, subject: "Internet connection settings") {
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
                "Console Power",
                footer: ConsolePowerSettingsView.detail(power.draft.leaveAction)
            ) {
                MobilePickerRow("When Leaving a Console Stream", selection: $power.draft.leaveAction) {
                    ForEach(ConsoleLeaveAction.allCases, id: \.self) { action in
                        Text(ConsolePowerSettingsView.title(action)).tag(action)
                    }
                }
            }
            .disabled(!power.isEditable)
            MobileSettingsGroup(
                footer: "A console stream interrupted by sleep starts again on the same connection."
            ) {
                MobileToggleRow(
                    "Put the Console in Rest Mode When This Device Sleeps",
                    isOn: $power.draft.restOnMacSleep
                )
                MobileToggleRow("Reconnect After This Device Wakes", isOn: $power.draft.resumeAfterWake)
            }
            .disabled(!power.isEditable)
            MobileSettingsGroup(
                footer: "A console stream that loses its connection connects again, up to three times, "
                    + "instead of ending."
            ) {
                MobileToggleRow("Reconnect When the Connection Drops", isOn: $power.draft.reconnectAfterDrop)
            }
            .disabled(!power.isEditable)
            SettingsPersistenceBanner(power.setting, subject: "console power settings") {
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

    private static func natValue(_ check: NatTypeFeature.Check) -> String {
        switch check {
        case .idle:
            "Not Checked"
        case .checking:
            "Checking"
        case .found(let type):
            "Type \(type.rawValue)"
        case .failed:
            "Unknown"
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
