import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI

/// Lets the user pick a saved account, load its cloud titles, and see per service which titles are offered or
/// dropped and which catalogue rules decided each one.
public struct EntitlementsSettingsView: View {
    /// The entitlements reducer that owns accounts, titles and display choices.
    public let store: StoreOf<EntitlementsReducer>
    @Environment(\.screenLayout) private var layout
    @MenuFocusState private var searchFocused: Bool

    /// Creates an entitlements settings view.
    ///
    /// - Parameter store: The entitlements reducer that owns accounts, titles and display choices.
    public init(store: StoreOf<EntitlementsReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            if case .failed(let message) = store.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if store.titles != nil {
                services
                summary
                filters
                explanationLayout {
                    titleList
                        .frame(minWidth: 320, maxWidth: 420, minHeight: 360)
                    if let title = store.selected {
                        ExplainedTitleDetail(title: title)
                    }
                }
            }
        }
        .onAppear {
            store.send(.appear)
        }
    }

    private var explanationLayout: AnyLayout {
        layout.isCompact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker(selection: Binding(get: { store.account }, set: { store.send(.selectAccount($0)) })) {
                if store.accounts.isEmpty {
                    Text(.settingsEntitlementsNoSavedAccounts).tag(UUID?.none)
                }
                ForEach(store.accounts) { account in
                    Text(account.name).tag(UUID?.some(account.id))
                }
            } label: {
                Text(.settingsEntitlementsAccount)
            }
            .frame(maxWidth: 320)
            FocusButton(.settingsEntitlementsLoad) {
                store.send(.load)
            }
            .glassControlStyle()
            .disabled(store.busy || store.selectedAccount == nil)
            if store.busy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var services: some View {
        FocusableSegments(
            options: EntitlementService.allCases,
            title: \.title,
            selection: Binding(get: { store.service }, set: { store.send(.service($0)) })
        )
        .accessibilityLabel(.settingsEntitlementsService)
        .accessibilityIdentifier("entitlements-service")
    }

    private var titleList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.rows) { title in
                    titleRow(title)
                }
            }
        }
        .accessibilityIdentifier("entitlements-titles")
    }

    private func titleRow(_ title: ExplainedTitle) -> some View {
        let selected = store.selection == title.id
        return FocusButton {
            store.send(.select(title.id))
        } label: {
            ExplainedTitleRow(title: title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    selected
                        ? Palette.accent.opacity(0.18)
                        : Color.clear,
                    in: .rect(cornerRadius: 8)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected
            ? .isSelected
            : [])
    }

    private var summary: some View {
        let summary = store.summary
        return VStack(alignment: .leading, spacing: 8) {
            EntitlementFact(.settingsEntitlementsFactSource) {
                Text(store.service.source)
                lines(store.report?.source(of: store.service) ?? [])
            }
            EntitlementFact(.settingsEntitlementsFactRules) {
                lines(store.service.rules)
            }
            EntitlementFact(.settingsEntitlementsFactEntitlements) {
                Text(.settingsEntitlementsHeldInLibrary(count: summary.held))
                lines(store.report?.held ?? [])
            }
            EntitlementFact(.settingsEntitlementsFactDropped) {
                if summary.dropped.isEmpty {
                    Text(.settingsEntitlementsNothingDropped)
                }
                ForEach(summary.dropped, id: \.reason) { dropped in
                    Text(.settingsEntitlementsDroppedGroup(count: dropped.count, reason: dropped.reason))
                }
            }
            EntitlementFact(.settingsEntitlementsFactEndResult) {
                Text(.settingsEntitlementsEndTotals(offered: summary.present, dropped: summary.droppedCount))
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("entitlements-summary")
    }

    private func lines(_ lines: [LocalizedStringResource]) -> some View {
        ForEach(lines.indices, id: \.self) {
            Text(lines[$0])
        }
    }

    private var query: Binding<String> {
        Binding(get: { store.query }, set: { store.send(.query($0)) })
    }

    private var filters: some View {
        HStack(spacing: 12) {
            FocusableSegments(
                options: EntitlementFilter.allCases,
                title: \.title,
                selection: Binding(get: { store.filter }, set: { store.send(.filter($0)) })
            )
            .accessibilityLabel(.settingsEntitlementsFilter)
            TextField(String(localized: .commonSearch), text: query)
                .textFieldStyle(.roundedBorder)
                .menuFocusBinding($searchFocused)
                .controllerKeyboard(title: .commonSearch, text: query, isFocused: searchFocused)
                .frame(maxWidth: 280)
        }
    }
}

private struct ExplainedTitleRow: View {
    let title: ExplainedTitle
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.game.name).lineLimit(1)
            Text(title.game.productId).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            Text(
                title.droppedBecause.map { .settingsEntitlementsDroppedBecause(reason: $0) }
                    ?? title.game.standing.label
            )
            .lineLimit(2)
            .font(.caption.weight(.semibold))
            .foregroundStyle(title.game.visible
                ? Color.secondary
                : Color.orange)
        }
    }
}

