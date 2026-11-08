import ChiakiModels
import MenuFocus
import SwiftUI

/// Says why a settings pane's values could not be loaded or saved, with a way to try again.
///
/// Shows nothing while the setting loads, saves or is saved.
public struct SettingsPersistenceBanner: View {
    private let message: LocalizedStringResource?
    private let retries: Bool
    private let retry: () -> Void

    /// Creates the banner for a setting.
    ///
    /// - Parameters:
    ///   - setting: The setting's workflow.
    ///   - subject: What the settings are, in lower case, such as "interface settings".
    ///   - invalid: What to do about a value that does not validate.
    ///   - reportsInvalid: Whether an invalid value is reported here; `false` when the pane explains it.
    ///   - retry: Loads or saves again.
    public init<Value>(
        _ setting: PersistedSetting<Value>,
        subject: LocalizedStringResource,
        invalid: LocalizedStringResource? = nil,
        reportsInvalid: Bool = true,
        retry: @escaping () -> Void
    ) {
        let subject = String(localized: subject)
        switch setting {
        case .unloaded, .loading, .ready, .saving:
            message = nil
            retries = false
        case .loadFailed:
            message = .settingsBannerLoadFailed(subject: subject)
            retries = true
        case .saveFailed(_, _, .unavailable):
            message = .settingsBannerSaveFailed(subject: subject)
            retries = true
        case .saveFailed(_, _, .invalid):
            message = reportsInvalid
                ? invalid ?? .settingsBannerInvalid(subject: subject)
                : nil
            retries = false
        }
        self.retry = retry
    }

    /// The banner.
    public var body: some View {
        if let message {
            HStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                if retries {
                    FocusButton(.commonTryAgain, action: retry)
                        .glassControlStyle()
                }
            }
        }
    }
}
