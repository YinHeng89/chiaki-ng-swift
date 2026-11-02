import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI

/// Lists every core cache with its size and entry count, lets the user refresh, inspect a cache's records and
/// clear one cache or all of them. A cache's figures drop under its name when the row is too narrow for both.
public struct CachesSettingsView: View {
    /// The caches reducer the pane reads and sends actions to.
    public let store: StoreOf<CachesReducer>

    /// Creates a caches settings view.
    ///
    /// - Parameter store: The caches reducer the pane reads and sends actions to.
    public init(store: StoreOf<CachesReducer>) {
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
            if !store.summaries.isEmpty || store.phase == .ready {
                SettingsCard {
                    ForEach(Array(store.summaries.enumerated()), id: \.element.id) { index, summary in
                        if index > 0 {
                            Divider()
                        }
                        cacheRow(CacheSummaryPresentation(summary, decoded: store.decodedArtwork))
                        if store.entries.cache == summary.id {
                            entries
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            FocusButton("Refresh") {
                store.send(.load)
            }
            .glassControlStyle()
            .disabled(store.busy)
            .accessibilityIdentifier("caches-refresh")
            FocusButton("Clear all", role: .destructive) {
                store.send(.askClear(.all))
            }
            .glassControlStyle()
            .disabled(store.busy || !store.holdsAnything)
            .accessibilityIdentifier("caches-clear-all")
            if store.busy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func cacheRow(_ cache: CacheSummaryPresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(cache.title).font(.callout.weight(.medium)).fixedSize()
                Spacer(minLength: 8)
                cacheFigures(cache)
                cacheButtons(cache)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text(cache.title).font(.callout.weight(.medium))
                    Spacer(minLength: 8)
                    cacheButtons(cache)
                }
                HStack(spacing: 16) {
                    cacheFigures(cache)
                }
            }
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func cacheFigures(_ cache: CacheSummaryPresentation) -> some View {
        Text(cache.memory ?? "").foregroundStyle(.secondary).monospacedDigit()
            .frame(width: 110, alignment: .trailing)
        Text(cache.entries).foregroundStyle(.secondary).monospacedDigit()
            .frame(width: 110, alignment: .trailing)
        Text(cache.size).foregroundStyle(.secondary).monospacedDigit()
            .frame(width: 90, alignment: .trailing)
    }

    @ViewBuilder private func cacheButtons(_ cache: CacheSummaryPresentation) -> some View {
        let opened = store.entries.cache == cache.id
        FocusButton(opened
            ? "Hide entries"
            : "Show entries") {
                store.send(opened
                    ? .close
                    : .open(cache.id))
            }
            .glassControlStyle()
            .disabled(cache.isEmpty && !opened)
            .accessibilityIdentifier("caches-entries-\(cache.id)")
        FocusButton("Clear", role: .destructive) {
            store.send(.askClear(.one(cache.id)))
        }
        .glassControlStyle()
        .disabled(store.busy || cache.isEmpty)
        .accessibilityIdentifier("caches-clear-\(cache.id)")
    }

    @ViewBuilder private var entries: some View {
        switch store.entries {
        case .closed:
            EmptyView()
        case .loading:
            ProgressView().controlSize(.small)
        case .failed(_, let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .shown(_, let entries):
            LazyVStack(alignment: .leading, spacing: 10) {
                entryHeader
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Divider()
                    CacheEntryRow(entry: CacheEntryPresentation(entry, accountNames: store.accountNames))
                }
            }
            .padding(.leading, 12)
        }
    }

    private var entryHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("About").frame(maxWidth: .infinity, alignment: .leading)
            Text("Size").frame(width: CacheEntryRow.sizeWidth, alignment: .trailing)
            Text("Stored").frame(width: CacheEntryRow.dateWidth, alignment: .trailing)
            Text("Expires").frame(width: CacheEntryRow.dateWidth, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct CacheEntryRow: View {
    static let sizeWidth: CGFloat = 90
    static let dateWidth: CGFloat = 170
    let entry: CacheEntryPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(entry.subjects) { subject in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(subject.label).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .leading)
                        Text(subject.value).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.size).monospacedDigit()
                .frame(width: Self.sizeWidth, alignment: .trailing)
            Text(entry.stored).monospacedDigit()
                .frame(width: Self.dateWidth, alignment: .trailing)
            Text(entry.expires).monospacedDigit()
                .frame(width: Self.dateWidth, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

extension CacheKind {
    /// The human-readable name shown for this cache in the caches settings pane.
    public var title: String {
        switch self {
        case .streamableLists:
            "Streamable game lists"
        case .includedTitles:
            "PlayStation Plus titles"
        case .libraries:
            "Libraries"
        case .refusals:
            "Stream refusals"
        case .gameDetails:
            "Game details"
        case .images:
            "Images"
        case .forSaleTitles:
            "Available to buy"
        case .playedGames:
            "Played games"
        }
    }
}

/// One row of the caches pane: a cache's name, entry count, disk size and, for images, decoded artwork held
/// in memory.
public struct CacheSummaryPresentation: Equatable, Identifiable {
    /// The cache this row describes.
    public let id: CacheKind
    /// The display name of the cache.
    public let title: String
    /// The entry count, worded as "1 entry" or "N entries".
    public let entries: String
    /// The bytes stored on disk, formatted for display.
    public let size: String
    /// How many decoded artwork images are held in memory; only set for the images cache.
    public let memory: String?
    /// Whether the cache has no entries and, for images, no decoded artwork either.
    public let isEmpty: Bool

    /// Formats a core cache summary for display.
    ///
    /// - Parameters:
    ///   - summary: The counts and size the core reports for one cache.
    ///   - decoded: The number of decoded artwork images in memory, counted only for the images cache.
    public init(_ summary: CacheSummary, decoded: Int = 0) {
        id = summary.id
        title = summary.id.title
        entries = summary.entries == 1
            ? "1 entry"
            : "\(summary.entries) entries"
        size = LogFormat.size(summary.bytes)
        let artwork = summary.id == .images
            ? decoded
            : 0
        memory = summary.id == .images
            ? "\(artwork) in memory"
            : nil
        isEmpty = summary.entries == 0 && artwork == 0
    }
}

/// The display form of one stored cache record: what it is about, its size and when it was stored and
/// expires.
public struct CacheEntryPresentation: Equatable {
    /// A labelled fact identifying what a cache record belongs to, such as its account, store region or
    /// product.
    public struct Subject: Equatable, Identifiable {
        /// The kind of fact, such as "Account" or "Product".
        public let label: String
        /// The fact's value.
        public let value: String
        /// Identifies the subject by its label, which is unique within one record.
        public var id: String {
            label
        }
    }

    /// The facts identifying the record, or a single "Unreadable" subject when the core reports none.
    public let subjects: [Subject]
    /// The bytes the record occupies, formatted for display.
    public let size: String
    /// When the record was stored, formatted as an abbreviated date and short time.
    public let stored: String
    /// When the record expires, or "No expiry".
    public let expires: String

    /// Formats a core cache record for display.
    ///
    /// - Parameters:
    ///   - entry: The record the core reports.
    ///   - accountNames: Display names keyed by account ID, used to name the record's account; unknown
    ///     accounts read "Unsaved account".
    ///   - locale: The locale used to format dates.
    ///   - timeZone: The time zone used to format dates.
    public init(
        _ entry: CacheEntry, accountNames: [Data: String], locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        var subjects: [Subject] = []
        if let account = entry.account {
            subjects.append(Subject(label: "Account", value: accountNames[account] ?? "Unsaved account"))
        }
        if let region = entry.locale {
            subjects.append(Subject(label: "Store region", value: region))
        }
        if let product = entry.productID {
            subjects.append(Subject(label: "Product", value: product))
        }
        if let image = entry.imageURL {
            subjects.append(Subject(label: "Image", value: image))
        }
        if subjects.isEmpty {
            subjects.append(Subject(label: "Record", value: "Unreadable"))
        }
        self.subjects = subjects
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
        size = LogFormat.size(entry.bytes)
        stored = entry.storedAt.formatted(style)
        expires = entry.expiresAt.map { $0.formatted(style) } ?? "No expiry"
    }
}

extension CacheClearing {
    /// The destructive confirmation prompt asking whether to clear one cache or all of them.
    public var confirmation: AppConfirmation {
        switch self {
        case .one(let cache):
            AppConfirmation(
                title: "Clear \(cache.title)?", systemImage: "trash", confirmTitle: "Clear",
                tone: .destructive
            )
        case .all:
            AppConfirmation(
                title: "Clear all caches?", systemImage: "trash", confirmTitle: "Clear all",
                tone: .destructive
            )
        }
    }
}
