import ChiakiModels
import Foundation
import Testing
@testable import ChiakiNG

@MainActor @Test func aSessionStillClosingOrEndedMomentsAgoCountsAsJustLeft() throws {
    let ps5 = try #require(HardwareID(hex: "a1b2c3d4e5f6"))
    let ps4 = try #require(HardwareID(hex: "0a0b0c0d0e0f"))
    let sessions = RecentConsoleSessions()
    let start = ContinuousClock.now
    #expect(!sessions.justLeft(ps5, at: start))
    sessions.finished(ps5, at: start)
    #expect(!sessions.justLeft(ps5, at: start))
    sessions.began(ps5)
    #expect(sessions.justLeft(ps5, at: start))
    sessions.finished(ps5, at: start)
    #expect(sessions.justLeft(ps5, at: start + .seconds(5)))
    #expect(!sessions.justLeft(ps4, at: start + .seconds(5)))
    #expect(!sessions.justLeft(ps5, at: start + RecentConsoleSessions.window))
    sessions.finished(ps5, at: start + .seconds(30))
    #expect(sessions.justLeft(ps5, at: start + .seconds(10)))
}
