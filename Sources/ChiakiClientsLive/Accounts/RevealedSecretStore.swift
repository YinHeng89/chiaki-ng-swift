import ChiakiClients
import Dependencies

extension RevealedSecretStore: DependencyKey {
    /// The app's store of revealed secrets.
    public static let liveValue = RevealedSecretStore()
}
