import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// Console stream picture settings, for the home network and the internet.
struct PictureSettingsView: View {
    /// Which connection's stream settings are shown.
    enum RouteChoice: CaseIterable {
        /// Streams to consoles on the local network.
        case home
        /// Streams to consoles reached over the internet.
        case internet

        /// The connection's name in the segmented picker.
        var title: LocalizedStringResource {
            switch self {
            case .home:
                .settingsPictureRouteHome
            case .internet:
                .settingsPictureRouteInternet
            }
        }

        /// The picture settings route whose stream profile this choice edits.
        var route: PictureSettings.Route {
            switch self {
            case .home:
                .local
            case .internet:
                .remote
            }
        }
    }

    /// The persisted console picture settings being edited.
    @Bindable var store: StoreOf<PersistedSettingFeature<PictureSettings>>
    @State private var routeChoice = RouteChoice.home

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(.settingsPictureRouteHeading).font(.subheadline.weight(.medium))
                    Text(.settingsPictureRouteFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                FocusableSegments(
                    options: RouteChoice.allCases,
                    title: \.title,
                    selection: $routeChoice
                )
            }
            PictureStreamGroup(
                height: profile(\.height),
                fps: profile(\.fps),
                bitrate: profile(\.bitrateMbps),
                automaticBitrate: profile(\.automaticBitrate),
                automaticBitrateMbps: StreamProfile.automaticBitrateMbps(
                    height: store.draft[routeChoice.route].height
                ),
                resolutions: StreamProfile.heights
            )
            PictureCodecGroup(
                ps5: routeChoice == .home
                    ? $store.draft.localPS5Codec
                    : $store.draft.remotePS5Codec,
                hdr: routeChoice == .home
                    ? $store.draft.localPS5HDR
                    : $store.draft.remotePS5HDR
            )
            PictureDisplayGroup(
                height: store.draft[routeChoice.route].height,
                fps: store.draft[routeChoice.route].fps,
                output: profile(\.upscaledOutput),
                upscaler: $store.draft.upscaler,
                presentation: $store.draft.presentationFrameRate,
                hdr: store.draft.launchCodec(
                    forPS5: true,
                    route: routeChoice.route,
                    displaySupportsHDR: DisplayDynamicRange.supportsHDR
                ) == .hevcHDR,
                fullScreen: $store.draft.fullScreenStreams
            )
            PictureColourGroup(
                adjustments: $store.draft.adjustments,
                reduceBanding: $store.draft.reduceBanding
            )
            SettingsPersistenceBanner(store.setting, subject: .settingsPicturePersistenceSubject) {
                store.send(.retry)
            }
        }
        .disabled(!store.isEditable)
        .onAppear {
            store.send(.appeared)
        }
    }

    private func profile<Value>(_ key: WritableKeyPath<StreamProfile, Value>) -> Binding<Value> {
        let profile: WritableKeyPath<PictureSettings, StreamProfile> = \PictureSettings.[routeChoice.route]
        let path: WritableKeyPath<PictureSettings, Value> = profile.appending(path: key)
        let draft: Binding<PictureSettings> = $store.draft
        return draft[dynamicMember: path]
    }
}
