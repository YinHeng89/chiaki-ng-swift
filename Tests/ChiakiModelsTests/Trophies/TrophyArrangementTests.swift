import Foundation
import Testing
@testable import ChiakiModels

private let astro = TrophyTitle(id: "a", name: "Astro Bot", earned: TrophyCounts(bronze: 40), progress: 100)
private let uncharted = TrophyTitle(
    id: "u",
    name: "UNCHARTED 4",
    earned: TrophyCounts(bronze: 2),
    progress: 3
)
private let pokemon = TrophyTitle(id: "p", name: "Pokémon Café", progress: 0)
private let sackboy = TrophyTitle(id: "s", name: "Sackboy", earned: TrophyCounts(gold: 1), progress: 3)

private let first = PSNTrophy(
    id: 0,
    grade: .bronze,
    name: "Start",
    earned: true,
    earnedAt: Date(timeIntervalSince1970: 100),
    earnedRate: 80
)
private let platinum = PSNTrophy(id: 1, grade: .platinum, name: "All", earnedRate: 2)
private let gold = PSNTrophy(
    id: 2,
    grade: .gold,
    name: "Boss",
    earned: true,
    earnedAt: Date(timeIntervalSince1970: 300),
    earnedRate: 20
)
private let secret = PSNTrophy(id: 3, grade: .bronze, name: "Cave", hidden: true)

@Test func theGamesListFiltersByHowFarThePlayerHasGot() {
    let titles = [uncharted, astro, pokemon, sackboy]
    #expect(TrophyArrangement.titles(titles, filter: .all, sort: .recent, query: "") == titles)
    #expect(TrophyArrangement.titles(titles, filter: .completed, sort: .recent, query: "") == [astro])
    #expect(TrophyArrangement.titles(titles, filter: .inProgress, sort: .recent, query: "") == [
        uncharted,
        sackboy
    ])
    #expect(TrophyArrangement.titles(titles, filter: .notStarted, sort: .recent, query: "") == [pokemon])
}

@Test func theGamesListSortsAndKeepsPsnOrderOnTies() {
    let titles = [uncharted, astro, pokemon, sackboy]
    #expect(
        TrophyArrangement.titles(titles, filter: .all, sort: .progress, query: "")
            == [astro, uncharted, sackboy, pokemon]
    )
    #expect(
        TrophyArrangement.titles(titles, filter: .all, sort: .name, query: "")
            == [astro, pokemon, sackboy, uncharted]
    )
}

@Test func aReversedSortRunsTheOtherWayRound() {
    let titles = [uncharted, astro, pokemon, sackboy]
    #expect(
        TrophyArrangement.titles(titles, filter: .all, sort: .progress, query: "", direction: .reversed)
            == [pokemon, sackboy, uncharted, astro]
    )
    #expect(
        TrophyArrangement.titles(titles, filter: .all, sort: .name, query: "", direction: .reversed)
            == [uncharted, sackboy, pokemon, astro]
    )
    #expect(TrophySortDirection.standard.flipped == .reversed)
    #expect(TrophySortDirection.reversed.flipped == .standard)
}

@Test func theGamesListSearchIgnoresCaseAccentsAndSpaces() {
    let titles = [uncharted, astro, pokemon, sackboy]
    #expect(TrophyArrangement.titles(titles, filter: .all, sort: .recent, query: "  pokemon ") == [pokemon])
    #expect(TrophyArrangement.titles(titles, filter: .all, sort: .recent, query: "chart") == [uncharted])
    #expect(TrophyArrangement.titles(titles, filter: .completed, sort: .recent, query: "chart").isEmpty)
}

@Test func aGamesTrophiesFilterByWhetherTheyAreEarned() {
    let trophies = [first, platinum, gold, secret]
    #expect(TrophyArrangement.trophies(trophies, filter: .all, sort: .game) == trophies)
    #expect(TrophyArrangement.trophies(trophies, filter: .earned, sort: .game) == [first, gold])
    #expect(TrophyArrangement.trophies(trophies, filter: .unearned, sort: .game) == [platinum, secret])
}

@Test func aGamesTrophiesSortByGradeRarityEarnedTimeAndName() {
    let trophies = [first, platinum, gold, secret]
    #expect(TrophyArrangement.trophies(trophies, filter: .all, sort: .grade) == [
        platinum,
        gold,
        first,
        secret
    ])
    #expect(TrophyArrangement.trophies(trophies, filter: .all, sort: .rarity) == [
        platinum,
        gold,
        first,
        secret
    ])
    #expect(
        TrophyArrangement.trophies(trophies, filter: .all, sort: .recentlyEarned)
            == [gold, first, platinum, secret]
    )
    #expect(TrophyArrangement.trophies(trophies, filter: .all, sort: .name) == [
        platinum,
        gold,
        secret,
        first
    ])
}

@Test func everyChoiceHasItsOwnLabel() {
    for labels in [
        TrophyTitleFilter.allCases.map(\.name),
        TrophyTitleSort.allCases.map(\.name),
        TrophyFilter.allCases.map(\.name),
        TrophySort.allCases.map(\.name)
    ] {
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count)
    }
}
