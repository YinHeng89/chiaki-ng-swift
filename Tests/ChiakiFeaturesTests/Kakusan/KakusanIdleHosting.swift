@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture

extension DependencyValues {
    /// Lets a console stream arm and disarm Kakusan hosting that never reports an event, for tests about
    /// the stream rather than its guests.
    mutating func idleKakusanHosting() {
        kakusan.arm = { _, _ in
        }
        kakusan.disarm = {
        }
        kakusan.useStunServers = { _ in
            .success(())
        }
        kakusan.loadSettings = {
            KakusanSettings()
        }
    }
}
