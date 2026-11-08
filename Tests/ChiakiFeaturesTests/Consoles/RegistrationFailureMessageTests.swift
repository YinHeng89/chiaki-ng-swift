import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func everyPairingFailureKeepsItsLabel() {
    #expect(String(localized: RegistrationFailureMessage
            .text(for: .invalidInput)) == "Enter a valid console address and eight-digit PIN.")
    #expect(
        String(localized: RegistrationFailureMessage.text(for: .rejected))
            == "Registration failed. Check the console address and generate a new PIN."
    )
    #expect(
        String(localized: RegistrationFailureMessage.text(for: .unreachable))
            == "The console didn't answer. Check the address and that the console is on, then try again."
    )
    #expect(
        String(localized: RegistrationFailureMessage.text(for: .remoteRejected))
            == "PlayStation registration failed. Retry or use a local PIN."
    )
    #expect(
        String(localized: RegistrationFailureMessage.text(for: .unavailable))
            == "The registration service is unavailable."
    )
    #expect(
        String(localized: RegistrationFailureMessage.text(for: .storage))
            == "Couldn't save the registration. Try again."
    )
    #expect(
        String(localized: RegistrationFailureMessage.text(for: .sessionPlaying)) == "A session is playing"
    )
}
