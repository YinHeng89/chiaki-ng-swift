import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import SwiftUI

/// How the account menu and the account sheet describe the selected account's cloud access.
struct AccountCloudSummary {
    /// The line shown under the account's name: the Plus tier when the catalog is reachable, the status
    /// otherwise.
    let text: LocalizedStringResource
    /// The help text explaining the status.
    let help: LocalizedStringResource
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
    public let text: LocalizedStringResource
    /// The colour the status is drawn in.
    public let color: Color
    /// The longer explanation shown as help, including the cached catalog details when there are any.
    public let help: LocalizedStringResource
    /// Whether the account's cloud catalog is confirmed available.
    public var catalogAvailable = false

    /// Works out the label for an account from the cloud status check.
    ///
    /// - Parameters:
    ///   - state: The cloud status check's state.
    ///   - selectedProfileID: The account whose status is shown, or `nil` when none is selected.
    ///   - now: The current time, used to tell whether the cached result has expired.
    public init(state: CloudStatusFeature.State, selectedProfileID: UUID?, now: Date) {
        let fallback: LocalizedStringResource = .libraryCloudStatusFallbackHelp
        guard state.scope?.accountID == selectedProfileID, selectedProfileID != nil else {
            (text, color, help) = (.libraryCloudStatusChecking, .secondary, fallback)
            return
        }
        let cachedHelp: LocalizedStringResource
        if let snapshot = state.snapshot, snapshot.scope.accountID == selectedProfileID {
            cachedHelp = .libraryCloudStatusCachedHelp(
                count: snapshot.catalog.gameCount,
                date: snapshot.checkedAt.formatted()
            )
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
                (text, color, help) = (.libraryCloudStatusChecking, .secondary, cachedHelp)
            }
        case .failed(let reason):
            self = Self(failure: reason, hasSnapshot: state.snapshot != nil, cachedHelp: cachedHelp)
        case .ready:
            self = Self(ready: state, selectedProfileID: selectedProfileID, now: now, cachedHelp: cachedHelp)
        }
    }
    private init(failure reason: CloudStatusFailure, hasSnapshot: Bool, cachedHelp: LocalizedStringResource) {
        switch reason {
        case .signInRequired:
            (text, color, help) = (
                .libraryCloudStatusSignInAgain,
                .orange,
                .libraryCloudStatusSignInAgainHelp
            )
        case .regionUnsupported:
            (text, color, help) = (
                .libraryCloudStatusRegionUnavailable,
                .orange,
                .libraryCloudStatusRegionUnavailableHelp
            )
        case .authorizationRejected:
            (text, color, help) = (
                .libraryCloudStatusAccessRejected,
                .red,
                .libraryCloudStatusAccessRejectedHelp
            )
        default:
            let title: LocalizedStringResource = !hasSnapshot
                ? .libraryCloudStatusCouldNotCheck
                : .libraryCloudStatusUpdateFailed
            (text, color, help) = (title, .red, cachedHelp)
        }
    }
    private init(
        ready state: CloudStatusFeature.State,
        selectedProfileID: UUID?,
        now: Date,
        cachedHelp: LocalizedStringResource
    ) {
        guard let snapshot = state.snapshot, snapshot.scope.accountID == selectedProfileID else {
            (text, color, help) = (.libraryCloudStatusUnknown, .secondary, .libraryCloudStatusFallbackHelp)
            return
        }
        guard snapshot.expiresAt > now else {
            (text, color, help) = (.libraryCloudStatusCachedResult, .secondary, cachedHelp)
            return
        }
        help = cachedHelp
        switch snapshot.catalog.availability {
        case .catalogAvailable:
            (text, color) = (.libraryCloudStatusCatalogAvailable, Palette.accent)
            catalogAvailable = true
        case .subscriptionRequired:
            (text, color) = (.libraryCloudStatusPlusRequired, .orange)
        case .signInRequired:
            (text, color) = (.libraryCloudStatusSignInAgain, .orange)
        case .empty:
            (text, color) = (.libraryCloudStatusNoGames, .secondary)
        case .limitedCatalog:
            (text, color) = (.libraryCloudStatusLimitedCatalog, .orange)
        }
    }
}
