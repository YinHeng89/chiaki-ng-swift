import SwiftUI

extension EnvironmentValues {
    /// Whether streamer mode is on, hiding identifiers such as console addresses and account ids on screen.
    @Entry public var streamerMode = false
}

/// The text rules of streamer mode, which replaces identifying values with a neutral placeholder.
public enum StreamerMode {
    /// The placeholder shown instead of a hidden value.
    public static let hidden = "Hidden"

    /// The text to show for an identifier.
    ///
    /// - Parameters:
    ///   - value: The identifier.
    ///   - enabled: Whether streamer mode is on.
    /// - Returns: ``hidden`` when streamer mode is on, otherwise `value`.
    public static func identifier(_ value: String, enabled: Bool) -> String {
        enabled
            ? hidden
            : value
    }

    /// The name to show for a console.
    ///
    /// - Parameters:
    ///   - name: The console's own name, if it has one.
    ///   - address: The console's network address.
    ///   - kind: The console's model name, used instead of the address in streamer mode.
    ///   - enabled: Whether streamer mode is on.
    /// - Returns: The name, or the address or model name when the console has no name.
    public static func consoleName(_ name: String?, address: String, kind: String, enabled: Bool) -> String {
        name ?? (enabled
            ? kind
            : address)
    }
}

/// Hides a text field's value behind the streamer mode placeholder while keeping the field usable.
///
/// The field keeps its layout and still accepts input; only the drawn text is cleared and the placeholder
/// is drawn over it. Apply it with ``SwiftUICore/View/streamerHiddenField(_:active:)``.
public struct StreamerHiddenField: ViewModifier {
    @Environment(\.streamerMode) private var streamerMode
    private let text: String
    private let active: Bool

    /// Creates the modifier for one field.
    ///
    /// - Parameters:
    ///   - text: The field's current value.
    ///   - active: Whether this field hides its value in streamer mode.
    public init(text: String, active: Bool) {
        self.text = text
        self.active = active
    }

    private var hidden: Bool {
        active && streamerMode && !text.isEmpty
    }

    /// Clears the drawn value and overlays the placeholder while streamer mode hides it.
    ///
    /// - Parameter content: The text field.
    /// - Returns: The field with its value hidden when required.
    public func body(content: Content) -> some View {
        content
            .foregroundStyle(
                hidden
                    ? AnyShapeStyle(Color.clear)
                    : AnyShapeStyle(.foreground)
            )
            .overlay(alignment: .leading) {
                Text(StreamerMode.hidden)
                    .foregroundStyle(.secondary)
                    .opacity(
                        hidden
                            ? 1
                            : 0
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityValue(
                Text(
                    hidden
                        ? StreamerMode.hidden
                        : text
                )
            )
    }
}

extension View {
    /// Hides the field's value in streamer mode.
    ///
    /// - Parameters:
    ///   - text: The field's current value.
    ///   - active: Whether this field hides its value in streamer mode.
    /// - Returns: The field wrapped in ``StreamerHiddenField``.
    public func streamerHiddenField(_ text: String, active: Bool = true) -> some View {
        modifier(StreamerHiddenField(text: text, active: active))
    }
}
