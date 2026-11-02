import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import SwiftUI

/// How the account menu and the account sheet describe the selected account's cloud access.
struct AccountCloudSummary {
    /// The line shown under the account's name: the Plus tier when the catalog is reachable, the status
    /// otherwise.
    let text: String
    /// The help text explaining the status.
    let help: String
    /// The colour of the line.
    let color: Color

    /// Describes the library's cloud status for its selected account.
    ///
    /// - Parameters:
    ///   - store: The library.
    ///   - now: The moment the status is described at.
    @MainActor init(store: StoreOf<LibraryFeature>, now: Date = Date()) {
        let presentation = CloudStatusPresentation(
            state: store.cloudStatus,
            selectedProfileID: store.selectedAccount,
            now: now
        )
        text = presentation.catalogAvailable
            ? store.cloudStatus.plusTier?.label ?? presentation.text
            : presentation.text
        help = presentation.help
        color = presentation.color
    }
}

/// The cloud status label for the selected account: its text, colour and help, worked out from the cloud
/// status check and its cached result.
public struct CloudStatusPresentation {
    /// The short status text shown in the label.
    public let text: String
    /// The colour the status is drawn in.
    public let color: Color
    /// The longer explanation shown as help, including the cached catalog details when there are any.
    public let help: String
    /// Whether the account's cloud catalog is confirmed available.
    public var catalogAvailable = false

    /// Works out the label for an account from the cloud status check.
    ///
    /// - Parameters:
    ///   - state: The cloud status check's state.
    ///   - selectedProfileID: The account whose status is shown, or `nil` when none is selected.
    ///   - now: The current time, used to tell whether the cached result has expired.
    public init(state: CloudStatusFeature.State, selectedProfileID: UUID?, now: Date) {
        let fallback = "Checks this account’s PlayStation cloud catalog. Use Refresh details to retry."
        guard state.scope?.accountID == selectedProfileID, selectedProfileID != nil else {
            (text, color, help) = ("Checking cloud…", .secondary, fallback)
            return
        }
        let cachedHelp: String
        if let snapshot = state.snapshot, snapshot.scope.accountID == selectedProfileID {
            cachedHelp = "\(snapshot.catalog.gameCount) catalog games. "
                + "Last checked \(snapshot.checkedAt.formatted()). "
                + "Streaming access is verified separately for each game."
        } else {
            cachedHelp = fallback
        }
        switch state.phase {
        case .idle, .loading, .refreshing:
            if let snapshot = state.snapshot, snapshot.scope.accountID == selectedProfileID,
               snapshot.expiresAt > now {
                self = Self(
                    ready: state,
                    selectedProfileID: selectedProfileID,
                    now: now,
                    cachedHelp: cachedHelp
                )
            } else {
                (text, color, help) = ("Checking cloud…", .secondary, cachedHelp)
            }
        case .failed(let reason):
            self = Self(failure: reason, hasSnapshot: state.snapshot != nil, cachedHelp: cachedHelp)
        case .ready:
            self = Self(ready: state, selectedProfileID: selectedProfileID, now: now, cachedHelp: cachedHelp)
        }
    }
    private init(failure reason: CloudStatusFailure, hasSnapshot: Bool, cachedHelp: String) {
        switch reason {
        case .signInRequired:
            (text, color, help) = (
                "Cloud sign in again",
                .orange,
                "Sign in again to save a current NPSSO credential for cloud access."
            )
        case .regionUnsupported:
            (text, color, help) = (
                "Cloud region unavailable",
                .orange,
                "PlayStation did not return a cloud store for this account’s region."
            )
        case .authorizationRejected:
            (text, color, help) = (
                "Cloud access rejected",
                .red,
                "PlayStation rejected cloud authorization (HTTP 403). "
                    + "This does not establish that your NPSSO is expired or that your subscription is ineligible."
            )
        default:
            let title = !hasSnapshot
                ? "Cloud couldn’t check"
                : "Cloud update failed"
            (text, color, help) = (title, .red, cachedHelp)
        }
    }
    private init(
        ready state: CloudStatusFeature.State,
        selectedProfileID: UUID?,
        now: Date,
        cachedHelp: String
    ) {
        let fallback = "Checks this account’s PlayStation cloud catalog. Use Refresh details to retry."
        guard let snapshot = state.snapshot, snapshot.scope.accountID == selectedProfileID else {
            (text, color, help) = ("Cloud unknown", .secondary, fallback)
            return
        }
        guard snapshot.expiresAt > now else {
            (text, color, help) = ("Cloud cached result", .secondary, cachedHelp)
            return
        }
        help = cachedHelp
        switch snapshot.catalog.availability {
        case .catalogAvailable:
            (text, color) = ("Cloud catalog available", Palette.accent)
            catalogAvailable = true
        case .subscriptionRequired:
            (text, color) = ("Cloud PS Plus required", .orange)
        case .signInRequired:
            (text, color) = ("Cloud sign in again", .orange)
        case .empty:
            (text, color) = ("Cloud no games found", .secondary)
        case .limitedCatalog:
            (text, color) = ("Cloud limited catalog", .orange)
        }
    }
}
