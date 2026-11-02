import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import ComposableArchitecture
import Foundation

/// Owns the app's one open database and the streaming core opened over it, and the account work that needs
/// both.
///
/// The composition root builds the one instance over the launch's `UserData` and installs it
/// as `\.accountService`; every live client reaches the database through it.
public actor AccountService {
    private let data: UserData
    private let database: AppDatabaseClient
    private var cloudService: CloudStatusService?
    private var repositories = RepositoriesState.closed
    private var refreshTask: Task<[UUID: AccountRefreshResult.Issue], Error>?
    private var core = CoreState.closed
    private var coreLog: Task<Void, Never>?

    private enum RepositoriesState {
        case closed
        case opening(Task<AppRepositories, any Error>)
        case open(AppRepositories)
    }

    private enum CoreState {
        case closed
        case open(CoreSession)
        case failed(ContinuousClock.Instant)
    }

    private static let coreRetryInterval: Duration = .seconds(10)

    private static let coreLogInterval: Duration = .milliseconds(500)

    /// Creates the service over one user data location.
    ///
    /// - Parameters:
    ///   - data: Where the database and the core's catalog live.
    ///   - database: Opens and migrates the one app database.
    public init(data: UserData, database: AppDatabaseClient) {
        self.data = data
        self.database = database
    }

    /// The cloud status service over the open database.
    ///
    /// - Returns: The service, built once.
    /// - Throws: The error ``storage()`` throws.
    public func cloud() async throws -> CloudStatusService {
        if let cloudService {
            return cloudService
        }
        let repositories = try await storage()
        let service = CloudStatusService(
            repositories: repositories,
            catalog: .init { scope in
                guard let account = try repositories.accounts.list()
                    .first(where: { $0.id == scope.accountID })
                else {
                    throw CloudStatusFailure.signInRequired
                }
                let access: CloudAccess
                do throws(CatalogUnanswered) {
                    access = try await CatalogBridge().cloudAccess(account: account.accountID)
                } catch {
                    throw error.needsSignIn
                        ? CloudStatusFailure.signInRequired
                        : CloudStatusFailure.network
                }
                switch access.availability {
                case .rejected:
                    throw CloudStatusFailure.authorizationRejected
                case .regionUnsupported:
                    throw CloudStatusFailure.regionUnsupported
                case .unavailable:
                    throw CloudStatusFailure.network
                case .available, .signInExpired:
                    return CloudCatalogEvidence(
                        gameCount: access.titleCount ?? 0,
                        nativeCatalog: access.fromAccountService && access.complete,
                        warning: access.availability == .signInExpired
                            ? .sessionExpired
                            : .none,
                        isPlus: UsersBridge().find(account.accountID)?.plusMember
                    )
                }
            }
        )
        cloudService = service
        return service
    }

    /// The repositories over the one app database, opening it and the core on first use.
    ///
    /// Concurrent first callers share one open; a failed open is tried again by the next caller.
    ///
    /// - Returns: The repositories.
    /// - Throws: `DatabaseOpenFailure` when the database cannot be opened, or the error
    ///   creating the catalog folder or the installation's device id throws.
    public func storage() async throws -> AppRepositories {
        let opened: AppRepositories
        switch repositories {
        case .open(let open):
            opened = open
        case .opening(let task):
            opened = try await task.value
        case .closed:
            let task = Task { [data, database] in
                try await Self.open(data, with: database)
            }
            repositories = .opening(task)
            do {
                opened = try await task.value
            } catch {
                repositories = .closed
                throw error
            }
            repositories = .open(opened)
        }
        openCoreIfDue(opened, catalog: data.catalog)
        return opened
    }

    private static func open(_ data: UserData,
                             with database: AppDatabaseClient) async throws -> AppRepositories {
        try FileManager.default.createDirectory(
            at: data.catalog, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let repositories = try await AppRepositories(database: database.open(data).get()) { failure in
            @Dependency(\.logger) var logger
            logger.enqueue(.diagnostic(
                .accounts, .error, "A store the core uses failed: \(failure)"
            ))
        }
        _ = try repositories.installation.deviceID()
        return repositories
    }
    private func openCoreIfDue(_ repositories: AppRepositories, catalog: URL) {
        switch core {
        case .open:
            return
        case .failed(let failedAt) where failedAt.duration(to: .now) < Self.coreRetryInterval:
            return
        case .closed, .failed:
            openCore(repositories, catalog: catalog)
        }
    }
    private func openCore(_ repositories: AppRepositories, catalog: URL) {
        let opened: CoreSession
        do {
            opened = try CoreSession.open(
                catalog: catalog,
                consoles: repositories.consoles,
                credentials: repositories.credentials,
                datacenters: repositories.datacenters,
                devices: repositories.devices
            )
        } catch {
            core = .failed(.now)
            @Dependency(\.logger) var logger
            logger.enqueue(.diagnostic(
                .accounts, .error,
                "The streaming core could not be opened; sign-in and play are unavailable until it opens"
            ))
            return
        }
        core = .open(opened)
        coreLog?.cancel()
        coreLog = Self.drainCoreLog(opened)
        try? opened.restoreDerivedDeviceColumns(in: repositories.devices)
        let users = opened.users.welcomeBack()
        let consolesRemembered = opened.rememberSavedConsoles()
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(
            .accounts, .info,
            "Core opened: \(users?.admitted ?? 0) saved account(s) admitted, \(users?.rejected ?? 0) "
                + "rejected; \(consolesRemembered?.remembered ?? 0) saved console(s) remembered, "
                + "\(consolesRemembered?.rejected ?? 0) rejected"
        ))
    }

    private static func drainCoreLog(_ core: CoreSession) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            @Dependency(\.logger) var logger
            while !Task.isCancelled {
                for line in core.log.read() {
                    await logger.log(.coreDiagnostic(
                        severity: line.severity, message: CoreDiagnosticLine.format(line.message)
                    ))
                }
                do {
                    try await Task.sleep(for: coreLogInterval)
                } catch {
                    break
                }
            }
        }
    }

    /// Refreshes every PlayStation account, sharing one run between concurrent callers.
    ///
    /// - Returns: The accounts with the issue each refresh met.
    /// - Throws: The error ``storage()`` throws, or `CancellationError`.
    public func refresh() async throws -> AccountRefreshResult {
        if let refreshTask {
            let issues = try await refreshTask.value
            return try await AccountRefreshResult(accounts: storage().accounts.list(), issues: issues)
        }
        let repositories = try await storage()
        let task = Task {
            try await AccountDetailsRefresh.run(repositories)
        }
        refreshTask = task
        defer {
            refreshTask = nil
        }
        let issues = try await task.value
        return try AccountRefreshResult(accounts: repositories.accounts.list(), issues: issues)
    }
    /// The core account id of a saved account.
    ///
    /// - Parameter id: The saved account.
    /// - Returns: Its account id, or `nil` when it is not saved.
    /// - Throws: The error ``storage()`` throws.
    public func accountID(of id: UUID) async throws -> AccountID? {
        try await storage().accounts.list().first { $0.id == id }?.accountID
    }
    /// Signs an account out of the core and deletes it.
    ///
    /// - Parameter id: The saved account.
    /// - Throws: The error ``storage()`` or the repository throws.
    public func delete(_ id: UUID) async throws {
        let repositories = try await storage()
        if let profile = try repositories.accounts.list().first(where: { $0.id == id }) {
            UsersBridge().signOut(profile.accountID)
        }
        try repositories.accounts.delete(id)
    }
    /// Every saved account, after merging unlinked duplicates.
    ///
    /// - Returns: The accounts.
    /// - Throws: The error ``storage()`` or the repository throws.
    public func load() async throws -> [AccountProfile] {
        let repositories = try await storage()
        try repositories.accounts.consolidateUnlinkedDuplicates()
        return try repositories.accounts.list()
    }
    /// Saves an account known only by its account id as a home user.
    ///
    /// - Parameters:
    ///   - profile: The new account's id.
    ///   - name: Its display name.
    ///   - account: Its core account id.
    /// - Returns: The saved account.
    /// - Throws: `PersistenceError` when the core refuses it or it was not saved.
    public func addAccountID(profile: UUID, name: String, account: AccountID) async throws -> AccountProfile {
        let repositories = try await storage()
        repositories.credentials.expect(PendingProfile(id: profile, name: name))
        defer {
            repositories.credentials.expect(nil)
        }
        guard UsersBridge().addHomeUser(account, name: name) != nil else {
            throw PersistenceError.invalidInput
        }
        guard let saved = try repositories.accounts.list().first(where: { $0.accountID == account }) else {
            throw PersistenceError.corruptData
        }
        return saved
    }

    /// Signs an account in on the web and saves its credentials.
    ///
    /// - Parameters:
    ///   - profile: The account being signed in.
    ///   - capture: The NPSSO the browser captured.
    /// - Returns: The saved account.
    /// - Throws: `SignInFailure` for every failure.
    public func signIn(profile: UUID,
                       capture: consuming SignInCapture) async throws(SignInFailure) -> AccountProfile {
        let repositories: AppRepositories
        do {
            repositories = try await storage()
        } catch {
            throw .storage
        }
        return try await AccountSignIn.run(profile: profile, capture: capture, in: repositories)
    }

    /// Signs a new account in by a QR code another device approves, and saves its credentials.
    ///
    /// - Parameters:
    ///   - profile: The id the new account is saved under.
    ///   - progress: Told each step before the sign-in ends.
    /// - Returns: The saved account.
    /// - Throws: `SignInFailure` for every failure.
    public func signInWithQR(
        profile: UUID,
        progress: @escaping @Sendable (QRSignInProgress) -> Void
    ) async throws(SignInFailure) -> AccountProfile {
        let repositories: AppRepositories
        do {
            repositories = try await storage()
        } catch {
            throw .storage
        }
        return try await AccountSignIn.runQR(profile: profile, progress: progress, in: repositories)
    }
}

