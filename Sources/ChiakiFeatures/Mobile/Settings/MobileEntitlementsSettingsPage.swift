import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
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
        MobileSettingsGroup(.mobileEntitlementsAccount) {
            MobilePickerRow(
                .mobileEntitlementsAccount,
                selection: Binding(get: { store.account }, set: { store.send(.selectAccount($0)) }),
                choices: store.accounts.isEmpty
                    ? [nil]
                    : store.accounts.map { UUID?.some($0.id) },
                verbatimLabel: { id in
                    store.accounts.first { $0.id == id }?.name
                        ?? String(localized: .mobileEntitlementsNoAccounts)
                }
            )
            MobileButtonRow(.mobileEntitlementsLoad) {
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
                .mobileEntitlementsService,
                selection: Binding(get: { store.service }, set: { store.send(.service($0)) }),
                choices: EntitlementService.allCases
            ) { service in
                service.title
            }
            .accessibilityIdentifier("entitlements-service")
            MobilePickerRow(
                .mobileEntitlementsFilter,
                selection: Binding(get: { store.filter }, set: { store.send(.filter($0)) }),
                choices: EntitlementFilter.allCases
            ) { filter in
                filter.title
            }
            search
        }
    }

    private var search: some View {
        MobileSearchEntry(
            prompt: .commonSearch,
            text: Binding(get: { store.query }, set: { store.send(.query($0)) })
        )
        .mobileRowPadding()
    }

    private var summary: some View {
        let summary = store.summary
        return MobileSettingsGroup(.mobileEntitlementsSummary) {
            fact(
                .mobileEntitlementsSource,
                lines: [Text(store.service.source)]
                    + (store.report?.source(of: store.service) ?? []).map { Text($0) }
            )
            fact(.mobileEntitlementsRulesApplied, lines: store.service.rules.map { Text($0) })
            fact(
                .mobileEntitlementsEntitlements,
                lines: [Text(.mobileEntitlementsHeldCount(count: summary.held))]
                    + (store.report?.held ?? []).map { Text($0) }
            )
            fact(
                .mobileEntitlementsDropped,
                lines: summary.dropped.isEmpty
                    ? [Text(.mobileEntitlementsNothing)]
                    : summary.dropped.map {
                        Text(.mobileEntitlementsDroppedReason(count: $0.count, reason: $0.reason))
                    }
            )
            MobileValueRow(
                .mobileEntitlementsEndResult,
                value: .mobileEntitlementsEndResultValue(
                    offered: summary.present,
                    dropped: summary.droppedCount
                )
            )
        }
        .accessibilityIdentifier("entitlements-summary")
    }

    private var titles: some View {
        MobileSettingsGroup(.mobileEntitlementsTitles) {
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
        return FocusButton {
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
                    (title.droppedBecause.map { Text(.mobileEntitlementsDroppedBecause(reason: $0)) }
                        ?? Text(title.game.standing.label))
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
            .mobileEntitlementsSource,
            lines: [
                Text(
                    title.game.streamServiceType == "pscloud"
                        ? .mobileEntitlementsSourcePsCloud
                        : .mobileEntitlementsSourcePsNow
                )
            ]
        )
        VStack(alignment: .leading, spacing: 6) {
            Text(.mobileEntitlementsRulesApplied)
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
            .mobileEntitlementsEntitlements,
            lines: title.heldRecords.isEmpty
                ? [Text(.mobileEntitlementsNoneHeld)]
                : title.heldRecords.map { Text($0) },
            monospaced: !title.heldRecords.isEmpty
        )
        VStack(alignment: .leading, spacing: 3) {
            Text(.mobileEntitlementsDropped)
            (title.droppedBecause.map { Text(.mobileEntitlementsBecause(reason: $0)) }
                ?? Text(.mobileEntitlementsNo))
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
        MobileValueRow(.mobileEntitlementsEndResult, value: title.endResult)
    }

    private func fact(
        _ label: LocalizedStringResource,
        lines: [Text],
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                line
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
