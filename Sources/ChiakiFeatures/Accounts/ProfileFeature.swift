import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// A capability that depends on how a profile was added; account id profiles only get local play.
public enum ProfileFeature: Hashable, Sendable {
    /// Remote play with consoles on the local network.
    case localPlay
    /// PlayStation cloud streaming and its catalog.
    case cloud
    /// Consoles found and woken through the PSN account.
    case psnConsoles
    /// The PSN account's trophies.
    case trophies
}

extension RegistrationFlow.ProfileKind {
    /// Whether profiles of this kind can use `feature`; web sign-in profiles can use everything and
    /// account id profiles only local play.
    public func permits(_ feature: ProfileFeature) -> Bool {
        switch self {
        case .npsso:
            true
        case .accountID:
            feature == .localPlay
        }
    }
}

extension Optional where Wrapped == RegistrationFlow.Profile {
    /// Whether the profile can use `feature`; no profile permits nothing.
    public func permits(_ feature: ProfileFeature) -> Bool {
        guard let profile = self else {
            return false
        }
        return profile.kind.permits(feature)
    }
}

/// Wraps a reducer so that entry actions for a feature are dropped, or replaced by a fallback
/// action, while the state's profile does not permit that feature.
public struct ProfileFeatureGate<Base: Reducer>: Reducer {
    /// The wrapped reducer's state.
    public typealias State = Base.State
    /// The wrapped reducer's action.
    public typealias Action = Base.Action

    /// The reducer that handles every action the gate lets through.
    public let base: Base
    /// The feature the gated entry actions need.
    public let feature: ProfileFeature
    /// Where the state keeps the active profile.
    public let profile: KeyPath<State, RegistrationFlow.Profile?>
    /// Whether an action enters the gated feature.
    public let isEntry: (Action) -> Bool
    /// The action sent instead of a blocked entry action, or `nil` to drop it.
    public let otherwise: Action?

    /// Passes the action to `base` unless it is an entry action the profile does not permit, in
    /// which case it sends `otherwise` or nothing.
    public func _reduce(into state: inout State, action: Action) -> Effect<Action> {
        guard isEntry(action), !state[keyPath: profile].permits(feature) else {
            return base._reduce(into: &state, action: action)
        }
        guard let otherwise else {
            return .none
        }
        return .send(otherwise)
    }
}

extension Reducer {
    /// Gates this reducer's entry actions behind a profile feature.
    ///
    /// - Parameters:
    ///   - feature: The feature the entry actions need.
    ///   - profile: Where the state keeps the active profile.
    ///   - otherwise: The action sent instead of a blocked entry action, or `nil` to drop it.
    ///   - isEntry: Whether an action enters the feature.
    /// - Returns: The gated reducer.
    public func requires(
        _ feature: ProfileFeature,
        of profile: KeyPath<State, RegistrationFlow.Profile?>,
        otherwise: Action? = nil,
        entering isEntry: @escaping (Action) -> Bool
    ) -> ProfileFeatureGate<Self> {
        ProfileFeatureGate(
            base: self,
            feature: feature,
            profile: profile,
            isEntry: isEntry,
            otherwise: otherwise
        )
    }
}

extension Reducer where Action: CasePathable {
    /// Gates the listed entry action cases behind a profile feature.
    ///
    /// - Parameters:
    ///   - feature: The feature the entry actions need.
    ///   - profile: Where the state keeps the active profile.
    ///   - entries: The action cases that enter the feature.
    ///   - otherwise: The action sent instead of a blocked entry action, or `nil` to drop it.
    /// - Returns: The gated reducer.
    public func requires(
        _ feature: ProfileFeature,
        of profile: KeyPath<State, RegistrationFlow.Profile?>,
        entering entries: PartialCaseKeyPath<Action>...,
        otherwise: Action? = nil
    ) -> ProfileFeatureGate<Self> {
        requires(feature, of: profile, otherwise: otherwise) { action in
            entries.contains {
                action.is($0)
            }
        }
    }
}

private struct ProfileFeatureVisibility: ViewModifier {
    let permitted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if permitted {
            content
        }
    }
}

extension View {
    /// Shows this view only when `profile` permits `feature`, and removes it otherwise.
    public func requires(_ feature: ProfileFeature, of profile: RegistrationFlow.Profile?) -> some View {
        modifier(ProfileFeatureVisibility(permitted: profile.permits(feature)))
    }
}
