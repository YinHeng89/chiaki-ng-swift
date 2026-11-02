import ChiakiModels
import ChiakiDiagnostics
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// Shows request totals, filter controls and the list of HTTP exchanges the core recorded, with an inline
/// detail pane whose masked secrets can be revealed and copied. Totals and log rows wrap to two lines when the
/// page is too narrow for their columns.
public struct RequestsSettingsView: View {
    /// The requests reducer that owns the log, filters and open exchange.
    public let store: StoreOf<RequestsReducer>
    @MenuFocusState private var searchFocused: Bool
    @MenuFocusState private var focusedRow: UInt64?

    /// Creates a requests settings view.
    ///
    /// - Parameter store: The requests reducer that owns the log, filters and open exchange.
    public init(store: StoreOf<RequestsReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            controls
            if case .failed(let message) = store.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            filters
            list
        }
    }

    private var search: Binding<String> {
        Binding(
            get: {
                store.filter.search
            },
            set: {
                store.send(.setSearch($0))
            }
        )
    }

    private var summary: some View {
        let all = store.log.totals.all
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                requestStats(all)
                volumeStats(all)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    requestStats(all)
                }
                HStack(spacing: 24) {
                    volumeStats(all)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func requestStats(_ all: CoreHTTPTally) -> some View {
        stat("Requests", "\(all.requests)")
        stat("HTTP errors", "\(all.httpErrors)")
        stat("Transport errors", "\(all.transportErrors)")
    }

    @ViewBuilder private func volumeStats(_ all: CoreHTTPTally) -> some View {
        stat("Received", LogFormat.size(all.bytesReceived))
        stat("Sent", LogFormat.size(all.bytesSent))
        stat("In log", "\(store.log.exchanges.count)")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            FocusButton("Clear log", role: .destructive) {
                store.send(.clearLog)
            }
            .glassControlStyle()
            .disabled(store.log.exchanges.isEmpty)
            .accessibilityIdentifier("requests-clear-log")
            FocusButton("Reset counts") {
                store.send(.resetCounts)
            }
            .glassControlStyle()
            .disabled(store.log.totals.all.requests == 0)
            .accessibilityIdentifier("requests-reset-counts")
            FocusButton("Clear filters") {
                store.send(.clearFilters)
            }
            .glassControlStyle()
            .disabled(store.filter.isEmpty)
            .accessibilityIdentifier("requests-clear-filters")
            if store.loading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var filters: some View {
        SettingsCard {
            HStack(spacing: 16) {
                TextField("Search URLs", text: search)
                    .textFieldStyle(.roundedBorder)
                    .menuFocusBinding($searchFocused)
                    .controllerKeyboard(title: "Search URLs", text: search, isFocused: searchFocused)
                    .accessibilityIdentifier("requests-search")
                Toggle(
                    "Failures only",
                    isOn: Binding(
                        get: {
                            store.filter.failuresOnly
                        },
                        set: {
                            store.send(.setFailuresOnly($0))
                        }
                    )
                )
                .accessibilityIdentifier("requests-failures-only")
            }
            Divider()
            chipRow("Credentials") {
                ForEach(RequestsReducer.CredentialFilter.allCases, id: \.self) { credential in
                    chip(credential.title, chosen: store.filter.credentials.contains(credential)) {
                        store.send(.toggleCredential(credential))
                    }
                }
            }
            Divider()
            chipRow("Areas") {
                ForEach(CoreHTTPArea.allCases, id: \.self) { area in
                    chip(area.title, chosen: store.filter.areas.contains(area)) {
                        store.send(.toggleArea(area))
                    }
                }
            }
            if !store.baseChoices.isEmpty {
                Divider()
                chipRow("Bases") {
                    ForEach(store.baseChoices) { choice in
                        chip(
                            "\(choice.host)  \(choice.lifetime)  \(choice.kept) in log",
                            chosen: choice.chosen
                        ) {
                            store.send(.toggleBase(choice.base))
                        }
                        .help(choice.base)
                    }
                }
            }
        }
    }

    private func chipRow(_ title: String, @ViewBuilder chips: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chips()
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(_ title: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        FocusButton(action: action) {
            Label(title, systemImage: chosen
                ? "checkmark.circle.fill"
                : "circle")
                .font(.callout)
                .lineLimit(1)
        }
        .glassControlStyle()
        .accessibilityAddTraits(chosen
            ? .isSelected
            : [])
    }

    @ViewBuilder private var list: some View {
        let shown = store.shown
        if shown.isEmpty {
            Text(store.log.exchanges.isEmpty
                ? "No requests"
                : "No matching requests")
                .foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { exchange in
                    row(exchange)
                    if store.detail.exchange == exchange.id {
                        RequestDetailView(exchange: exchange, store: store) {
                            store.send(.close)
                            focusedRow = exchange.id
                        }
                        .padding(.leading, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder private func exchangeColumns(_ shown: RequestRowPresentation) -> some View {
        Text(shown.time).monospacedDigit().foregroundStyle(.secondary)
            .frame(width: 70, alignment: .leading)
        Text(shown.method).font(.callout.monospaced().weight(.semibold))
            .frame(width: 56, alignment: .leading)
        VStack(alignment: .leading, spacing: 2) {
            Text(shown.base).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(shown.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(idealWidth: 160)
    }

    @ViewBuilder private func outcomeColumns(_ shown: RequestRowPresentation) -> some View {
        Label(shown.status, systemImage: shown.failed
            ? "exclamationmark.triangle.fill"
            : "checkmark.circle")
            .foregroundStyle(shown.failed
                ? Color.red
                : Color.secondary)
                .frame(width: 130, alignment: .leading)
        Text(shown.duration).monospacedDigit().foregroundStyle(.secondary)
            .frame(width: 70, alignment: .trailing)
        Text(shown.size).monospacedDigit().foregroundStyle(.secondary)
            .frame(width: 70, alignment: .trailing)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(shown.credentials, id: \.self) { credential in
                Text(credential).font(.caption)
            }
        }
        .frame(width: 120, alignment: .leading)
        Text(shown.area).font(.caption).foregroundStyle(.secondary)
            .frame(width: 70, alignment: .leading)
    }

    private func row(_ exchange: CoreHTTPExchange) -> some View {
        let shown = RequestRowPresentation(exchange)
        return FocusButton {
            store.send(.open(exchange.id))
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    exchangeColumns(shown)
                    outcomeColumns(shown)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        exchangeColumns(shown)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        outcomeColumns(shown)
                    }
                }
            }
            .font(.callout)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .menuFocused($focusedRow, equals: exchange.id)
        .accessibilityIdentifier("requests-row-\(exchange.id)")
        .accessibilityAddTraits(store.detail.exchange == exchange.id
            ? .isSelected
            : [])
    }
}

private struct RequestDetailView: View {
    let exchange: CoreHTTPExchange
    let store: StoreOf<RequestsReducer>
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FocusButton("Copy as cURL") {
                    store.send(.copyCurl)
                }
                .glassControlStyle()
                .disabled(!loaded)
                .accessibilityIdentifier("requests-copy-curl")
                FocusButton("Copy response") {
                    store.send(.copyResponse)
                }
                .glassControlStyle()
                .disabled(!loaded)
                .accessibilityIdentifier("requests-copy-response")
                FocusButton("Close") {
                    close()
                }
                .glassControlStyle()
                .accessibilityIdentifier("requests-close-detail")
            }
            facts
            switch store.detail {
            case .closed:
                EmptyView()
            case .loading:
                ProgressView().controlSize(.small)
            case .missing:
                Label("This request is no longer in the log.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .shown(_, let detail):
                section("Request") {
                    marked("URL", exchange.url, part: .url)
                    headers(detail.requestHeaders, request: true)
                    shownBody(detail.requestBody, part: .requestBody)
                }
                section("Response") {
                    if let error = exchange.transportError {
                        Label(error.title, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        headers(detail.responseHeaders, request: false)
                        shownBody(detail.responseBody, part: .responseBody)
                    }
                }
            }
        }
    }

    private var loaded: Bool {
        if case .shown = store.detail {
            return true
        }
        return false
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 3) {
            fact("Endpoint", exchange.label)
            fact("Credential", exchange.credentialLabel)
            fact("Attempt", "\(exchange.attempt)")
            fact("Started", exchange.startedAt.formatted(date: .abbreviated, time: .standard))
            fact("Status", exchange.status.map { code in
                exchange.reason.isEmpty
                    ? "\(code)"
                    : "\(code) \(exchange.reason)"
            } ?? exchange.transportError?.title ?? "")
            fact("Sent", LogFormat.size(exchange.bytesSent))
            fact("Received", LogFormat.size(exchange.bytesReceived))
        }
    }

    @ViewBuilder private func fact(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)
                Text(value).font(.callout.monospaced()).textSelection(.enabled)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SettingsCard(title) {
            content()
        }
    }

    private func marked(
        _ title: String, _ text: CoreHTTPMarkedText, part: RequestsReducer.SecretPart
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(RequestMasking.shown(text, part: part, revealed: store.revealed))
                .font(.callout.monospaced())
                .textSelection(.enabled)
            reveals(text, part: part)
        }
    }

    private func headers(_ headers: [CoreHTTPHeader], request: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Headers").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                let part: RequestsReducer.SecretPart = request
                    ? .requestHeader(index)
                    : .responseHeader(index)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(header.name).font(.callout.monospaced().weight(.semibold))
                    Text(RequestMasking.shown(header.value, part: part, revealed: store.revealed))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    reveals(header.value, part: part)
                }
            }
        }
    }

    private func shownBody(_ body: CoreHTTPBody, part: RequestsReducer.SecretPart) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if body.truncated {
                Label(
                    "Truncated: \(LogFormat.size(body.kept)) of \(LogFormat.size(body.size)) kept",
                    systemImage: "scissors"
                )
                .foregroundStyle(.orange)
            }
            if body.binary {
                Text("Binary, \(LogFormat.size(body.size))").foregroundStyle(.secondary)
            } else if body.text.isEmpty {
                Text("Empty").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(RequestMasking.shown(body.text, part: part, revealed: store.revealed))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
                reveals(body.text, part: part)
            }
        }
    }

    @ViewBuilder private func reveals(_ text: CoreHTTPMarkedText,
                                      part: RequestsReducer.SecretPart) -> some View {
        if !text.spans.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(text.spans.enumerated()), id: \.offset) { index, span in
                        let secret = RequestsReducer.Secret(part, index)
                        FocusButton(store.revealed.contains(secret)
                            ? "Hide \(span.kind.title)"
                            : "Reveal \(span.kind.title)") {
                                store.send(.toggleSecret(secret))
                            }
                            .glassControlStyle()
                            .controlSize(.small)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
