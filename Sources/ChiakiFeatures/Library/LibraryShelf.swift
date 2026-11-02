import ChiakiModels
import CoreGraphics
import Foundation

/// What the console shelf shows, derived once per render from the library's state and the developer previews.
struct LibraryShelf {
    /// The consoles shown, previews included.
    let consoles: [DisplayedConsole]
    /// Which cards show their last title and how.
    let plan: ConsoleContinuePlan
    /// The recently played rows below the shelf.
    let recentRows: [RecentlyPlayedSection.Row]
    /// Where each direction moves focus.
    let graph: ConsoleShelfFocusGraph
    /// Whether the shelf still waits for the console catalog.
    let waiting: Bool

    /// Derives the shelf.
    ///
    /// - Parameters:
    ///   - state: The library's state.
    ///   - consoles: The consoles shown.
    ///   - gridWidth: The measured width of the console grid.
    ///   - layeredArt: Whether cards draw a title's layered art.
    ///   - compact: Whether the window is compact.
    ///   - stacked: Whether a compact window stacks its cards in one column, so Down moves to the next card,
    ///     rather than paging them in one row.
    ///   - recentOrigin: The console the recently played rows were last entered from.
    ///   - tabCenters: The horizontal centre of each compact section tab.
    init(
        state: LibraryFeature.State,
        consoles: [DisplayedConsole],
        gridWidth: CGFloat,
        layeredArt: Bool,
        compact: Bool,
        stacked: Bool = false,
        recentOrigin: UUID?,
        tabCenters: [LibrarySection: CGFloat]
    ) {
        self.consoles = consoles
        plan = ConsoleContinuePlan(
            consoles: consoles,
            recentlyPlayed: state.recentlyPlayed,
            gridWidth: gridWidth,
            layeredArt: layeredArt
        )
        recentRows = state.recentRows(continuing: plan.continuing)
        waiting = state.consoleLoad.isWaiting
        graph = ConsoleShelfFocusGraph(
            consoles: consoles,
            columns: Self.columns(
                consoles: consoles.count, gridWidth: gridWidth, compact: compact, stacked: stacked
            ),
            continuing: Set(consoles.filter(plan.shows)),
            recentRows: recentRows.map { row in
                ConsoleShelfFocusGraph.RecentRow(
                    consoleID: row.consoleID,
                    titleIDs: row.titles?.map(\.titleID) ?? []
                )
            },
            hasStatusAction: state.hasStatusAction,
            compact: compact,
            accountSelected: state.selectedProfile != nil,
            sections: state.availableSections,
            cloudUnavailable: state.cloudUnavailable,
            section: state.section,
            recentOrigin: recentOrigin,
            tabCenters: tabCenters
        )
    }

    private static func columns(consoles: Int, gridWidth: CGFloat, compact: Bool, stacked: Bool) -> Int {
        guard compact else {
            return ConsoleGridLayout.columns(for: gridWidth, cards: consoles)
        }
        return stacked
            ? 1
            : max(1, consoles)
    }
}
