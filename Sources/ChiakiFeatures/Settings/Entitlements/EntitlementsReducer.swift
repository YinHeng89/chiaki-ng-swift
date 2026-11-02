import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Drives the entitlements settings panel: loads saved accounts, fetches and explains an account's cloud
/// titles, and filters them for display.
@Reducer public struct EntitlementsReducer {
    /// The loading workflow of the entitlements panel.
    public enum Phase: Equatable, Sendable {
        /// Nothing has been requested yet.
        case idle
        /// Saved accounts are being read by the operation with this identifier.
        case loadingAccounts(UUID)
        /// Accounts are known and no titles are loaded for the selected account.
        case ready
        /// Titles are being fetched by the operation with this identifier.
        case loading(UUID)
        /// Titles for the selected account are loaded.
        case loaded
        /// The last request failed with this message.
        case failed(String)
    }
    /// The entitlements panel's accounts, loaded titles and display choices.
    @ObservableState public struct State: Equatable {
        /// Where the panel is in its loading workflow.
        public var phase: Phase = .idle
        /// The saved accounts that can be inspected.
        public var accounts: [EntitlementAccount] = []
        /// The identifier of the selected account.
        public var account: UUID?
        /// The loaded titles for the selected account, or `nil` before they are fetched.
        public var titles: [ExplainedTitle]?
        /// How the catalogue was fetched for the loaded titles.
        public var report: CatalogFetchReport?
        /// The service whose titles are listed.
        public var service = EntitlementService.psNow
        /// The visibility filter applied to the list.
        public var filter = EntitlementFilter.all
        /// The search text matched against title names and product identifiers.
        public var query = ""
        /// The identifier of the title whose details are shown.
        public var selection: String?
        /// Creates an idle panel with no accounts or titles.
        public init() {
        }
        /// Whether accounts or titles are being loaded.
        public var busy: Bool {
            switch phase {
            case .loadingAccounts, .loading:
                true
            default:
                false
            }
        }
        /// The selected account, if it is among the loaded accounts.
        public var selectedAccount: EntitlementAccount? {
            accounts.first { $0.id == account }
        }
        /// The loaded titles that match the service, filter and search text.
        public var rows: [ExplainedTitle] {
            (titles ?? []).filter {
                service.lists($0) && filter
                    .matches($0) && (query.isEmpty || $0.game.name.localizedStandardContains(query)
                        || $0.game.productId.localizedStandardContains(query))
            }
        }
        /// The selected title, if it is among the visible rows.
        public var selected: ExplainedTitle? {
            rows.first { $0.id == selection }
        }
        /// Counts for the selected service across all loaded titles.
        public var summary: EntitlementSummary {
            EntitlementSummary(titles ?? [], service: service)
        }
    }
    /// Events the entitlements panel handles.
    public enum Action: Equatable, Sendable {
        /// The panel appeared and should load saved accounts if it has none.
        case appear
        /// The account read with this identifier finished with these accounts.
        case accountsLoaded(UUID, [EntitlementAccount])
        /// The account read with this identifier failed with this message.
        case accountsFailed(UUID, String)
        /// The user chose a different account, clearing any loaded titles.
        case selectAccount(UUID?)
        /// The user asked to load the selected account's titles.
        case load
        /// The title fetch with this identifier finished with these titles.
        case loaded(UUID, [ExplainedTitle])
        /// The title fetch with this identifier reported how the catalogue was fetched.
        case reported(UUID, CatalogFetchReport?)
        /// The title fetch with this identifier failed with this message.
        case failed(UUID, String)
        /// The user chose which service's titles to list.
        case service(EntitlementService)
        /// The user chose a visibility filter.
        case filter(EntitlementFilter)
        /// The user changed the search text.
        case query(String)
        /// The user selected a title, or cleared the selection.
        case select(String?)
    }
    /// Loads accounts and titles.
    @Dependency(\.catalog) var client
    /// Supplies the locale used to ask the catalogue for titles.
    @Dependency(\.locale) var locale
    /// Generates the identifiers that tie each completion to the request that started it.
    @Dependency(\.uuid) var uuid
    /// Identifies the in-flight account and title requests so a newer request cancels an older one.
    public enum CancelID: Sendable {
        /// The account read and the title fetch.
        case accounts, load
    }
    /// Creates the reducer.
    public init() {
    }
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appear:
                guard state.phase == .idle || state.accounts.isEmpty, !state.busy else {
                    return .none
                }
                let id = uuid()
                state.phase = .loadingAccounts(id)
                return .run { [client] send in
                    do {
                        await send(.accountsLoaded(id, try await client.entitlementAccounts()))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.accountsFailed(id, "Saved accounts could not be read."))
                    }
                }.cancellable(id: CancelID.accounts, cancelInFlight: true)
            case let .accountsLoaded(id, accounts):
                guard state.phase == .loadingAccounts(id) else {
                    return .none
                }
                state.accounts = accounts
                if state.selectedAccount == nil {
                    state.account = accounts.first?.id
                    state.titles = nil
                }
                state.phase = state.titles == nil
                    ? .ready
                    : .loaded
            case let .accountsFailed(id, message):
                guard state.phase == .loadingAccounts(id) else {
                    return .none
                }
                state.phase = .failed(message)
            case .selectAccount(let account):
                guard state.account != account else {
                    return .none
                }
                state.account = account
                state.titles = nil
                state.report = nil
                state.selection = nil
                state.phase = .ready
                return .cancel(id: CancelID.load)
            case .load:
                guard let account = state.selectedAccount else {
                    return .none
                }
                let id = uuid()
                state.phase = .loading(id)
                let catalogLocale = locale.identifier.replacingOccurrences(of: "_", with: "-")
                return .run { [client] send in
                    do {
                        let titles = try await client.explainedTitles(account, catalogLocale)
                        await send(.reported(id, await client.fetchReport(account)))
                        await send(.loaded(id, titles))
                    } catch is CancellationError {
                        return
                    } catch let failure as EntitlementsFailure {
                        await send(.failed(id, failure.message))
                    } catch {
                        await send(.failed(id, LogFormat.error(error)))
                    }
                }.cancellable(id: CancelID.load, cancelInFlight: true)
            case let .loaded(id, titles):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.titles = titles
                state.phase = .loaded
                if state.selected == nil {
                    state.selection = state.rows.first?.id
                }
            case let .reported(id, report):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.report = report
            case let .failed(id, message):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.phase = .failed(message)
            case .service(let service):
                guard state.service != service else {
                    return .none
                }
                state.service = service
                state.selection = state.rows.first?.id
            case .filter(let filter):
                state.filter = filter
            case .query(let query):
                state.query = query
            case .select(let id):
                state.selection = id
            }
            return .none
        }
    }
}

