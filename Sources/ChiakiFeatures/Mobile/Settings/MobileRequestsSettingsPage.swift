import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The touch Requests page: the request totals, the log's actions and its filters, beside the recorded HTTP
/// exchanges, each opening in place to show its facts, headers and bodies with masked secrets that can be revealed.
struct MobileRequestsSettingsPage: View {
    /// The settings.
    let settings: StoreOf<SettingsFeature>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    var body: some View {
        MobileSettingsForm {
            totals
            controls
            filters
            choices
        } trailing: {
            list
        }
        .onAppear {
            settings.send(.requests(.appear))
        }
        .onDisappear {
            settings.send(.requests(.disappear))
        }
    }

    private var store: StoreOf<RequestsReducer> {
        settings.scope(state: \.requests, action: \.requests)
    }

    private var totals: some View {
        let all = store.log.totals.all
        return MobileSettingsGroup("Totals") {
            MobileValueRow("Requests", value: "\(all.requests)")
            MobileValueRow("HTTP Errors", value: "\(all.httpErrors)")
            MobileValueRow("Transport Errors", value: "\(all.transportErrors)")
            MobileValueRow("Received", value: LogFormat.size(all.bytesReceived))
            MobileValueRow("Sent", value: LogFormat.size(all.bytesSent))
            MobileValueRow("In Log", value: "\(store.log.exchanges.count)")
        }
    }

