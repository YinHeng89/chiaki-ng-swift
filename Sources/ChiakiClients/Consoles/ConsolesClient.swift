import ChiakiModels
import ComposableArchitecture
import Foundation

/// Reaches the consoles: pairs and unpairs them, reads and edits the saved pairings, subscribes to the
/// one local-network scan, lists an account's consoles on PlayStation Network, reads the console set to
/// connect at launch and wakes consoles, keeps the login PINs, and fetches and launches recently played
/// titles with their art.
///
/// The live value, in `ChiakiClientsLive`, is built by the app's composition root over the open database
/// and core. It validates a pairing request and pairs through the core, which saves the pairing through the
/// console store, and removes a pairing the console rejected. A save from the console editor changes the
/// database and the core together or not at all. Every scan subscriber shares one underlying scan: it
/// starts with the first subscriber, ends with the last, and saves each discovered console's address once,
/// whoever is subscribed; a saved address is reported through ``notePairingsChanged`` so the catalog
/// reloads. Pairing and editing failures are returned, never thrown, so a feature sends the result back
/// tagged with the attempt that started it.
public struct ConsolesClient: Sendable {
    /// Pairs one console for an account.
    ///
    /// - Parameters: the account the pairing is for, the console and how it is reached, the PIN the console
    ///   shows for a home target or `nil` for an internet target, and a closure that receives each step the
    ///   attempt reports.
    /// - Returns: The paired console, or why the attempt failed. A cancelled task returns
    ///   `ChiakiModels/PairingFailure/cancelled`.
    public var pair: @Sendable (
        _ account: AccountID,
        _ target: PairingTarget,
        _ pin: String?,
        _ progress: @escaping @Sendable (PairingProgress) -> Void
    ) async -> Result<PairedConsole, PairingFailure>

    /// Removes an account's pairing with a console from the core, after the console rejected it.
    ///
    /// - Returns: Nothing once the pairing is gone, or `ChiakiModels/PairingFailure/unavailable` when it
    ///   could not be removed.
    public var unpair: @Sendable (
        _ account: UUID,
        _ console: RegistrationFlow.ConsoleTarget
    ) async -> Result<Void, PairingFailure>

    /// Reads every saved pairing.
    public var pairings: @Sendable () async -> Result<[RegisteredConsole], ConsoleCatalogFailure>

    /// A stream that yields each time something outside the catalog's own reads changed a pairing, such as a
    /// discovered console saving its new address.
    public var pairingChanges: @Sendable () -> AsyncStream<Void>

    /// Reports that the saved pairings changed.
    public var notePairingsChanged: @Sendable () -> Void

    /// Reads a console's saved launch options.
    public var launchOptions: @Sendable (_ console: UUID) async
        -> Result<ConsoleLaunchOptions, ConsoleEditFailure>

    /// Saves a console editor draft; returns `nil` on success.
    public var saveDraft: @Sendable (_ draft: ConsoleDraft) async -> ConsoleEditFailure?

    /// Deletes a console with its pairings; returns `nil` on success.
    public var deleteConsole: @Sendable (_ console: UUID) async -> ConsoleEditFailure?

    /// Subscribes to the shared local-network scan; ending the iteration of the returned stream unsubscribes.
    public var scanEvents: @Sendable () async -> AsyncStream<ConsoleScanEvent>

    /// Lists an account's PS5 or PS4 consoles registered on PlayStation Network, for pairing over the
    /// internet.
    public var accountConsoles: @Sendable (_ profile: UUID, _ ps5: Bool) async throws -> [PSNConsole]

    /// The id of the console set to connect at launch, or `nil` when none is.
    public var launchConsole: @Sendable () async throws -> UUID?

    /// Sends a wake request to a console in rest mode, given the account, the paired console and the address
    /// the scan found it at.
    public var wake: @Sendable (UUID, RegistrationFlow.ConsoleTarget, String) async throws -> Void

    /// The saved login PIN of an account on a console, or `nil` when none is saved.
    public var loginPIN: @Sendable (LoginPINOwner) async throws -> StreamAccessCode?

    /// Saves the login PIN of an account on a console, stored encrypted.
    public var saveLoginPIN: @Sendable (LoginPINOwner, StreamAccessCode) async throws -> Void

    /// Forgets the login PIN of an account on a console.
    public var clearLoginPIN: @Sendable (LoginPINOwner) async throws -> Void

    /// Fetches the recently played titles of an account.
    public var recentlyPlayed: @Sendable (UUID) async throws -> RecentlyPlayedFetch

    /// Asks a console, by hardware id, to launch a title as an account, and reports what the console did.
    public var launchTitle: @Sendable (UUID, Data, RecentTitle) async throws -> ConsoleLaunchState

    /// Fetches the art layers of a game concept for an account, for the recently played cards, or `nil` when
    /// the game has none or a fetch fails.
    public var artLayers: @Sendable (UUID, String) async -> GameArtLayers?

