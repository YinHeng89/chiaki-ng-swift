import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Drives the Requests settings panel: polls the core's HTTP log while visible, filters the exchanges, loads
/// one exchange's details and reveals or copies masked secrets on request.
@Reducer public struct RequestsReducer {
    /// How often the log's revision is checked while the panel is visible.
    public static let refreshEvery = Duration.seconds(1)

    /// The progress of reading the log.
    public enum Phase: Equatable, Sendable {
        /// The log has not been read.
        case idle
        /// The read with this identifier is in flight.
        case loading(UUID)
        /// The log has been read.
        case ready
        /// The last read failed with this message.
        case failed(LocalizedStringResource)
    }

    /// Whether the panel is visible and polling the log.
    public enum Watch: Equatable, Sendable {
        /// The panel is not visible, so the log is not polled.
        case hidden
        /// The panel is visible and the log is polled for new revisions.
        case watching
    }

    /// The detail pane for one exchange.
    public enum Detail: Equatable, Sendable {
        /// No exchange is open.
        case closed
        /// The details of this exchange are being read by the request with this identifier.
        case loading(UInt64, UUID)
        /// The details of this exchange are shown.
        case shown(UInt64, CoreHTTPExchangeDetail)
        /// This exchange is no longer kept, so its details could not be read.
        case missing(UInt64)

        /// The exchange the pane is about, or `nil` when it is closed.
        public var exchange: UInt64? {
            switch self {
            case .closed:
                nil
            case .loading(let exchange, _), .shown(let exchange, _), .missing(let exchange):
                exchange
            }
        }
    }

    /// The request log, the filters applied to it and the open exchange.
    @ObservableState public struct State: Equatable {
        /// The progress of reading the log.
        public var phase = Phase.idle
        /// Whether the panel is visible and polling.
        public var watch = Watch.hidden
        /// The last log that was read.
        public var log = CoreHTTPLog()
        /// The filters applied to the request list.
        public var filter = Filter()
        /// The exchange detail pane.
        public var detail = Detail.closed
        /// The masked secrets the user chose to reveal in the open exchange.
        public var revealed: Set<Secret> = []

        /// Creates state that has not read the log.
        public init() {
        }

        /// Whether a log read is in flight.
        public var loading: Bool {
            if case .loading = phase {
                return true
            }
            return false
        }

        /// The exchanges that pass the filter.
        public var shown: [CoreHTTPExchange] {
            log.exchanges.filter(filter.admits)
        }

        /// The open exchange, if it is still in the log.
        public var selected: CoreHTTPExchange? {
            guard let exchange = detail.exchange else {
                return nil
            }
            return log.exchanges.first { $0.id == exchange }
        }

        /// The base URLs offered as filters, ordered by lifetime request count.
        public var baseChoices: [RequestBaseChoice] {
            RequestBaseChoice.choices(totals: log.totals, exchanges: log.exchanges, chosen: filter.bases)
        }
    }

    /// Events the Requests panel handles.
    public enum Action: Equatable, Sendable {
        /// The panel appeared, so the log is read and polled.
        case appear
        /// The panel disappeared, so polling and any read stop.
        case disappear
        /// Reads the log again.
        case refresh
        /// The read with this identifier returned this log.
        case loaded(UUID, CoreHTTPLog)
        /// The read with this identifier failed.
        case loadFailed(UUID)
        /// The poll saw this log revision, which triggers a read when it differs from the shown log.
        case revisionSeen(UInt64)
        /// Turns a credential filter on or off.
        case toggleCredential(CredentialFilter)
        /// Turns an area filter on or off.
        case toggleArea(CoreHTTPArea)
        /// Turns a base URL filter on or off.
        case toggleBase(String)
        /// Shows only failed exchanges, or every exchange.
        case setFailuresOnly(Bool)
        /// Sets the search text.
        case setSearch(String)
        /// Removes every filter.
        case clearFilters
        /// Opens the exchange with this identifier, or closes it when it is already open.
        case open(UInt64)
        /// Closes the detail pane and hides revealed secrets.
        case close
        /// The detail read with this identifier returned these details, or `nil` when the exchange is gone.
        case detailLoaded(UUID, CoreHTTPExchangeDetail?)
        /// Reveals or masks a secret again.
        case toggleSecret(Secret)
        /// Clears the log and reads it again.
        case clearLog
        /// Resets the lifetime totals and reads the log again.
        case resetCounts
        /// Copies the open request as a curl command, with only revealed secrets unmasked.
        case copyCurl
        /// Copies the open response's status, headers and body, with only revealed secrets unmasked.
        case copyResponse
    }

