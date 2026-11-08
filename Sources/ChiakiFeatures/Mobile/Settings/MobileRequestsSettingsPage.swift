import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
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
        return MobileSettingsGroup(.mobileRequestsTotals) {
            MobileValueRow(.mobileRequestsRequests, verbatim: "\(all.requests)")
            MobileValueRow(.mobileRequestsHttpErrors, verbatim: "\(all.httpErrors)")
            MobileValueRow(.mobileRequestsTransportErrors, verbatim: "\(all.transportErrors)")
            MobileValueRow(.mobileRequestsReceived, verbatim: LogFormat.size(all.bytesReceived))
            MobileValueRow(.mobileRequestsSent, verbatim: LogFormat.size(all.bytesSent))
            MobileValueRow(.mobileRequestsInLog, verbatim: "\(store.log.exchanges.count)")
        }
    }

    private var controls: some View {
        MobileSettingsGroup {
            MobileButtonRow(.mobileRequestsClearLog, destructive: true) {
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
            MobileButtonRow(.mobileRequestsResetCounts) {
                store.send(.resetCounts)
            }
            .disabled(store.log.totals.all.requests == 0)
            .accessibilityIdentifier("requests-reset-counts")
            MobileButtonRow(.mobileRequestsClearFilters) {
                store.send(.clearFilters)
            }
            .disabled(store.filter.isEmpty)
            .accessibilityIdentifier("requests-clear-filters")
            if case .failed(let message) = store.phase {
                failure(Text(message))
                    .textSelection(.enabled)
            }
        }
    }

    private var filters: some View {
        MobileSettingsGroup(.mobileRequestsFilters) {
            MobileSearchEntry(
                prompt: .mobileRequestsSearchUrls,
                text: Binding(get: { store.filter.search }, set: { store.send(.setSearch($0)) }),
                kind: .url
            )
            .accessibilityIdentifier("requests-search")
            .mobileRowPadding()
            MobileToggleRow(
                .mobileRequestsFailuresOnly,
                isOn: Binding(get: { store.filter.failuresOnly }, set: { store.send(.setFailuresOnly($0)) })
            )
            .accessibilityIdentifier("requests-failures-only")
        }
    }

    @ViewBuilder
    private var choices: some View {
        MobileSettingsGroup(.mobileRequestsCredentials) {
            ForEach(RequestsReducer.CredentialFilter.allCases, id: \.self) { credential in
                check(Text(credential.title), chosen: store.filter.credentials.contains(credential)) {
                    store.send(.toggleCredential(credential))
                }
            }
        }
        MobileSettingsGroup(.mobileRequestsAreas) {
            ForEach(CoreHTTPArea.allCases, id: \.self) { area in
                check(Text(area.title), chosen: store.filter.areas.contains(area)) {
                    store.send(.toggleArea(area))
                }
            }
        }
        if !store.baseChoices.isEmpty {
            MobileSettingsGroup(.mobileRequestsBases) {
                ForEach(store.baseChoices) { choice in
                    check(
                        Text(verbatim: choice.host),
                        detail: Text(
                            .mobileRequestsBaseDetail(
                                lifetime: String(choice.lifetime),
                                kept: String(choice.kept),
                                base: choice.base
                            )
                        ),
                        chosen: choice.chosen
                    ) {
                        store.send(.toggleBase(choice.base))
                    }
                }
            }
        }
    }

    private func check(
        _ title: Text, detail: Text? = nil, chosen: Bool, action: @escaping () -> Void
    ) -> some View {
        FocusButton(action: action) {
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
        MobileSettingsGroup(.mobileRequestsRequests) {
            if shown.isEmpty {
                Text(
                    store.log.exchanges.isEmpty
                        ? .mobileRequestsNoRequests
                        : .mobileRequestsNoMatches
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

    private func statusSymbol(_ shown: RequestRowPresentation) -> String {
        shown.failed
            ? "exclamationmark.triangle.fill"
            : "checkmark.circle"
    }

    private func summary(of shown: RequestRowPresentation) -> some View {
        HStack(spacing: 8) {
            Text(shown.duration)
                .monospacedDigit()
            Text(shown.size)
                .monospacedDigit()
            Text(shown.area)
            ForEach(Array(shown.credentials.enumerated()), id: \.offset) { _, credential in
                Text(credential)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func row(_ exchange: CoreHTTPExchange) -> some View {
        let shown = RequestRowPresentation(exchange)
        let opened = store.detail.exchange == exchange.id
        return FocusButton {
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
                        Label(shown.status, systemImage: statusSymbol(shown))
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
                    summary(of: shown)
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
        MobileButtonRow(.mobileRequestsCopyCurl) {
            store.send(.copyCurl)
        }
        .disabled(!loaded)
        .accessibilityIdentifier("requests-copy-curl")
        MobileButtonRow(.mobileRequestsCopyResponse) {
            store.send(.copyResponse)
        }
        .disabled(!loaded)
        .accessibilityIdentifier("requests-copy-response")
        MobileButtonRow(.commonClose) {
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
            failure(Text(.mobileRequestsMissing))
        case .shown(_, let detail):
            section(.mobileRequestsRequest) {
                marked(.mobileRequestsUrl, exchange.url, part: .url)
                headers(detail.requestHeaders, request: true)
                shownBody(detail.requestBody, part: .requestBody)
            }
            section(.mobileRequestsResponse) {
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
        fact(.mobileRequestsEndpoint, exchange.label)
        fact(.mobileRequestsCredential, exchange.credentialLabel)
        fact(.mobileRequestsAttempt, "\(exchange.attempt)")
        fact(.mobileRequestsStarted, exchange.startedAt.formatted(date: .abbreviated, time: .standard))
        fact(
            .mobileRequestsStatus,
            exchange.status.map { code in
                exchange.reason.isEmpty
                    ? "\(code)"
                    : "\(code) \(exchange.reason)"
            } ?? exchange.transportError.map { String(localized: $0.title) } ?? ""
        )
        fact(.mobileRequestsSent, LogFormat.size(exchange.bytesSent))
        fact(.mobileRequestsReceived, LogFormat.size(exchange.bytesReceived))
    }

    @ViewBuilder
    private func fact(_ label: LocalizedStringResource, _ value: String) -> some View {
        if !value.isEmpty {
            MobileValueRow(label, verbatim: value)
        }
    }

    private func section(
        _ title: LocalizedStringResource,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileRowPadding()
    }

    private func marked(
        _ title: LocalizedStringResource, _ text: CoreHTTPMarkedText, part: RequestsReducer.SecretPart
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
            Text(.mobileRequestsHeaders)
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
            Text(.mobileRequestsBody)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            if body.truncated {
                Label {
                    Text(
                        .mobileRequestsTruncated(
                            kept: LogFormat.size(body.kept),
                            size: LogFormat.size(body.size)
                        )
                    )
                } icon: {
                    Image(systemName: "scissors")
                }
                .foregroundStyle(.orange)
            }
            if body.binary {
                Text(.mobileRequestsBinary(size: LogFormat.size(body.size)))
                    .foregroundStyle(.secondary)
            } else if body.text.isEmpty {
                Text(.mobileRequestsEmpty)
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
                        let kind = String(localized: span.kind.name)
                        FocusButton(
                            store.revealed.contains(secret)
                                ? .mobileRequestsHideSecret(kind: kind)
                                : .mobileRequestsRevealSecret(kind: kind)
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

    private func failure(_ message: Text) -> some View {
        Label {
            message
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileRowPadding()
    }
}
