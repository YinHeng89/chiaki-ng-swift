import ChiakiModels
import SwiftUI
import Testing
@testable import ChiakiFeatures

@Test func consoleGridMovesAcrossRowsAndColumns() {
    #expect(ConsoleGridNavigation.from(0, count: 3, columns: 2, .right) == .console(1))
    #expect(ConsoleGridNavigation.from(1, count: 3, columns: 2, .right) == .outside)
    #expect(ConsoleGridNavigation.from(1, count: 3, columns: 2, .left) == .console(0))
    #expect(ConsoleGridNavigation.from(0, count: 3, columns: 2, .left) == .outside)
    #expect(ConsoleGridNavigation.from(2, count: 3, columns: 2, .right) == .outside)
    #expect(ConsoleGridNavigation.from(0, count: 3, columns: 2, .down) == .console(2))
    #expect(ConsoleGridNavigation.from(1, count: 3, columns: 2, .down) == .outside)
    #expect(ConsoleGridNavigation.from(2, count: 3, columns: 2, .down) == .outside)
    #expect(ConsoleGridNavigation.from(2, count: 3, columns: 2, .up) == .console(0))
    #expect(ConsoleGridNavigation.from(1, count: 3, columns: 2, .up) == .outside)
    #expect(ConsoleGridNavigation.from(1, count: 4, columns: 2, .down) == .console(3))
}

@Test func singleColumnConsoleGridMovesVertically() {
    #expect(ConsoleGridNavigation.from(0, count: 2, columns: 1, .down) == .console(1))
    #expect(ConsoleGridNavigation.from(1, count: 2, columns: 1, .down) == .outside)
    #expect(ConsoleGridNavigation.from(1, count: 2, columns: 1, .up) == .console(0))
    #expect(ConsoleGridNavigation.from(0, count: 2, columns: 1, .right) == .outside)
}

@Test func consoleGridUsesTwoColumnsOnlyWhenWideWithSeveralConsoles() {
    #expect(ConsoleGridLayout.columns(for: 1440, cards: 3) == 2)
    #expect(ConsoleGridLayout.columns(for: 1440, cards: 1) == 1)
    #expect(ConsoleGridLayout.columns(for: 900, cards: 3) == 1)
}
