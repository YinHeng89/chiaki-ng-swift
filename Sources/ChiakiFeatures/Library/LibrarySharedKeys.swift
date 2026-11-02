import ChiakiModels
import ComposableArchitecture
import Foundation

extension SharedReaderKey where Self == InMemoryKey<UUID?>.Default {
    /// The account the library is shown for, owned by the app and read by the library.
    public static var selectedAccount: Self {
        Self[.inMemory("selectedAccount"), default: nil]
    }
}

extension SharedReaderKey where Self == InMemoryKey<[RegistrationFlow.Profile]>.Default {
    /// The saved accounts, owned by the app and read by the library.
    public static var accounts: Self {
        Self[.inMemory("accounts"), default: []]
    }
}

extension SharedReaderKey where Self == InMemoryKey<[RegistrationFlow.Registration]>.Default {
    /// The paired consoles of every account, owned by the app and read by the library.
    public static var consoleCatalog: Self {
        Self[.inMemory("consoleCatalog"), default: []]
    }
}