    /// Creates a client from its operations; each defaults to the test behaviour.
    ///
    /// - Parameters:
    ///   - pair: Pairs one console for an account; by default it reports an issue and fails as unavailable.
    ///   - unpair: Removes a rejected pairing; by default it reports an issue and fails as unavailable.
    ///   - pairings: Reads every saved pairing; by default it reports an issue and fails as unavailable.
    ///   - pairingChanges: A stream of changes; by default one that never yields.
    ///   - notePairingsChanged: Reports a change; by default nothing.
    ///   - launchOptions: Reads a console's launch options; by default it reports an issue and fails.
    ///   - saveDraft: Saves a draft; by default it reports an issue and fails.
    ///   - deleteConsole: Deletes a console; by default it reports an issue and fails.
    ///   - scanEvents: Subscribes to the shared scan; by default a scan that never reports anything.
    ///   - accountConsoles: Lists an account's consoles of one generation; by default none.
    ///   - launchConsole: Reads the console set to connect at launch; by default none.
    ///   - wake: Wakes a console as an account, at an address; by default nothing.
    ///   - loginPIN: Reads a saved PIN; by default none.
    ///   - saveLoginPIN: Saves a PIN; by default nothing.
    ///   - clearLoginPIN: Forgets a PIN; by default nothing.
    ///   - recentlyPlayed: Fetches an account's recently played titles; by default it fails as unavailable.
    ///   - launchTitle: Launches a title on a console; by default it fails as unavailable.
    ///   - artLayers: Fetches the art layers of a game concept; by default none.
    public init(
        pair: @escaping @Sendable (
            AccountID,
            PairingTarget,
            String?,
            @escaping @Sendable (PairingProgress) -> Void
        ) async -> Result<PairedConsole, PairingFailure> = { _, _, _, _ in
            reportIssue("ConsolesClient.pair is unimplemented")
            return .failure(.unavailable)
        },
        unpair: @escaping @Sendable (
            UUID,
            RegistrationFlow.ConsoleTarget
        ) async -> Result<Void, PairingFailure> = { _, _ in
            reportIssue("ConsolesClient.unpair is unimplemented")
            return .failure(.unavailable)
        },
        pairings: @escaping @Sendable () async -> Result<[RegisteredConsole], ConsoleCatalogFailure> = {
            reportIssue("ConsolesClient.pairings is unimplemented")
            return .failure(.unavailable)
        },
        pairingChanges: @escaping @Sendable () -> AsyncStream<Void> = {
            AsyncStream { _ in
            }
        },
        notePairingsChanged: @escaping @Sendable () -> Void = {
        },
        launchOptions: @escaping @Sendable (UUID) async
            -> Result<ConsoleLaunchOptions, ConsoleEditFailure> = { _ in
                reportIssue("ConsolesClient.launchOptions is unimplemented")
                return .failure(.loadFailed)
            },
        saveDraft: @escaping @Sendable (ConsoleDraft) async -> ConsoleEditFailure? = { _ in
            reportIssue("ConsolesClient.saveDraft is unimplemented")
            return .saveFailed
        },
        deleteConsole: @escaping @Sendable (UUID) async -> ConsoleEditFailure? = { _ in
            reportIssue("ConsolesClient.deleteConsole is unimplemented")
            return .deleteFailed
        },
        scanEvents: @escaping @Sendable () async -> AsyncStream<ConsoleScanEvent> = {
            AsyncStream { _ in
            }
        },
        accountConsoles: @escaping @Sendable (UUID, Bool) async throws -> [PSNConsole] = { _, _ in
            []
        },
        launchConsole: @escaping @Sendable () async throws -> UUID? = {
            nil
        },
        wake: @escaping @Sendable (UUID, RegistrationFlow.ConsoleTarget, String) async throws -> Void = {
            _, _, _ in
        },
        loginPIN: @escaping @Sendable (LoginPINOwner) async throws -> StreamAccessCode? = { _ in
            nil
        },
        saveLoginPIN: @escaping @Sendable (LoginPINOwner, StreamAccessCode) async throws -> Void = { _, _ in
        },
        clearLoginPIN: @escaping @Sendable (LoginPINOwner) async throws -> Void = { _ in
        },
        recentlyPlayed: @escaping @Sendable (UUID) async throws -> RecentlyPlayedFetch = { _ in
            throw ConsoleTitlesFailure.unavailable
        },
        launchTitle: @escaping @Sendable (UUID, Data, RecentTitle) async throws -> ConsoleLaunchState = {
            _, _, _ in
            throw ConsoleTitlesFailure.unavailable
        },
        artLayers: @escaping @Sendable (UUID, String) async -> GameArtLayers? = { _, _ in
            nil
        }
    ) {
        self.pair = pair
        self.unpair = unpair
        self.pairings = pairings
        self.pairingChanges = pairingChanges
        self.notePairingsChanged = notePairingsChanged
        self.launchOptions = launchOptions
        self.saveDraft = saveDraft
        self.deleteConsole = deleteConsole
        self.scanEvents = scanEvents
        self.accountConsoles = accountConsoles
        self.launchConsole = launchConsole
        self.wake = wake
        self.loginPIN = loginPIN
        self.saveLoginPIN = saveLoginPIN
        self.clearLoginPIN = clearLoginPIN
        self.recentlyPlayed = recentlyPlayed
        self.launchTitle = launchTitle
        self.artLayers = artLayers
    }
}

extension ConsolesClient: TestDependencyKey {
    /// Reports an issue when a test pairs, unpairs, reads the pairings or uses the console editor without
    /// overriding the operation; never reports changes, scans nothing, lists no consoles, has no launch
    /// console, wakes nothing, saves and finds no PIN, fails every recently played fetch and launch as
    /// unavailable and has no art.
    public static let testValue = ConsolesClient()
}

extension DependencyValues {
    /// The consoles: pairing, the saved pairings, the shared scan, launch, PINs and recently played titles.
    public var consoles: ConsolesClient {
        get {
            self[ConsolesClient.self]
        }
        set {
            self[ConsolesClient.self] = newValue
        }
    }
}