private struct EntitlementFact<Content: View>: View {
    let label: LocalizedStringResource
    @ViewBuilder let content: Content

    init(_ label: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout.weight(.semibold))
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                content
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ExplainedTitleDetail: View {
    let title: ExplainedTitle
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.game.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                Text(title.game.productId).font(.callout.monospaced()).textSelection(.enabled)
                EntitlementFact(.settingsEntitlementsFactSource) {
                    Text(title.game.streamServiceType == "pscloud"
                        ? .settingsEntitlementsDetailSourcePsCloud
                        : .settingsEntitlementsDetailSourcePsNow)
                }
                EntitlementFact(.settingsEntitlementsFactRules) {
                    ForEach(Array(title.explanation.steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: step.outcome.symbol).foregroundStyle(step.outcome.color)
                            Text(step.rule.label).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                            Text(step.facts).font(.callout.monospaced())
                        }
                    }
                }
                EntitlementFact(.settingsEntitlementsFactEntitlements) {
                    if title.heldRecords.isEmpty {
                        Text(.settingsEntitlementsNoneHeld)
                    }
                    ForEach(title.heldRecords, id: \.self) {
                        Text($0).font(.callout.monospaced())
                    }
                }
                EntitlementFact(.settingsEntitlementsFactDropped) {
                    Text(title.droppedBecause.map { .settingsEntitlementsDetailBecause(reason: $0) }
                        ?? .settingsEntitlementsDetailNotDropped)
                        .foregroundStyle(title.game.visible
                            ? Color.secondary
                            : Color.orange)
                }
                EntitlementFact(.settingsEntitlementsFactEndResult) {
                    Text(title.endResult)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Presentation of a catalogue rule outcome in the entitlements detail.
extension CatalogStepOutcome {
    /// The SF Symbol name shown beside a rule with this outcome.
    public var symbol: String {
        switch self {
        case .passed:
            "checkmark.circle"
        case .failed:
            "xmark.circle"
        case .noted:
            "info.circle"
        case .unchecked:
            "questionmark.circle"
        }
    }

    /// The colour of the symbol shown beside a rule with this outcome.
    public var color: Color {
        switch self {
        case .passed:
            .green
        case .failed:
            .red
        case .noted, .unchecked:
            .secondary
        }
    }
}

/// Presentation of one catalogue explanation step.
extension CatalogExplanation.Step {
    /// The step's product, ownership, title number and tier values that are present, separated by spaces.
    public var facts: String {
        [productID, ownershipID, titleNumber, tier.map { String(localized: $0.label) }].compactMap(\.self)
            .joined(separator: "  ")
    }
}

/// Presentation of catalogue rules in the entitlements detail.
extension CatalogRule {
    /// The rule's display name.
    public var label: LocalizedStringResource {
        switch self {
        case .listedInCatalog:
            .settingsEntitlementsRuleListedInCatalog
        case .platform:
            .settingsEntitlementsRulePlatform
        case .service:
            .settingsEntitlementsRuleService
        case .includedWithPlus:
            .settingsEntitlementsRuleIncludedWithPlus
        case .tier:
            .settingsEntitlementsRuleTier
        case .countsAsGame:
            .settingsEntitlementsRuleCountsAsGame
        case .libraryMatch:
            .settingsEntitlementsRuleLibraryMatch
        case .mergedIntoListing:
            .settingsEntitlementsRuleMergedIntoListing
        case .ownListing:
            .settingsEntitlementsRuleOwnListing
        case .ownedDuplicate:
            .settingsEntitlementsRuleOwnedDuplicate
        case .trialSuperseded:
            .settingsEntitlementsRuleTrialSuperseded
        case .discUpgrade:
            .settingsEntitlementsRuleDiscUpgrade
        case .ownership:
            .settingsEntitlementsRuleOwnership
        case .ps5Native:
            .settingsEntitlementsRuleNativePs5
        case .duplicateLaunch:
            .settingsEntitlementsRuleDuplicateLaunch
        case .alreadyOwned:
            .settingsEntitlementsRuleAlreadyOwned
        case .listStreamability:
            .settingsEntitlementsRuleListStreamability
        case .storefront:
            .settingsEntitlementsRuleStorefront
        case .rememberedRefusal:
            .settingsEntitlementsRuleRememberedRefusal
        case .release:
            .settingsEntitlementsRuleRelease
        case .sameProduct:
            .settingsEntitlementsRuleSameProduct
        case .accessRoute:
            .settingsEntitlementsRuleAccessRoute
        case .premiumBranding:
            .settingsEntitlementsRulePremiumBranding
        case .premiumEntitlement:
            .settingsEntitlementsRulePremiumEntitlement
        case .joinedByEntitlement:
            .settingsEntitlementsRuleJoinedByEntitlement
        case .joinedByProduct:
            .settingsEntitlementsRuleJoinedByProduct
        case .bundleOwnership:
            .settingsEntitlementsRuleBundleOwnership
        }
    }
}

/// Derived descriptions of an explained title for the entitlements panel.
extension ExplainedTitle {
    /// The distinct ownership records the catalogue matched while explaining the title, in the order they
    /// appeared.
    public var heldRecords: [String] {
        var records: [String] = []
        for step in explanation.steps {
            if let record = step.ownershipID, !records.contains(record) {
                records.append(record)
            }
        }
        return records
    }

    /// A line saying whether the title is offered, and with which standing if it is.
    public var endResult: LocalizedStringResource {
        game.visible
            ? .settingsEntitlementsOffered(standing: String(localized: game.standing.label))
            : .settingsEntitlementsNotOffered
    }

    /// The reason the title was dropped, or `nil` when it is offered.
    public var droppedBecause: String? {
        game.visible
            ? nil
            : CloudLibraryLog.droppedBecause(game.hideReason ?? "", service: game.streamServiceType)
    }
}

/// Describes how the catalogue was fetched, as lines of text for the entitlements panel.
extension CatalogFetchReport {
    /// Returns lines describing where the given service's title list was read from, how complete it is and
    /// when it was fetched.
    public func source(of service: EntitlementService) -> [LocalizedStringResource] {
        switch service {
        case .psNow:
            psNowSource
        case .psCloud:
            psCloudSource
        }
    }

    private static func dated(_ moment: Date) -> String {
        moment.formatted(date: .abbreviated, time: .shortened)
    }

    private var psNowSource: [LocalizedStringResource] {
        let titles = String(psNowTitles)
        let fetched = Self.dated(listFetchedAt)
        let copies: LocalizedStringResource = copiesChecked.map {
            .settingsEntitlementsReportCopiesChecked(
                asked: String($0.asked),
                answered: String($0.answered),
                uncovered: String(withoutACoveredCopy)
            )
        } ?? .settingsEntitlementsReportCopiesUnchecked
        return [
            fromAccountService
                ? .settingsEntitlementsReportPsNowFromAccount(count: titles)
                : .settingsEntitlementsReportPsNowFromStore(count: titles),
            complete
                ? .settingsEntitlementsReportListComplete(date: fetched)
                : .settingsEntitlementsReportListIncomplete(date: fetched),
            copies
        ]
    }

    private var psCloudSource: [LocalizedStringResource] {
        var lines: [LocalizedStringResource] = [
            .settingsEntitlementsReportPsCloudTitles(count: String(psCloudTitles))
        ]
        if let audience {
            lines.append(
                .settingsEntitlementsReportAudience(
                    country: audience.country,
                    language: audience.language,
                    age: String(audience.age)
                )
            )
            lines.append(premiumCategory.map {
                .settingsEntitlementsReportPremiumCategory(
                    count: String($0.titles),
                    date: Self.dated($0.fetchedAt)
                )
            } ?? .settingsEntitlementsReportPremiumSilent)
        } else {
            lines.append(.settingsEntitlementsReportAudienceUnknown)
        }
        return lines
    }

    /// Lines describing the account's library fetch and membership tier.
    public var held: [LocalizedStringResource] {
        let membership: LocalizedStringResource = tier.map {
            .settingsEntitlementsReportTier(tier: String(localized: $0.label))
        } ?? .settingsEntitlementsReportTierUnknown
        switch library {
        case .unknown:
            return [.settingsEntitlementsReportLibraryUnfetched, membership]
        case .unavailable:
            return [.settingsEntitlementsReportLibraryUnavailable, membership]
        case let .fetched(moment, records):
            return [
                .settingsEntitlementsReportLibraryHolds(count: String(records), date: Self.dated(moment)),
                membership
            ]
        }
    }
}
