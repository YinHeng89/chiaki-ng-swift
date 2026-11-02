import Dependencies
import ChiakiModels
import ChiakiDiagnostics
import Darwin

/// Raises the process's open file limit at launch so streams do not run out of sockets.
enum FileDescriptorLimit {
    /// The highest soft limit the app asks for.
    static let ceiling: rlim_t = 4096

    /// Works out the soft limit to request, capped by the hard limit and ``FileDescriptorLimit/ceiling``.
    /// - Parameters:
    ///   - soft: The current soft limit.
    ///   - hard: The current hard limit.
    /// - Returns: The new soft limit, or `nil` when the current one is already high enough.
    static func target(soft: rlim_t, hard: rlim_t) -> rlim_t? {
        let target = min(hard, ceiling)
        guard soft < target else {
            return nil
        }
        return target
    }

    /// Reads the open file limit, raises the soft limit when it is below the target and logs what happened.
    static func raise() {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            report(
                "File descriptor limit could not be read: \(LogFormat.errno(errno)); it stays at the system default"
            )
            return
        }
        guard let target = target(soft: limit.rlim_cur, hard: limit.rlim_max) else {
            report(
                "File descriptor limit is \(limit.rlim_cur) (hard limit \(limit.rlim_max)); no raise needed",
                level: .debug
            )
            return
        }
        let previous = limit.rlim_cur
        limit.rlim_cur = target
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            report(
                "File descriptor limit could not be raised from \(previous) to \(target): \(LogFormat.errno(errno)); "
                    + "streams may fail with code 4329, 4629 or 4729 when sockets run out"
            )
            return
        }
        report(
            "File descriptor limit raised from \(previous) to \(target) (hard limit \(limit.rlim_max))",
            level: .info
        )
    }

    private static func report(_ message: String, level: LogLevel = .warning) {
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.app, level, message))
    }
}
