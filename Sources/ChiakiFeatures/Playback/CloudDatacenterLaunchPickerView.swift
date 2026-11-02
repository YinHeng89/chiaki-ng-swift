import ChiakiModels
import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

/// A countdown panel listing cloud datacenters by ping that connects to the lowest one automatically unless
/// the player picks another.
public struct CloudDatacenterLaunchPickerView: View {
    /// The datacenters to list, with their measured ping and bandwidth and the countdown length.
    public let offer: CloudDatacenterLaunchOffer
    /// Seconds left before the lowest-ping datacenter is chosen automatically, or `nil` when no countdown
    /// runs.
    public let remaining: Int?
    /// The name of the datacenter already being connected to; while set, every row is disabled.
    public let pending: String?
    /// Called with the name of the datacenter row the player activates.
    public let choose: (String) -> Void
    /// Called when the player backs out of the picker.
    public let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.screenLayout) private var layout
    @MenuFocusState private var focused: String?
    @State private var drain: CGFloat = 1
    @State private var hostWindow: PlatformWindow?

    /// Creates a cloud datacenter launch picker view.
    ///
    /// - Parameters:
    ///   - offer: The datacenters to list, with their measured ping and bandwidth and the countdown length.
    ///   - remaining: Seconds left before the lowest-ping datacenter is chosen automatically, or `nil` when no
    ///     countdown runs.
    ///   - pending: The name of the datacenter already being connected to; while set, every row is disabled.
    ///   - choose: Called with the name of the datacenter row the player activates.
    ///   - cancel: Called when the player backs out of the picker.
    public init(
        offer: CloudDatacenterLaunchOffer,
        remaining: Int?,
        pending: String?,
        choose: @escaping (String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.offer = offer
        self.remaining = remaining
        self.pending = pending
        self.choose = choose
        self.cancel = cancel
    }

    /// The heading shown at the top of the picker.
    public static let title = "Choose a datacenter"
    /// The tallest the list grows before it scrolls, on a tall screen.
    public static let tallListHeight: CGFloat = 360
    /// The tallest the list grows before it scrolls on a short screen, which leaves the heading and the panel's
    /// margins room on a 393 point tall screen.
    public static let shortListHeight: CGFloat = 200
    /// How many rows show without scrolling on a tall screen.
    public static let tallUnscrolledRows = 7
    /// How many rows show without scrolling on a short screen.
    public static let shortUnscrolledRows = 4

    private var maximumListHeight: CGFloat {
        layout.isShort
            ? Self.shortListHeight
            : Self.tallListHeight
    }

    private var maximumUnscrolledRows: Int {
        layout.isShort
            ? Self.shortUnscrolledRows
            : Self.tallUnscrolledRows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(CloudDatacenterLaunchOffer.pingNote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 4)
            list
        }
        .padding(14)
        .frame(width: 340)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .menuFocusSection()
        .background(WindowAccessor { hostWindow = $0 })
        .task {
            await focusInitial()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLibraryContent)) { notification in
            guard let window = notification.object as? PlatformWindow,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            focused = initialFocus
        }
        .onMenuExitCommand {
            cancel()
        }
        .onChange(of: remaining, initial: true) { _, value in
            updateDrain(value)
        }
    }

    @ViewBuilder private var list: some View {
        if offer.entries.count > maximumUnscrolledRows {
            ScrollView {
                rows
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: maximumListHeight)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(offer.entries) { entry in
                row(entry)
            }
        }
    }

    private func focusInitial() async {
        focused = nil
        await Task.yield()
        focused = initialFocus
        navigator?.ensureFocus(in: hostWindow) {
            focused = nil
        } apply: {
            focused = initialFocus
        }
    }

    private var initialFocus: String? {
        offer.lowest?.name ?? offer.entries.first?.name
    }

    private var countdownText: String {
        guard let remaining else {
            return "Lowest ping"
        }
        return "Lowest ping, connecting in \(remaining) s"
    }

    private func updateDrain(_ value: Int?) {
        guard let value, pending == nil else {
            return
        }
        if reduceMotion {
            drain = CGFloat(value) / CGFloat(offer.timeoutSeconds)
            return
        }
        withAnimation(.linear(duration: 1)) {
            drain = CGFloat(max(0, value - 1)) / CGFloat(offer.timeoutSeconds)
        }
    }

    private func detail(
        _ entry: CloudDatacenterLaunchOffer.Entry,
        lowest: Bool
    ) -> (text: String, colour: Color)? {
        if let pending {
            if pending == entry.name || (lowest && pending == CloudDatacenterLaunchOffer.automaticName) {
                return ("Connecting", Palette.accent)
            }
            if lowest {
                return ("Lowest ping", Palette.accent)
            }
        } else if lowest {
            return (countdownText, Palette.accent)
        }
        if entry.highLatency {
            return ("High latency", .orange)
        }
        return nil
    }

    private func row(_ entry: CloudDatacenterLaunchOffer.Entry) -> some View {
        let lowest = offer.isLowest(entry)
        return FocusButton {
            choose(entry.name)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body.weight(lowest
                                ? .semibold
                                : .regular))
                    if let detail = detail(entry, lowest: lowest) {
                        Text(detail.text)
                            .font(.caption)
                            .foregroundStyle(detail.colour)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.pingDescription)
                        .monospacedDigit()
                        .foregroundStyle(entry.highLatency
                            ? Color.orange
                            : Color.white.opacity(0.85))
                    if let bandwidth = entry.bandwidthDescription {
                        Text(bandwidth)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
            .modifier(LaunchPickerRowSurface(
                lowest: lowest,
                focused: focused == entry.name,
                drain: lowest && pending == nil && remaining != nil
                    ? drain
                    : nil
            ))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(10))
        .menuFocused($focused, equals: entry.name)
        .environment(\.menuMove) { direction in
            move(from: entry, direction: direction)
        }
        .foregroundStyle(.white)
        .disabled(pending != nil)
        .accessibilityLabel(accessibilityLabel(entry, lowest: lowest))
    }

    private func move(from entry: CloudDatacenterLaunchOffer.Entry, direction: MenuMoveDirection) {
        guard let index = offer.entries.firstIndex(of: entry) else {
            return
        }
        switch direction {
        case .up:
            focused = offer.entries[max(0, index - 1)].name
        case .down:
            focused = offer.entries[min(offer.entries.count - 1, index + 1)].name
        case .left, .right:
            break
        @unknown default:
            break
        }
    }

    private func accessibilityLabel(_ entry: CloudDatacenterLaunchOffer.Entry, lowest: Bool) -> String {
        var label = entry.answered
            ? "\(entry.name), adjusted ping \(entry.pingDescription)"
            : "\(entry.name), \(entry.pingDescription)"
        if let bandwidth = entry.bandwidthDescription {
            label += ", measured bandwidth \(bandwidth)"
        }
        if lowest {
            label += ", lowest ping"
            if pending == nil, let remaining {
                label += ", connecting in \(remaining) seconds"
            }
        } else if entry.highLatency {
            label += ", high latency"
        }
        return label
    }
}

private struct LaunchPickerRowSurface: ViewModifier {
    let lowest: Bool
    let focused: Bool
    let drain: CGFloat?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                if let drain {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(width: proxy.size.width * drain, height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .clipShape(.rect(cornerRadius: 10))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(stroke, lineWidth: 1)
            }
            .onHover { value in
                hovering = value
            }
    }

    private var fill: Color {
        if lowest {
            return Palette.accent.opacity(0.16)
        }
        if hovering || focused {
            return Color.white.opacity(0.07)
        }
        return .clear
    }

    private var stroke: Color {
        if lowest, !focused {
            return Palette.accent.opacity(0.35)
        }
        return .clear
    }
}
