import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels
import Dependencies
import Foundation

/// The `--diagnose-cloud-catalog` run: fetches the first saved account's cloud catalog and reports on it.
enum CloudLibraryDiagnostic {
    /// Runs the diagnostic through the installed clients, in the injected locale.
    ///
    /// - Returns: The lines printed for the run.
    static func run() async -> String {
        @Dependency(\.accounts) var accounts
        @Dependency(\.catalog) var catalogClient
        @Dependency(\.locale) var locale
        do {
            guard let account = try await accounts.load().get().first else {
                return "Cloud catalog: no saved account"
            }
            let catalog = try await catalogClient.library(
                account.id,
                arguments.contains("--force"),
                locale.identifier.replacingOccurrences(of: "_", with: "-")
            ) { _ in
            }
            var lines = ["Cloud catalog: \(catalog.games.count) titles"]
            for argument in arguments where argument.hasPrefix("--find=") {
                lines.append(contentsOf: findLines(String(argument.dropFirst("--find=".count)), in: catalog))
            }
            let tier = UsersBridge().find(account.accountID)?.tier ?? nil
            lines.append("Subscription: \(tier?.label ?? "unknown")")
            lines.append(contentsOf: await titleLines(account.accountID))
            return lines.joined(separator: "\n")
        } catch let failure as CloudLibraryFailure {
            return "Cloud catalog: \(failure)"
        } catch {
            return "Cloud catalog: storage or cancellation failure (\(error))"
        }
    }

    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private static func findLines(_ query: String, in catalog: CloudLibrarySnapshot) -> [String] {
        let needle = query.lowercased()
        return catalog.games
            .filter { $0.name.lowercased().contains(needle) || $0.id.lowercased().contains(needle) }
            .map {
                "Row \($0.name) \($0.productId) \($0.platform) owned=\($0.isOwned) visible=\($0.visible) "
                    + "standing=\($0.standing.rawValue) refusal=\($0.launchRefusal?.rawValue ?? "-")"
            }
    }

    private static func titleLines(_ account: AccountID) async -> [String] {
        var lines = [String]()
        for argument in arguments where argument.hasPrefix("--product=") {
            let product = String(argument.dropFirst("--product=".count))
            switch await TitleChecksBridge().storefront(account: account, productID: product) {
            case .success(let answer):
                lines.append("Product \(product): \(answer.streaming), owned per store \(answer.ownedPerStore), "
                    + "library add offered \(answer.offersLibraryAdd)")
            case .failure(let failure):
                lines.append("Product \(product): unanswered (\(failure.reason), HTTP \(failure.httpStatus))")
            }
        }
        return lines
    }
}