extension AccountService: TestDependencyKey {
    /// A service whose database open is unimplemented, so a test that reaches storage without installing its
    /// own service fails.
    public static let testValue = AccountService(data: .scratch(), database: AppDatabaseClient())
}

extension DependencyValues {
    /// The one service owning the app database and the core.
    public var accountService: AccountService {
        get {
            self[AccountService.self]
        }
        set {
            self[AccountService.self] = newValue
        }
    }
}

/// Signs an account in to the core with the NPSSO the sign-in page set, and records the NPSSO's expiry.
///
/// The core saves the signed-in account through the credential store under the profile announced here, so a
/// new account keeps the id the app chose for it.
private enum AccountSignIn {
    /// Signs an account in and returns it as saved.
    ///
    /// - Parameters:
    ///   - profile: The account being signed in.
    ///   - capture: The NPSSO the browser captured.
    ///   - repositories: The open repositories.
    /// - Returns: The saved account.
    /// - Throws: `SignInFailure` for every failure.
    static func run(
        profile: UUID,
        capture: consuming SignInCapture,
        in repositories: AppRepositories
    ) async throws(SignInFailure) -> AccountProfile {
        let device: String
        let known: AccountID?
        do {
            device = try repositories.installation.deviceID()
            known = try repositories.accounts.list().first { $0.id == profile && $0.method == .npsso }?
                .accountID
        } catch {
            throw .storage
        }
        let expiresAt = capture.expiresAt
        let source = capture.expirySource
        repositories.credentials.expect(PendingProfile(id: profile, name: "", expirySource: source))
        defer {
            repositories.credentials.withdraw(profile)
        }
        let users = UsersBridge()
        let user: SignedInUser
        do throws(CoreSignInFailure) {
            user = try await users.signIn(
                npsso: Self.secret(capture.npsso), validUntil: expiresAt, deviceID: device,
                correlationID: profile, again: known.flatMap { users.find($0)?.accountID }
            )
        } catch {
            throw Self.failure(of: error)
        }
        let signedIn = user.accountID
        do {
            guard let saved = try repositories.accounts.list().first(where: { $0.accountID == signedIn })
            else {
                throw PersistenceError.corruptData
            }
            if expiresAt != nil {
                try repositories.credentials.noteNPSSO(
                    Self.secret(capture.npsso), expiresAt: expiresAt, source: source, for: saved.id
                )
            }
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .accounts, .info,
                "Sign-in for \"\(user.onlineID)\" (id \(LogFormat.idPrefix(profile))) succeeded; NPSSO expiry "
                    + (expiresAt.map { $0.ISO8601Format() } ?? "unknown")
            ))
            return saved
        } catch {
            throw .storage
        }
    }

    /// Signs a new account in by a QR code and returns it as saved.
    ///
    /// - Parameters:
    ///   - profile: The id the new account is saved under.
    ///   - progress: Told each step before the sign-in ends.
    ///   - repositories: The open repositories.
    /// - Returns: The saved account.
    /// - Throws: `SignInFailure` for every failure.
    static func runQR(
        profile: UUID,
        progress: @escaping @Sendable (QRSignInProgress) -> Void,
        in repositories: AppRepositories
    ) async throws(SignInFailure) -> AccountProfile {
        let device: String
        do {
            device = try repositories.installation.deviceID()
        } catch {
            throw .storage
        }
        let credentials = repositories.credentials
        defer {
            credentials.withdraw(profile)
        }
        let user: SignedInUser
        do throws(CoreSignInFailure) {
            user = try await UsersBridge().signInWithQR(deviceID: device, correlationID: profile) { step in
                if step == .signingIn {
                    credentials.expect(PendingProfile(id: profile, name: "", expirySource: .unknown))
                }
                progress(step)
            }
        } catch {
            throw Self.failure(of: error)
        }
        let signedIn = user.accountID
        do {
            guard let saved = try repositories.accounts.list().first(where: { $0.accountID == signedIn })
            else {
                throw PersistenceError.corruptData
            }
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .accounts, .info,
                "QR code sign-in for \"\(user.onlineID)\" (id \(LogFormat.idPrefix(profile))) succeeded"
            ))
            return saved
        } catch {
            throw .storage
        }
    }

    private static func secret(_ npsso: borrowing NPSSO) -> SecretBytes {
        SecretBytes(count: npsso.count) { (buffer: UnsafeMutableRawBufferPointer) in
            npsso.withUnsafeBytes {
                buffer.copyMemory(from: $0)
            }
        }
    }

    private static func failure(of failure: CoreSignInFailure) -> SignInFailure {
        switch failure {
        case .cancelled, .declined:
            .cancelled
        case .differentAccount:
            .differentAccount
        case .invalidRequest, .rejected, .verificationRequired:
            .rejected
        case .expired:
            .codesExpired
        case .layoutChanged:
            .unreadableResponse
        case .rateLimited:
            .rateLimited
        case .unavailable(httpStatus: nil), .coreClosed:
            .serviceUnavailable
        case .unavailable, .invalidDevice, .transport, .malformed, .unknownUser:
            .unreachable
        }
    }
}
