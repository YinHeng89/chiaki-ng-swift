import ChiakiModels
import ComposableArchitecture
import MenuFocus
import SwiftUI

/// The Picture tab: console or cloud picture settings.
struct PictureSettingsContainerView: View {
    /// Which streams' settings are shown.
    enum StreamKind: CaseIterable {
        /// Console streams over the home network or the internet.
        case console
        /// Cloud streams.
        case cloud

        /// The stream kind's name in the segmented picker.
        var title: String {
            switch self {
            case .console:
                "Console"
            case .cloud:
                "Cloud"
            }
        }
    }

    /// The persisted console picture settings.
    let console: StoreOf<PersistedSettingFeature<PictureSettings>>
    /// The cloud picture feature.
    let cloud: StoreOf<CloudPictureSettingsFeature>
    /// Whether any account is signed in to PlayStation Network; without one only console settings are shown.
    var psnReach = PSNReach.signedIn
    @State private var streamKind = StreamKind.console

    private var shownKind: StreamKind {
        psnReach == .signedIn
            ? streamKind
            : .console
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center) {
                Text("Picture").font(.title.weight(.semibold))
                Spacer(minLength: 16)
                if psnReach == .signedIn {
                    FocusableSegments(
                        options: StreamKind.allCases,
                        title: \.title,
                        selection: $streamKind
                    )
                }
            }
            switch shownKind {
            case .console:
                PictureSettingsView(store: console)
            case .cloud:
                CloudPictureSettingsView(store: cloud)
            }
        }
    }
}