/// The visibility filter applied to the entitlements title list.
public enum EntitlementFilter: String, CaseIterable, Equatable, Sendable {
    /// Shows every title, only the titles that are offered, or only the titles that were dropped.
    case all = "All", visible = "Visible", hidden = "Hidden"

    /// Returns whether the title passes this filter based on its visibility.
    public func matches(_ title: ExplainedTitle) -> Bool {
        switch self {
        case .all:
            true
        case .visible:
            title.game.visible
        case .hidden:
            !title.game.visible
        }
    }
}

/// Counts for one service's titles: how many are offered, how many are held, and why the rest were dropped.
public struct EntitlementSummary: Equatable, Sendable {
    /// A group of dropped titles that share the same reason.
    public struct Dropped: Equatable, Sendable {
        /// The reason the titles in this group were dropped.
        public let reason: String
        /// How many titles were dropped for this reason.
        public let count: Int
    }

    /// The number of the service's titles that are offered.
    public let present: Int
    /// The number of the service's titles the account owns.
    public let held: Int
    /// The dropped titles grouped by reason, in the order each reason was first seen.
    public let dropped: [Dropped]

    /// Builds the summary from the titles that the given service lists.
    public init(_ titles: [ExplainedTitle], service: EntitlementService) {
        let listed = titles.filter { service.lists($0) }
        present = listed.count { $0.game.visible }
        held = listed.count { $0.game.isOwned }
        var reasons: [String] = []
        var counts: [String: Int] = [:]
        for title in listed where !title.game.visible {
            let reason = title.droppedBecause ?? ""
            if counts[reason] == nil {
                reasons.append(reason)
            }
            counts[reason, default: 0] += 1
        }
        dropped = reasons.map { Dropped(reason: $0, count: counts[$0] ?? 0) }
    }

    /// The total number of titles dropped across every reason.
    public var droppedCount: Int {
        dropped.reduce(0) { $0 + $1.count }
    }
}
