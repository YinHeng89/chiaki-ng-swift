import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels
import Dependencies
import Foundation
import PlatformUI
#if os(macOS)
    import AppKit
#endif

extension PlatformClient {
    /// The app's lifecycle: shuts the stream leases down, stops them for sleep, releases sleep through the
    /// power observer and drops stale connections after wake or a network change; quitting goes through the
    /// application. Text goes through the system pasteboard, offered files live in a folder of the process's
    /// temporary directory, one folder per offer, error reports are saved through a save panel and written
    /// atomically, and alerts go to the system's notification centre. The window and launch operations are
    /// left to the app, which owns the window.
    ///
    /// Quitting schedules `terminate:` on the run loop instead of calling it from the main actor: the
    /// application delegate defers termination until the store's shutdown task finishes, and that task needs
    /// the main actor, which would stay occupied by the waiting `terminate:` call.
    ///
    /// - Parameters:
    ///   - leases: The composition root's one stream lease.
    ///   - allowSleep: Lets the Mac sleep once the notification with this number has been handled.
    /// - Returns: The live client.
    public static func live(
        leases: StreamLeases,
        allowSleep: @escaping @Sendable (_ notification: Int) async -> Void
    ) -> PlatformClient {
        PlatformClient(
            shutdown: {
                guard await leases.shutdown(within: .seconds(5)) else {
                    @Dependency(\.logger) var logger
                    await logger.log(.diagnostic(
                        .playback,
                        .warning,
                        "Quit: the stream did not close within 5 s; quitting without waiting for it"
                    ))
                    return
                }
            },
            sleep: { rest in
                let stopping = await leases.stopForSleep(rest: rest)
                _ = await leases.waitUntilReleased(within: .seconds(5))
                return stopping
            },
            restsConsoleOnSleep: {
                @Dependency(\.settings) var power
                return (try? await power.load(ConsolePowerSettings.self).restOnMacSleep) ?? false
            },
            allowSleep: allowSleep,
            woke: {
                HTTPCallsBridge().dropConnections(because: "woke from sleep")
            },
            networkChanged: {
                HTTPCallsBridge().dropConnections(because: "the network changed")
            },
            quit: {
                await MainActor.run {
                    #if os(macOS)
                        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
                    #endif
                }
            },
            uptime: {
                ProcessInfo.processInfo.systemUptime
            },
            copy: { text in
                await MainActor.run {
                    PlatformPasteboard.copy(text)
                }
            },
            paste: {
                await MainActor.run {
                    PlatformPasteboard.string()
                }
            },
            offerFile: { text, name, ready in
                await offer(text, name: name, ready: ready)
            },
            chooseReportDestination: { name in
                await chooseDestination(suggesting: name)
            },
            writeReport: { text, url in
                try Data(text.utf8).write(to: url, options: .atomic)
            },
            notificationPermission: {
                await SystemAlerts.permission()
            },
            postNotification: { id, title, body in
                await SystemAlerts.post(id: id, title: title, body: body)
            }
        )
    }

    private static func offer(
        _ text: String,
        name: String,
        ready: @escaping @Sendable (URL) async -> Void
    ) async {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kakusan", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return
        }
        await ready(file)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private static func chooseDestination(suggesting name: String) async -> URL? {
        #if os(macOS)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name
                panel.canCreateDirectories = true
                return panel.runModal() == .OK
                    ? panel.url
                    : nil
            }
        #else
            nil
        #endif
    }
}
