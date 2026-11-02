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
            Picker(
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
            .frame(maxWidth: 320)
            FocusButton("Load entitlements") {
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
            title: \.rawValue,
            selection: Binding(get: { store.service }, set: { store.send(.service($0)) })
        )
        .accessibilityLabel("Service")
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
            EntitlementFact("Source") {
                Text(store.service.source)
                ForEach(store.report?.source(of: store.service) ?? [], id: \.self) {
                    Text($0)
                }
            }
            EntitlementFact("Rules applied") {
                ForEach(store.service.rules, id: \.self) {
                    Text($0)
                }
            }
            EntitlementFact("Entitlements") {
                Text("\(summary.held) of this service's titles are held in the account's library")
                ForEach(store.report?.held ?? [], id: \.self) {
                    Text($0)
                }
            }
            EntitlementFact("Dropped") {
                if summary.dropped.isEmpty {
                    Text("Nothing")
                }
                ForEach(summary.dropped, id: \.reason) { dropped in
                    Text("\(dropped.count) because \(dropped.reason)")
                }
            }
            EntitlementFact("End result") {
                Text("\(summary.present) offered, \(summary.droppedCount) dropped")
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("entitlements-summary")
    }

    private var query: Binding<String> {
        Binding(get: { store.query }, set: { store.send(.query($0)) })
    }

    private var filters: some View {
        HStack(spacing: 12) {
            FocusableSegments(
                options: EntitlementFilter.allCases,
                title: \.rawValue,
                selection: Binding(get: { store.filter }, set: { store.send(.filter($0)) })
            )
            .accessibilityLabel("Filter")
            TextField("Search", text: query)
                .textFieldStyle(.roundedBorder)
                .menuFocusBinding($searchFocused)
                .controllerKeyboard(title: "Search", text: query, isFocused: searchFocused)
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
            Text(title.droppedBecause.map { "Dropped because \($0)" } ?? title.game.standing.label)
                .lineLimit(2)
                .font(.caption.weight(.semibold))
                .foregroundStyle(title.game.visible
                    ? Color.secondary
                    : Color.orange)
        }
    }
}

private struct EntitlementFact<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
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
                EntitlementFact("Source") {
                    Text(title.game.streamServiceType == "pscloud"
                        ? "PlayStation Store PS5 lists"
                        : "PlayStation Now shelves")
                }
                EntitlementFact("Rules applied") {
                    ForEach(Array(title.explanation.steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: step.outcome.symbol).foregroundStyle(step.outcome.color)
                            Text(step.rule.label).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                            Text(step.facts).font(.callout.monospaced())
                        }
                    }
                }
                EntitlementFact("Entitlements") {
                    if title.heldRecords.isEmpty {
                        Text("None held")
                    }
                    ForEach(title.heldRecords, id: \.self) {
                        Text($0).font(.callout.monospaced())
                    }
                }
                EntitlementFact("Dropped") {
                    Text(title.droppedBecause.map { "Because \($0)" } ?? "No")
                        .foregroundStyle(title.game.visible
                            ? Color.secondary
                            : Color.orange)
                }
                EntitlementFact("End result") {
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
        [productID, ownershipID, titleNumber, tier?.label].compactMap(\.self)
            .joined(separator: "  ")
    }
}

/// Presentation of catalogue rules in the entitlements detail.
extension CatalogRule {
    /// The rule's display name.
    public var label: String {
        switch self {
        case .listedInCatalog:
            "Listed for streaming"
        case .platform:
            "Platform"
        case .service:
            "Service"
        case .includedWithPlus:
            "Included with PS Plus"
        case .tier:
            "Tier"
        case .countsAsGame:
            "Counts as a game"
        case .libraryMatch:
            "Library match"
        case .mergedIntoListing:
            "Merged into listing"
        case .ownListing:
            "Own listing"
        case .ownedDuplicate:
            "Owned duplicate"
        case .trialSuperseded:
            "Trial superseded"
        case .discUpgrade:
            "Disc upgrade"
        case .ownership:
            "Ownership"
        case .ps5Native:
            "PS5 native"
        case .duplicateLaunch:
            "Duplicate launch"
        case .alreadyOwned:
            "Already owned"
        case .listStreamability:
            "List streamability"
        case .storefront:
            "Storefront"
        case .rememberedRefusal:
            "Remembered refusal"
        case .release:
            "Release"
        case .sameProduct:
            "Same product"
        case .accessRoute:
            "Access route"
        case .premiumBranding:
            "Premium branding"
        case .premiumEntitlement:
            "Premium entitlement"
        case .joinedByEntitlement:
            "Joined by entitlement"
        case .joinedByProduct:
            "Joined by product"
        case .bundleOwnership:
            "Bundle ownership"
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
    public var endResult: String {
        game.visible
            ? "Offered: \(game.standing.label)"
            : "Not offered"
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
    public func source(of service: EntitlementService) -> [String] {
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

    private var psNowSource: [String] {
        let origin = fromAccountService
            ? "read through the account's PlayStation Now session"
            : "read from the public store because the account's session did not answer"
        let completeness = complete
            ? "complete"
            : "incomplete"
        let copies = copiesChecked.map {
            "Streaming copies were asked about for \($0.asked) PS4 titles and \($0.answered) were answered, "
                + "of which \(withoutACoveredCopy) have no copy a plan covers"
        } ?? "Streaming copies were not checked because the account's country, language or age is not known"
        return [
            "\(psNowTitles) titles on the PlayStation Now shelves, \(origin)",
            "The list is \(completeness) and was fetched \(Self.dated(listFetchedAt))",
            copies
        ]
    }

    private var psCloudSource: [String] {
        var lines = ["\(psCloudTitles) titles on the PlayStation Store's PS5 lists"]
        if let audience {
            lines.append(
                "Asked as country \(audience.country), language \(audience.language) and age \(audience.age), "
                    + "taken from the account's sign-in"
            )
            lines.append(premiumCategory.map {
                "The Premium streaming category gave \($0.titles) included titles, fetched \(Self.dated($0.fetchedAt))"
            } ??
                "The Premium streaming category has not answered, so inclusion falls back to the store lists")
        } else {
            lines.append(
                "The account's country, language or age is not known, so the Premium streaming category was "
                    + "not asked for and inclusion falls back to the store lists"
            )
        }
        return lines
    }

    /// Lines describing the account's library fetch and membership tier.
    public var held: [String] {
        let membership = tier == nil
            ? "The membership tier is not known"
            : "Membership tier: \(tier?.label ?? "none")"
        switch library {
        case .unknown:
            return ["The library has not been fetched", membership]
        case .unavailable:
            return ["The library could not be fetched, so ownership is unknown", membership]
        case let .fetched(moment, records):
            return ["The library holds \(records) records, fetched \(Self.dated(moment))", membership]
        }
    }
}
