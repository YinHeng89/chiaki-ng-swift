import ChiakiModels
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// A full-width glass button on a Kakusan card.
public struct KakusanActionButton: View {
    /// The button's title.
    public let title: String
    /// Whether the button is the card's main action.
    public var prominent: Bool
    /// Whether the button ends something.
    public var destructive: Bool
    /// Whether controller navigation selected the button.
    public let focused: Bool
    /// What the button does.
    public let perform: () -> Void

    /// Creates a Kakusan action button.
    ///
    /// - Parameters:
    ///   - title: The button's title.
    ///   - prominent: Whether the button is the card's main action.
    ///   - destructive: Whether the button ends something.
    ///   - focused: Whether controller navigation selected the button.
    ///   - perform: What the button does.
    public init(
        title: String,
        prominent: Bool = false,
        destructive: Bool = false,
        focused: Bool,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.prominent = prominent
        self.destructive = destructive
        self.focused = focused
        self.perform = perform
    }

    public var body: some View {
        Group {
            if prominent {
                FocusButton(role: destructive
                    ? .destructive
                    : nil, action: perform) {
                        Text(title)
                            .frame(maxWidth: .infinity)
                    }
                    .glassProminentControlStyle()
            } else {
                FocusButton(role: destructive
                    ? .destructive
                    : nil, action: perform) {
                        Text(title)
                            .frame(maxWidth: .infinity)
                    }
                    .glassControlStyle()
            }
        }
        .controlSize(.large)
        .environment(\.menuItemFocused, focused)
    }
}

/// A Kakusan card's heading: a symbol in a glass circle and a title.
public struct KakusanHeader: View {
    /// The SF Symbol name.
    public let symbol: String
    /// The heading.
    public let title: String

    /// Creates a Kakusan header.
    ///
    /// - Parameters:
    ///   - symbol: The SF Symbol name.
    ///   - title: The heading.
    public init(symbol: String, title: String) {
        self.symbol = symbol
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 48, height: 48)
                .glassEffect(AppGlass.control, in: .circle)
            Text(title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A failure message on a Kakusan card.
struct KakusanErrorText: View {
    /// The message.
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(CouchTone.failed.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The time left until a deadline, updated every second.
public struct KakusanCountdownText: View {
    /// The words before the time left.
    public let prefix: String
    /// When the countdown ends.
    public let deadline: Date

    /// Creates a Kakusan countdown text.
    ///
    /// - Parameters:
    ///   - prefix: The words before the time left.
    ///   - deadline: When the countdown ends.
    public init(prefix: String, deadline: Date) {
        self.prefix = prefix
        self.deadline = deadline
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(prefix) \(KakusanCountdown.remaining(until: deadline, now: context.date))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// A device fingerprint in lines of monospaced groups.
public struct KakusanFingerprintView: View {
    /// The heading above the fingerprint.
    public let title: String
    /// The fingerprint shown.
    public let fingerprint: KakusanFingerprint

    /// Creates a Kakusan fingerprint view.
    ///
    /// - Parameters:
    ///   - title: The heading above the fingerprint.
    ///   - fingerprint: The fingerprint shown.
    public init(title: String, fingerprint: KakusanFingerprint) {
        self.title = title
        self.fingerprint = fingerprint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(fingerprint.lines, id: \.self) { line in
                    Text(line)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fingerprint \(fingerprint.description)")
        }
    }
}