    /// Reads and manages the HTTP log.
    @Dependency(\.settings) var client
    /// Copies exchanges and their parts as text.
    @Dependency(\.platform) var platform
    /// Generates the identifiers that tie each completion to its request.
    @Dependency(\.uuid) var uuid
    /// Paces the revision poll.
    @Dependency(\.continuousClock) var clock

    /// Identifies the poll, the log read and the detail read so each can be cancelled or replaced.
    public enum CancelID: Sendable {
        /// The revision poll, the log read and the detail read.
        case poll, log, detail
    }

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appear:
                guard state.watch == .hidden else {
                    return .none
                }
                state.watch = .watching
                return .merge(load(&state), poll())
            case .disappear:
                guard state.watch == .watching else {
                    return .none
                }
                state.watch = .hidden
                if state.loading {
                    state.phase = .idle
                }
                return .merge(.cancel(id: CancelID.poll), .cancel(id: CancelID.log))
            case .refresh:
                return load(&state)
            case let .loaded(id, log):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.log = log
                state.phase = .ready
            case .loadFailed(let id):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.phase = .failed(.settingsRequestsUnreadable)
            case .revisionSeen(let revision):
                guard state.watch == .watching, !state.loading, revision != state.log.revision else {
                    return .none
                }
                return load(&state)
            case .toggleCredential(let credential):
                state.filter.credentials.formSymmetricDifference([credential])
            case .toggleArea(let area):
                state.filter.areas.formSymmetricDifference([area])
            case .toggleBase(let base):
                state.filter.bases.formSymmetricDifference([base])
            case .setFailuresOnly(let only):
                state.filter.failuresOnly = only
            case .setSearch(let text):
                state.filter.search = text
            case .clearFilters:
                state.filter = Filter()
            case .open(let exchange):
                state.revealed = []
                guard state.detail.exchange != exchange else {
                    state.detail = .closed
                    return .cancel(id: CancelID.detail)
                }
                let id = uuid()
                state.detail = .loading(exchange, id)
                return .run { [client] send in
                    await send(.detailLoaded(id, await client.requestDetail(exchange)))
                }.cancellable(id: CancelID.detail, cancelInFlight: true)
            case .close:
                state.detail = .closed
                state.revealed = []
                return .cancel(id: CancelID.detail)
            case let .detailLoaded(id, detail):
                guard case .loading(let exchange, id) = state.detail else {
                    return .none
                }
                state.detail = detail.map { .shown(exchange, $0) } ?? .missing(exchange)
            case .toggleSecret(let secret):
                state.revealed.formSymmetricDifference([secret])
            case .clearLog:
                state.detail = .closed
                state.revealed = []
                return .merge(
                    .cancel(id: CancelID.detail),
                    .run { [client] send in
                        await client.clearRequestLog()
                        await send(.refresh)
                    }
                )
            case .resetCounts:
                return .run { [client] send in
                    await client.resetRequestTotals()
                    await send(.refresh)
                }
            case .copyCurl:
                guard let exchange = state.selected, case .shown(_, let detail) = state.detail else {
                    return .none
                }
                let text = RequestCopy.curl(exchange, detail, revealed: state.revealed)
                return .run { [platform] _ in
                    await platform.copy(text)
                }
            case .copyResponse:
                guard let exchange = state.selected, case .shown(_, let detail) = state.detail else {
                    return .none
                }
                let text = RequestCopy.response(exchange, detail, revealed: state.revealed)
                return .run { [platform] _ in
                    await platform.copy(text)
                }
            }
            return .none
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        let id = uuid()
        state.phase = .loading(id)
        return .run { [client] send in
            do {
                await send(.loaded(id, try await client.requestLog()))
            } catch is CancellationError {
                return
            } catch {
                await send(.loadFailed(id))
            }
        }.cancellable(id: CancelID.log, cancelInFlight: true)
    }

    private func poll() -> Effect<Action> {
        .run { [client, clock] send in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.refreshEvery)
                } catch {
                    return
                }
                await send(.revisionSeen(await client.requestLogRevision()))
            }
        }.cancellable(id: CancelID.poll, cancelInFlight: true)
    }
}

