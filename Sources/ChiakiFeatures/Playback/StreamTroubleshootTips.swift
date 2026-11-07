import MenuFocus
import SwiftUI

/// A topic of the stream menu's connection tips.
public enum StreamTroubleshootTopic: String, CaseIterable, Sendable {
    /// Tips for a weak Wi-Fi signal.
    case wifi = "Wi-Fi"
    /// Tips for a slow or unstable connection.
    case connectionSpeed = "Connection speed"
    /// Tips for a resolution that keeps changing.
    case resolution = "Resolution"

    /// The topic's name in the choice of topics.
    var title: LocalizedStringResource {
        switch self {
        case .wifi:
            .playbackTipsTopicWifi
        case .connectionSpeed:
            .playbackTipsTopicConnectionSpeed
        case .resolution:
            .playbackTipsTopicResolution
        }
    }

    /// The heading above the topic's tips.
    var heading: LocalizedStringResource {
        switch self {
        case .wifi:
            .playbackTipsWifiHeading
        case .connectionSpeed:
            .playbackTipsConnectionSpeedHeading
        case .resolution:
            .playbackTipsResolutionHeading
        }
    }

    /// The topic's tips, one paragraph each.
    var tips: [LocalizedStringResource] {
        switch self {
        case .wifi:
            [
                Self.moveCloser,
                .playbackTipsWifiBand,
                .playbackTipsWifiRestartRouter,
                .playbackTipsWifiInterference
            ]
        case .connectionSpeed:
            [
                .playbackTipsConnectionSpeedOtherDevices,
                .playbackTipsConnectionSpeedUploads
            ]
        case .resolution:
            [
                .playbackTipsResolutionNetwork,
                .playbackTipsResolutionLower
            ]
        }
    }

    private static var moveCloser: LocalizedStringResource {
        #if os(macOS)
            .playbackTipsWifiMoveCloserMac
        #else
            .playbackTipsWifiMoveCloser
        #endif
    }
}

/// The connection tips at the foot of the stream menu's Statistics panel: a choice of topics and the chosen
/// topic's tips.
struct StreamMenuTroubleshootControls: View {
    /// The topic whose tips show.
    @Binding var topic: StreamTroubleshootTopic
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus.
    let focusedControl: StreamMenuControl?

    /// The controls a controller moves through, one per topic.
    static let controls = StreamTroubleshootTopic.allCases.map {
        StreamMenuControl.troubleshootTopic($0.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(.playbackTipsTitle).font(.headline)
            StreamMenuChoiceRow(
                options: StreamTroubleshootTopic.allCases,
                title: \.title,
                selection: $topic,
                focus: focus,
                focusedControl: focusedControl,
                control: { .troubleshootTopic($0.rawValue) }
            )
            VStack(alignment: .leading, spacing: 10) {
                Text(topic.heading).font(.subheadline.weight(.semibold))
                ForEach(topic.tips.indices, id: \.self) { index in
                    Text(topic.tips[index])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
