import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The touch Entitlements page: the saved account to load, the service, filter and search over its cloud titles
/// and the service's summary, beside the titles, each opening in place to show which catalogue rules decided it.
struct MobileEntitlementsSettingsPage: View {
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
            account
            if store.titles != nil {
                listing
                summary
            }
        } trailing: {
            if store.titles != nil, !store.rows.isEmpty {
                titles
            }
        }
        .onAppear {
            store.send(.appear)
        }
    }

    private var store: StoreOf<EntitlementsReducer> {
        settings.scope(state: \.entitlements, action: \.entitlements)
    }

    private var account: some View {
        MobileSettingsGroup("Account") {
            MobilePickerRow(
                "Account",
                selection: Binding(get: { store.account }, set: { store.send(.selectAccount($0)) })
            ) {
                if store.accounts.isEmpty {
                    Text("No saved accounts").tag(UUID?.none)
                }
                ForEach(store.accounts) { account in
                    Text(account.name).tag(UUID?.some(account.id))
                }
            }
            MobileButtonRow("Load Entitlements") {
                store.send(.load)
            }
            .disabled(store.busy || store.selectedAccount == nil)
            .overlay(alignment: .trailing) {
                if store.busy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 16)
                }
            }
            if case .failed(let message) = store.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mobileRowPadding()
            }
        }
    }

    private var listing: some View {
        MobileSettingsGroup {
            MobilePickerRow(
                "Service",
                selection: Binding(get: { store.service }, set: { store.send(.service($0)) })
            ) {
                ForEach(EntitlementService.allCases, id: \.self) { service in
                    Text(service.rawValue).tag(service)
                }
            }
            .accessibilityIdentifier("entitlements-service")
            MobilePickerRow(
                "Filter",
                selection: Binding(get: { store.filter }, set: { store.send(.filter($0)) })
            ) {
                ForEach(EntitlementFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            search
        }
    }

    private var search: some View {
        MobileSearchEntry(
            prompt: "Search",
            text: Binding(get: { store.query }, set: { store.send(.query($0)) })
        )
        .mobileRowPadding()
    }

    private var summary: some View {
        let summary = store.summary
        return MobileSettingsGroup("Summary") {
            fact("Source", lines: [store.service.source] + (store.report?.source(of: store.service) ?? []))
            fact("Rules Applied", lines: store.service.rules)
            fact(
                "Entitlements",
                lines: ["\(summary.held) of this service's titles are held in the account's library"]
                    + (store.report?.held ?? [])
            )
            fact(
                "Dropped",
                lines: summary.dropped.isEmpty
                    ? ["Nothing"]
                    : summary.dropped.map { "\($0.count) because \($0.reason)" }
            )
            MobileValueRow("End Result", value: "\(summary.present) offered, \(summary.droppedCount) dropped")
        }
        .accessibilityIdentifier("entitlements-summary")
    }

    private var titles: some View {
        MobileSettingsGroup("Titles") {
            ForEach(store.rows) { title in
                titleRow(title)
                if store.selection == title.id {
                    detail(title)
                }
            }
        }
        .accessibilityIdentifier("entitlements-titles")
    }

    private func titleRow(_ title: ExplainedTitle) -> some View {
        let selected = store.selection == title.id
        return Button {
            store.send(.select(
                selected
                    ? nil
                    : title.id
            ))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.game.name)
                        .lineLimit(1)
                    Text(title.game.productId)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(title.droppedBecause.map { "Dropped because \($0)" } ?? title.game.standing.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            title.game.visible
                                ? Color.secondary
                                : Color.orange
                        )
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(
                        selected
                            ? .degrees(90)
                            : .zero
                    )
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            selected
                ? .isSelected
                : []
        )
    }

    @ViewBuilder
    private func detail(_ title: ExplainedTitle) -> some View {
        fact(
            "Source",
            lines: [
                title.game.streamServiceType == "pscloud"
                    ? "PlayStation Store PS5 lists"
                    : "PlayStation Now shelves"
            ]
        )
        VStack(alignment: .leading, spacing: 6) {
            Text("Rules Applied")
            ForEach(Array(title.explanation.steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(step.rule.label)
                            .font(.footnote.weight(.semibold))
                    } icon: {
                        Image(systemName: step.outcome.symbol)
                            .foregroundStyle(step.outcome.color)
                    }
                    if !step.facts.isEmpty {
                        Text(step.facts)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .mobileRowPadding()
        fact(
            "Entitlements",
            lines: title.heldRecords.isEmpty
                ? ["None held"]
                : title.heldRecords,
            monospaced: !title.heldRecords.isEmpty
        )
        VStack(alignment: .leading, spacing: 3) {
            Text("Dropped")
            Text(title.droppedBecause.map { "Because \($0)" } ?? "No")
                .font(.footnote)
                .foregroundStyle(
                    title.game.visible
                        ? Color.secondary
                        : Color.orange
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .mobileRowPadding()
        MobileValueRow("End Result", value: title.endResult)
    }

    private func fact(_ label: String, lines: [String], monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(
                        monospaced
                            ? .footnote.monospaced()
                            : .footnote
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .mobileRowPadding()
    }
}