    private var controls: some View {
        MobileSettingsGroup {
            MobileButtonRow("Clear Log", destructive: true) {
                store.send(.clearLog)
            }
            .disabled(store.log.exchanges.isEmpty)
            .overlay(alignment: .trailing) {
                if store.loading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 16)
                }
            }
            .accessibilityIdentifier("requests-clear-log")
            MobileButtonRow("Reset Counts") {
                store.send(.resetCounts)
            }
            .disabled(store.log.totals.all.requests == 0)
            .accessibilityIdentifier("requests-reset-counts")
            MobileButtonRow("Clear Filters") {
                store.send(.clearFilters)
            }
            .disabled(store.filter.isEmpty)
            .accessibilityIdentifier("requests-clear-filters")
            if case .failed(let message) = store.phase {
                failure(message)
                    .textSelection(.enabled)
            }
        }
    }

    private var filters: some View {
        MobileSettingsGroup("Filters") {
            MobileSearchEntry(
                prompt: "Search URLs",
                text: Binding(get: { store.filter.search }, set: { store.send(.setSearch($0)) }),
                kind: .url
            )
            .accessibilityIdentifier("requests-search")
            .mobileRowPadding()
            MobileToggleRow(
                "Failures Only",
                isOn: Binding(get: { store.filter.failuresOnly }, set: { store.send(.setFailuresOnly($0)) })
            )
            .accessibilityIdentifier("requests-failures-only")
        }
    }

    @ViewBuilder
    private var choices: some View {
        MobileSettingsGroup("Credentials") {
            ForEach(RequestsReducer.CredentialFilter.allCases, id: \.self) { credential in
                check(credential.title, chosen: store.filter.credentials.contains(credential)) {
                    store.send(.toggleCredential(credential))
                }
            }
        }
        MobileSettingsGroup("Areas") {
            ForEach(CoreHTTPArea.allCases, id: \.self) { area in
                check(area.title, chosen: store.filter.areas.contains(area)) {
                    store.send(.toggleArea(area))
                }
            }
        }
        if !store.baseChoices.isEmpty {
            MobileSettingsGroup("Bases") {
                ForEach(store.baseChoices) { choice in
                    check(
                        choice.host,
                        detail: "\(choice.lifetime)  \(choice.kept) in log\n\(choice.base)",
                        chosen: choice.chosen
                    ) {
                        store.send(.toggleBase(choice.base))
                    }
                }
            }
        }
    }

    private func check(
        _ title: String, detail: String? = nil, chosen: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MobileRowTitle(title: title, detail: detail)
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            chosen
                ? .isSelected
                : []
        )
    }

    @ViewBuilder
    private var list: some View {
        let shown = store.shown
        MobileSettingsGroup("Requests") {
            if shown.isEmpty {
                Text(
                    store.log.exchanges.isEmpty
                        ? "No requests"
                        : "No matching requests"
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mobileRowPadding()
            } else {
                ForEach(shown) { exchange in
                    row(exchange)
                    if store.detail.exchange == exchange.id {
                        detail(exchange)
                    }
                }
            }
        }
    }

    private func row(_ exchange: CoreHTTPExchange) -> some View {
        let shown = RequestRowPresentation(exchange)
        let opened = store.detail.exchange == exchange.id
        return Button {
            store.send(
                opened
                    ? .close
                    : .open(exchange.id)
            )
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(shown.method)
                            .font(.callout.monospaced().weight(.semibold))
                        Label(
                            shown.status,
                            systemImage: shown.failed
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(
                            shown.failed
                                ? Color.red
                                : Color.secondary
                        )
                        Spacer(minLength: 8)
                        Text(shown.time)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(shown.base)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(shown.path)
                        .font(.callout.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        Text(shown.duration)
                            .monospacedDigit()
                        Text(shown.size)
                            .monospacedDigit()
                        Text(shown.area)
                        ForEach(shown.credentials, id: \.self) { credential in
                            Text(credential)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(
                        opened
                            ? .degrees(90)
                            : .zero
                    )
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("requests-row-\(exchange.id)")
        .accessibilityAddTraits(
            opened
                ? .isSelected
                : []
        )
    }

    @ViewBuilder
    private func detail(_ exchange: CoreHTTPExchange) -> some View {
        let loaded = isLoaded
        MobileButtonRow("Copy as cURL") {
            store.send(.copyCurl)
        }
        .disabled(!loaded)
        .accessibilityIdentifier("requests-copy-curl")
        MobileButtonRow("Copy Response") {
            store.send(.copyResponse)
        }
        .disabled(!loaded)
        .accessibilityIdentifier("requests-copy-response")
        MobileButtonRow("Close") {
            store.send(.close)
        }
        .accessibilityIdentifier("requests-close-detail")
        facts(exchange)
        switch store.detail {
        case .closed:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .mobileRowPadding()
        case .missing:
            failure("This request is no longer in the log.")
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

    private var isLoaded: Bool {
        if case .shown = store.detail {
            return true
        }
        return false
    }

    @ViewBuilder
    private func facts(_ exchange: CoreHTTPExchange) -> some View {
        fact("Endpoint", exchange.label)
        fact("Credential", exchange.credentialLabel)
        fact("Attempt", "\(exchange.attempt)")
        fact("Started", exchange.startedAt.formatted(date: .abbreviated, time: .standard))
        fact(
            "Status",
            exchange.status.map { code in
                exchange.reason.isEmpty
                    ? "\(code)"
                    : "\(code) \(exchange.reason)"
            } ?? exchange.transportError?.title ?? ""
        )
        fact("Sent", LogFormat.size(exchange.bytesSent))
        fact("Received", LogFormat.size(exchange.bytesReceived))
    }

    @ViewBuilder
    private func fact(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            MobileValueRow(label, value: value)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileRowPadding()
    }

    private func marked(
        _ title: String, _ text: CoreHTTPMarkedText, part: RequestsReducer.SecretPart
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(RequestMasking.shown(text, part: part, revealed: store.revealed))
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            reveals(text, part: part)
        }
    }

    private func headers(_ headers: [CoreHTTPHeader], request: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Headers")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                let part: RequestsReducer.SecretPart = request
                    ? .requestHeader(index)
                    : .responseHeader(index)
                VStack(alignment: .leading, spacing: 2) {
                    Text(header.name)
                        .font(.callout.monospaced().weight(.semibold))
                    Text(RequestMasking.shown(header.value, part: part, revealed: store.revealed))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    reveals(header.value, part: part)
                }
            }
        }
    }

    private func shownBody(_ body: CoreHTTPBody, part: RequestsReducer.SecretPart) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            if body.truncated {
                Label(
                    "Truncated: \(LogFormat.size(body.kept)) of \(LogFormat.size(body.size)) kept",
                    systemImage: "scissors"
                )
                .foregroundStyle(.orange)
            }
            if body.binary {
                Text("Binary, \(LogFormat.size(body.size))")
                    .foregroundStyle(.secondary)
            } else if body.text.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func reveals(_ text: CoreHTTPMarkedText, part: RequestsReducer.SecretPart) -> some View {
        if !text.spans.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(text.spans.enumerated()), id: \.offset) { index, span in
                        let secret = RequestsReducer.Secret(part, index)
                        Button(
                            store.revealed.contains(secret)
                                ? "Hide \(span.kind.title)"
                                : "Reveal \(span.kind.title)"
                        ) {
                            store.send(.toggleSecret(secret))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func failure(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mobileRowPadding()
    }
}
