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

    /// The heading above the topic's tips.
    var heading: String {
        switch self {
        case .wifi:
            "If your Wi-Fi signal is weak"
        case .connectionSpeed:
            "If your connection is unstable"
        case .resolution:
            "If your resolution is unstable"
        }
    }

    /// The topic's tips, one paragraph each.
    var tips: [String] {
        switch self {
        case .wifi:
            [
                "Move \(Self.device) and your wireless router closer together for the strongest signal. Doors, "
                    + "walls and cabinets between them weaken the connection.",
                "If your Wi-Fi uses 2.4 GHz, try a 5 GHz connection, or the other way round. This can reduce "
                    + "interference.",
                "Restart your modem and router to set up the internet connection again. They can take a couple "
                    + "of minutes to restart fully.",
                "Other nearby Wi-Fi networks and mobile hotspots can affect your connection. Check whether your "
                    + "router has features that reduce interference."
            ]
        case .connectionSpeed:
            [
                "Other devices on the same network, such as phones or laptops, can slow your connection. Try "
                    + "turning some of them off.",
                "Sending data over the internet, such as uploading photos or video clips, can slow your upload "
                    + "speed."
            ]
        case .resolution:
            [
                "Resolution depends on the quality of your network connection. See Wi-Fi and Connection speed "
                    + "for more tips.",
                "To make the stream steadier, choose a lower resolution such as 720p in the Stream panel."
            ]
        }
    }

    private static var device: String {
        #if os(macOS)
            "this Mac"
        #else
            "this device"
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
            Text("Connection tips").font(.headline)
            StreamMenuChoiceRow(
                options: StreamTroubleshootTopic.allCases,
                title: \.rawValue,
                selection: $topic,
                focus: focus,
                focusedControl: focusedControl,
                control: { .troubleshootTopic($0.rawValue) }
            )
            VStack(alignment: .leading, spacing: 10) {
                Text(topic.heading).font(.subheadline.weight(.semibold))
                ForEach(topic.tips, id: \.self) { tip in
                    Text(tip)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