/// The types that identify masked secrets and filter the request list.
extension RequestsReducer {
    /// The part of an exchange a masked secret sits in.
    public enum SecretPart: Hashable, Sendable {
        /// The request URL.
        case url
        /// The request header at this position.
        case requestHeader(Int)
        /// The request body.
        case requestBody
        /// The response header at this position.
        case responseHeader(Int)
        /// The response body.
        case responseBody
    }

    /// One masked secret, identified by the part of the exchange it sits in and its position among that
    /// part's secrets.
    public struct Secret: Hashable, Sendable {
        /// The part of the exchange that holds the secret.
        public let part: SecretPart
        /// The secret's position among the secrets marked in that part.
        public let index: Int

        /// Identifies the secret at the given position within the given part.
        public init(_ part: SecretPart, _ index: Int) {
            self.part = part
            self.index = index
        }
    }

    /// A filter on the credentials an exchange carried.
    public enum CredentialFilter: Hashable, Sendable, CaseIterable {
        /// Admits exchanges that carried no credentials.
        case anonymous
        /// Admits exchanges that carried this credential.
        case carried(CoreHTTPCredential)

        /// The anonymous choice followed by one choice for each credential.
        public static var allCases: [CredentialFilter] {
            [.anonymous] + CoreHTTPCredential.allCases.map(CredentialFilter.carried)
        }

        /// Returns whether the exchange matches this credential choice.
        public func admits(_ exchange: CoreHTTPExchange) -> Bool {
            switch self {
            case .anonymous:
                exchange.credentials.isEmpty
            case .carried(let credential):
                exchange.credentials.contains(credential)
            }
        }
    }

    /// The filters applied to the request list; empty sets admit everything.
    public struct Filter: Equatable, Sendable {
        /// The credential choices, any of which admits an exchange.
        public var credentials: Set<CredentialFilter> = []
        /// The request areas to show.
        public var areas: Set<CoreHTTPArea> = []
        /// The base URLs to show.
        public var bases: Set<String> = []
        /// Whether only failed exchanges are shown.
        public var failuresOnly = false
        /// Text matched case insensitively against the masked URL.
        public var search = ""

        /// Creates a filter that admits every exchange.
        public init() {
        }

        /// Whether no filter is set, ignoring search text that is only whitespace.
        public var isEmpty: Bool {
            credentials.isEmpty && areas.isEmpty && bases.isEmpty && !failuresOnly
                && search.trimmingCharacters(in: .whitespaces).isEmpty
        }

        /// Returns whether the exchange passes every filter that is set.
        public func admits(_ exchange: CoreHTTPExchange) -> Bool {
            if failuresOnly, !exchange.failed {
                return false
            }
            if !areas.isEmpty, !areas.contains(exchange.area) {
                return false
            }
            if !bases.isEmpty, !bases.contains(exchange.base) {
                return false
            }
            if !credentials.isEmpty, !credentials.contains(where: { $0.admits(exchange) }) {
                return false
            }
            let needle = search.trimmingCharacters(in: .whitespaces)
            guard !needle.isEmpty else {
                return true
            }
            return RequestMasking.masked(exchange.url).localizedCaseInsensitiveContains(needle)
        }
    }
}
