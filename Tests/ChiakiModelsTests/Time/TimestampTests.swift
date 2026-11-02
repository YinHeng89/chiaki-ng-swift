import ChiakiModels
import Foundation
import Testing

@Test func timestampsReadMillisecondsAsDatesWithoutAMissingMarker() {
    #expect(Timestamp.date(milliseconds: 1_700_000_000_123) == Date(timeIntervalSince1970: 1_700_000_000.123))
    #expect(Timestamp.date(milliseconds: 1500) == Date(timeIntervalSince1970: 1.5))
    #expect(Timestamp.date(milliseconds: 0) == Date(timeIntervalSince1970: 0))
    #expect(Timestamp.date(milliseconds: -1) == Date(timeIntervalSince1970: -0.001))
}

@Test func timestampsRoundDatesToTheNearestMillisecond() {
    #expect(Timestamp.milliseconds(of: Date(timeIntervalSince1970: 1_765_000_000.4567)) == 1_765_000_000_457)
    #expect(Timestamp.milliseconds(of: Date(timeIntervalSince1970: 0.0004)) == 0)
    #expect(Timestamp.milliseconds(of: Date(timeIntervalSince1970: 0.0006)) == 1)
    #expect(Timestamp.milliseconds(of: Date(timeIntervalSince1970: -0.0006)) == -1)
    #expect(Timestamp.milliseconds(of: Date(timeIntervalSince1970: 5_106_401)) == 5_106_401_000)
}
