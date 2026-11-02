@testable import ChiakiFeatures
import Foundation
import Testing

private let waking = PlaybackAttemptLog(
    local: true, console: "PS5 \"PS5-054\" MAC 78c881c45ed3", address: "192.168.50.99", remoteDevice: nil
)
private let refused = "route=1 stage=3 domain=0 cause=25 result=27 quit=3"

@Test func aFailedStartIsOneLineWithTargetAndCause() {
    #expect(
        waking.failure(
            report: .init(
                outcome: .startFailed(.sessionRequestConnectionRefused),
                message: "Session setup failed: the console refused the connection",
                diagnostics: refused
            ),
            milliseconds: 1840
        ) == "Local start to PS5 \"PS5-054\" MAC 78c881c45ed3 at 192.168.50.99:9295 failed after 1840 ms "
            + "during session init: Session setup failed: the console refused the connection (the console refused "
            + "the session request) [ending start_failed.session_request_connection_refused; " + refused + "]"
    )
    #expect(
        waking.failure(
            report: .init(
                outcome: .startFailed(.sessionRequestConnectionRefused),
                message: nil,
                diagnostics: nil
            ),
            milliseconds: 90
        )
            == "Local start to PS5 \"PS5-054\" MAC 78c881c45ed3 at 192.168.50.99 failed after 90 ms: "
            + "The console refused the connection. Check Remote Play is available. "
            + "[ending start_failed.session_request_connection_refused]"
    )
    let remote = PlaybackAttemptLog(
        local: false,
        console: "PS5 \"Den\" MAC 00",
        address: "Den",
        remoteDevice: "a1b2c3d4…"
    )
    #expect(
        remote.failure(
            report: .init(outcome: .startFailed(.routeFailed), message: nil, diagnostics: nil),
            milliseconds: 5
        )
        .hasPrefix("Remote start to PS5 \"Den\" MAC 00 via PSN device a1b2c3d4… failed after 5 ms")
    )
}
