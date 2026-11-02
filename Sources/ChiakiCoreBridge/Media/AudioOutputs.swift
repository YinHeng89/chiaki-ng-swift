import ChiakiBridge
import ChiakiModels
import CxxStdlib

/// The audio output devices connected to this computer.
public enum AudioOutputs {
    /// The names of the connected output devices, each once.
    ///
    /// - Returns: The names.
    public static func names() -> [String] {
        chiaki_bridge.AudioOutputs.names().map(String.init)
    }

    /// Whether a device plays into headphones.
    ///
    /// - Parameter device: The device's name, or `nil` for the system's default output.
    /// - Returns: `AudioOutputKind.headphones` or `AudioOutputKind.speakers`.
    public static func kind(device: String?) -> AudioOutputKind {
        chiaki_bridge.AudioOutputs.is_headphones(std.string(device ?? ""))
            ? .headphones
            : .speakers
    }
}

/// Calls back on the main actor whenever the default audio output or its source changes.
///
/// Watching stops on ``stop()`` or when the watcher is released.
@MainActor
public final class AudioOutputWatcher {
    private let changed: @MainActor () -> Void
    private var watch: chiaki_bridge.AudioOutputWatch?

    /// Starts watching.
    ///
    /// - Parameter changed: Called on the main actor after each change.
    public init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        watch = chiaki_bridge.AudioOutputWatch.start(
            { context in
                guard let context else {
                    return
                }
                let watcher = Unmanaged<AudioOutputWatcher>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    watcher.changed()
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Stops watching.
    public func stop() {
        watch?.stop()
        watch = nil
    }

    isolated deinit {
        watch?.stop()
    }
}
