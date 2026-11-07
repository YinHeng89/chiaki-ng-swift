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
        stat(.settingsRequestsStatRequests, "\(all.requests)")
        stat(.settingsRequestsStatHttpErrors, "\(all.httpErrors)")
        stat(.settingsRequestsStatTransportErrors, "\(all.transportErrors)")
    }

    @ViewBuilder private func volumeStats(_ all: CoreHTTPTally) -> some View {
        stat(.settingsRequestsStatReceived, LogFormat.size(all.bytesReceived))
        stat(.settingsRequestsStatSent, LogFormat.size(all.bytesSent))
        stat(.settingsRequestsStatInLog, "\(store.log.exchanges.count)")
    }

    private func stat(_ label: LocalizedStringResource, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            FocusButton(.settingsRequestsClearLog, role: .destructive) {
                store.send(.clearLog)
            }
            .glassControlStyle()
            .disabled(store.log.exchanges.isEmpty)
            .accessibilityIdentifier("requests-clear-log")
            FocusButton(.settingsRequestsResetCounts) {
                store.send(.resetCounts)
            }
            .glassControlStyle()
            .disabled(store.log.totals.all.requests == 0)
            .accessibilityIdentifier("requests-reset-counts")
            FocusButton(.settingsRequestsClearFilters) {
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
                TextField(String(localized: .settingsRequestsSearchUrls), text: search)
                    .textFieldStyle(.roundedBorder)
                    .menuFocusBinding($searchFocused)
                    .controllerKeyboard(
                        title: .settingsRequestsSearchUrls,
                        text: search,
                        isFocused: searchFocused
                    )
                    .accessibilityIdentifier("requests-search")
                Toggle(
                    .settingsRequestsFailuresOnly,
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
            chipRow(.settingsRequestsCredentials) {
                ForEach(RequestsReducer.CredentialFilter.allCases, id: \.self) { credential in
                    chip(credential.title, chosen: store.filter.credentials.contains(credential)) {
                        store.send(.toggleCredential(credential))
                    }
                }
            }
            Divider()
            chipRow(.settingsRequestsAreas) {
                ForEach(CoreHTTPArea.allCases, id: \.self) { area in
                    chip(area.title, chosen: store.filter.areas.contains(area)) {
                        store.send(.toggleArea(area))
                    }
                }
            }
            if !store.baseChoices.isEmpty {
                Divider()
                chipRow(.settingsRequestsBases) {
                    ForEach(store.baseChoices) { choice in
                        chip(
                            .settingsRequestsBaseChip(
                                host: choice.host,
                                lifetime: String(choice.lifetime),
                                kept: String(choice.kept)
                            ),
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

    private func chipRow(_ title: LocalizedStringResource, @ViewBuilder chips: () -> some View) -> some View {
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

    private func chip(
        _ title: LocalizedStringResource, chosen: Bool, action: @escaping () -> Void
    ) -> some View {
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
                ? .settingsRequestsNoRequests
                : .settingsRequestsNoMatchingRequests)
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
            ForEach(shown.credentials.indices, id: \.self) { index in
                Text(shown.credentials[index]).font(.caption)
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
                FocusButton(.settingsRequestsCopyCurl) {
                    store.send(.copyCurl)
                }
                .glassControlStyle()
                .disabled(!loaded)
                .accessibilityIdentifier("requests-copy-curl")
                FocusButton(.settingsRequestsCopyResponse) {
                    store.send(.copyResponse)
                }
                .glassControlStyle()
                .disabled(!loaded)
                .accessibilityIdentifier("requests-copy-response")
                FocusButton(.commonClose) {
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
                Label(.settingsRequestsMissing, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .shown(_, let detail):
                section(.settingsRequestsRequest) {
                    marked(.settingsRequestsUrl, exchange.url, part: .url)
                    headers(detail.requestHeaders, request: true)
                    shownBody(detail.requestBody, part: .requestBody)
                }
                section(.settingsRequestsResponse) {
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
            fact(.settingsRequestsFactEndpoint, exchange.label)
            fact(.settingsRequestsFactCredential, exchange.credentialLabel)
            fact(.settingsRequestsFactAttempt, "\(exchange.attempt)")
            fact(
                .settingsRequestsFactStarted,
                exchange.startedAt.formatted(date: .abbreviated, time: .standard)
            )
            fact(.settingsRequestsFactStatus, exchange.status.map { code in
                exchange.reason.isEmpty
                    ? "\(code)"
                    : "\(code) \(exchange.reason)"
            } ?? exchange.transportError.map { String(localized: $0.title) } ?? "")
            fact(.settingsRequestsStatSent, LogFormat.size(exchange.bytesSent))
            fact(.settingsRequestsStatReceived, LogFormat.size(exchange.bytesReceived))
        }
    }

    @ViewBuilder private func fact(_ label: LocalizedStringResource, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)
                Text(value).font(.callout.monospaced()).textSelection(.enabled)
            }
        }
    }

    private func section(
        _ title: LocalizedStringResource, @ViewBuilder content: () -> some View
    ) -> some View {
        SettingsCard(title) {
            content()
        }
    }

    private func marked(
        _ title: LocalizedStringResource, _ text: CoreHTTPMarkedText, part: RequestsReducer.SecretPart
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
            Text(.settingsRequestsHeaders).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
            Text(.settingsRequestsBody).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if body.truncated {
                Label(
                    .settingsRequestsTruncated(
                        kept: LogFormat.size(body.kept),
                        total: LogFormat.size(body.size)
                    ),
                    systemImage: "scissors"
                )
                .foregroundStyle(.orange)
            }
            if body.binary {
                Text(.settingsRequestsBinary(size: LogFormat.size(body.size))).foregroundStyle(.secondary)
            } else if body.text.isEmpty {
                Text(.settingsRequestsEmpty).foregroundStyle(.secondary)
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
                        let kind = String(localized: span.kind.name)
                        FocusButton(store.revealed.contains(secret)
                            ? .settingsRequestsHideSecret(kind: kind)
                            : .settingsRequestsRevealSecret(kind: kind)) {
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
