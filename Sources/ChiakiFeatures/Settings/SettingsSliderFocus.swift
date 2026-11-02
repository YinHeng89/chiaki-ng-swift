import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// The Settings slider that holds focus: its identity and its live value.
///
/// Two targets are equal only when they are the same slider with the same value, so Settings notices when the
/// focused slider's value changes and refreshes the binding it restores on cancel.
struct SettingsSliderTarget: Equatable {
    /// The slider's identity, unique for each slider on screen.
    let id: UUID
    /// The slider's value.
    let value: Binding<Double>

    /// Compares identity and current value.
    ///
    /// - Parameters:
    ///   - lhs: One target.
    ///   - rhs: The other target.
    /// - Returns: `true` when both are the same slider showing the same value.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.value.wrappedValue == rhs.value.wrappedValue
    }
}

private struct SettingsSliderTargetKey: FocusedValueKey {
    typealias Value = SettingsSliderTarget
}

extension FocusedValues {
    /// The Settings slider that holds focus, or `nil` when no slider does.
    var settingsSliderTarget: SettingsSliderTarget? {
        get {
            self[SettingsSliderTargetKey.self]
        }
        set {
            self[SettingsSliderTargetKey.self] = newValue
        }
    }
}

/// Which Settings slider, if any, the controller is adjusting, with its value from when adjusting started.
typealias SettingsSliderNavigationState = SliderAdjustment<UUID, Double>

/// Holds the focused Settings slider for controller handlers, which outlive the view update that registered
/// them.
@MainActor
final class SettingsSliderFocusReference {
    /// The focused slider, or `nil` when no slider has focus.
    var target: SettingsSliderTarget?
}

private struct SettingsSliderNavigationKey: EnvironmentKey {
    static let defaultValue = SettingsSliderNavigationState.navigating
}

extension EnvironmentValues {
    /// Whether a Settings slider is being adjusted, so each slider can show the matching hint.
    var settingsSliderNavigation: SettingsSliderNavigationState {
        get {
            self[SettingsSliderNavigationKey.self]
        }
        set {
            self[SettingsSliderNavigationKey.self] = newValue
        }
    }
}

private struct SettingsSliderController: ViewModifier {
    let value: Binding<Double>
    @Environment(\.settingsSliderNavigation) private var navigation
    @MenuFocusState private var focused: Bool
    @State private var id = UUID()

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .menuFocused($focused)
                .focusedValue(\.settingsSliderTarget, SettingsSliderTarget(id: id, value: value))
            if focused {
                SliderAdjustmentPrompt(adjusting: navigation.isAdjusting(id))
            }
        }
    }
}

extension View {
    /// Makes a Settings slider adjustable with the controller: Confirm starts and finishes adjusting, Back
    /// restores the value from when adjusting started, and a hint below the slider says which applies.
    ///
    /// - Parameter value: The slider's value, which Back restores.
    /// - Returns: The slider with its controller hint.
    func settingsSliderController(value: Binding<Double>) -> some View {
        modifier(SettingsSliderController(value: value))
    }
}
