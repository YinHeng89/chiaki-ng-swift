import ChiakiClients
import ChiakiModels
import Foundation

extension StreamSessionClient {
    /// The client over the native lease and the app's launcher, with the tuning read from and written to the
    /// account's stored console, cloud and sound settings. The player operations are left to the app, which
    /// owns the player controls.
    ///
    /// - Parameters:
    ///   - leases: The one native lease.
    ///   - launcher: Prepares and runs the player for each kind of stream.
    /// - Returns: The live client.
    public static func live(leases: StreamLeases, launcher: any StreamLauncher) -> StreamSessionClient {
        StreamSessionClient(
            start: { id, source in
                start(id, source: source, leases: leases, launcher: launcher)
            },
            submitAccessCode: { id, prompt, code in
                await submit(code, for: prompt, in: id, leases: leases)
            },
            keyboard: { id, command in
                await MainActor.run {
                    leases.session(id)?.send(command) ?? false
                }
            },
            goHome: { id in
                await MainActor.run {
                    leases.session(id)?.goHome() ?? false
                }
            },
            selectDatacenter: { id, name in
                await MainActor.run {
                    leases.session(id)?.selectDatacenter(name) ?? false
                }
            },
            tune: { id, tuning in
                await MainActor.run {
                    leases.session(id)?.apply(tuning)
                }
            },
            leave: { id, exit in
                await leases.stop(id, exit: exit)
            },
            loadTuning: { context in
                try await StreamTuning.load(context)
            },
            saveTuning: { context, configuration in
                try await StreamTuning.save(context, configuration)
            }
        )
    }

    private static func start(
        _ id: StreamSessionID,
        source: StreamSource,
        leases: StreamLeases,
        launcher: any StreamLauncher
    ) -> AsyncThrowingStream<StreamSessionEvent, any Error> {
        let (events, continuation) = AsyncThrowingStream.makeStream(of: StreamSessionEvent.self)
        let task = Task { @MainActor in
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            guard leases.acquire(id, kind: source.kind) else {
                continuation.finish(throwing: StreamFailure.busy)
                return
            }
            defer {
                leases.release(id)
            }
            do {
                try await launcher.launch(source, opening: StreamSessionOpener(
                    id: id,
                    leases: leases,
                    continuation: continuation
                ))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { termination in
            guard case .cancelled = termination else {
                return
            }
            task.cancel()
            Task { @MainActor in
                await leases.stop(id)
            }
        }
        return events
    }

    @MainActor
    private static func submit(
        _ code: StreamAccessCode,
        for prompt: StreamAccessPrompt,
        in id: StreamSessionID,
        leases: StreamLeases
    ) async -> Bool {
        guard let session = leases.session(id) else {
            return false
        }
        return await session.submit(code, for: prompt)
    }
}
