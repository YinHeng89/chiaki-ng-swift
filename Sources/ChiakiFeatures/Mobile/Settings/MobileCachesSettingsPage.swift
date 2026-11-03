import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The touch Caches page: refreshing and clearing every cache, then one group per cache with its figures, its
/// records opened in place and its own clear action, which asks first.
struct MobileCachesSettingsPage: View {
    /// The settings.
    let settings: StoreOf<SettingsFeature>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    var body: some View {
        let shown = !store.summaries.isEmpty || store.phase == .ready
        let summaries = store.summaries
        let half = (summaries.count + 1) / 2
        MobileSettingsForm {
            controls
            if shown {
                ForEach(summaries.prefix(half), id: \.id) { summary in
                    cache(CacheSummaryPresentation(summary, decoded: store.decodedArtwork))
                }
            }
        } trailing: {
            if shown {
                ForEach(summaries.dropFirst(half), id: \.id) { summary in
                    cache(CacheSummaryPresentation(summary, decoded: store.decodedArtwork))
                }
            }
        }
        .onAppear {
            settings.send(.caches(.load))
        }
    }

    private var store: StoreOf<CachesReducer> {
        settings.scope(state: \.caches, action: \.caches)
    }

    private var controls: some View {
        MobileSettingsGroup {
            MobileButtonRow("Refresh") {
                store.send(.load)
            }
            .disabled(store.busy)
            .overlay(alignment: .trailing) {
                if store.busy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 16)
                }
            }
            .accessibilityIdentifier("caches-refresh")
            MobileButtonRow("Clear All", destructive: true) {
                store.send(.askClear(.all))
            }
            .disabled(store.busy || !store.holdsAnything)
            .accessibilityIdentifier("caches-clear-all")
            if case .failed(let message) = store.phase {
                failure(message)
                    .textSelection(.enabled)
            }
        }
    }

    private func cache(_ cache: CacheSummaryPresentation) -> some View {
        let opened = store.entries.cache == cache.id
        return MobileSettingsGroup(cache.title) {
            MobileValueRow("Entries", value: cache.entries)
            MobileValueRow("Size", value: cache.size)
            if let memory = cache.memory {
                MobileValueRow("Memory", value: memory)
            }
            MobileButtonRow(
                opened
                    ? "Hide Entries"
                    : "Show Entries"
            ) {
                store.send(
                    opened
                        ? .close
                        : .open(cache.id)
                )
            }
            .disabled(cache.isEmpty && !opened)
            .accessibilityIdentifier("caches-entries-\(cache.id)")
            if opened {
                entries
            }
            MobileButtonRow("Clear", destructive: true) {
                store.send(.askClear(.one(cache.id)))
            }
            .disabled(store.busy || cache.isEmpty)
            .accessibilityIdentifier("caches-clear-\(cache.id)")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var entries: some View {
        switch store.entries {
        case .closed:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .mobileRowPadding()
        case .failed(_, let message):
            failure(message)
        case .shown(_, let entries):
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                entryRow(CacheEntryPresentation(entry, accountNames: store.accountNames))
            }
        }
    }

    private func entryRow(_ entry: CacheEntryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.subjects) { subject in
                VStack(alignment: .leading, spacing: 1) {
                    Text(subject.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(subject.value)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            figure("Size", entry.size)
            figure("Stored", entry.stored)
            figure("Expires", entry.expires)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .mobileRowPadding()
        .accessibilityElement(children: .combine)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .font(.footnote)
    }

    private func failure(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mobileRowPadding()
    }
}
