import ChiakiModels
import Dependencies
import Foundation

/// Reaches the connected controllers: lists them, tests their rumble and shows lightbar colours on them.
public struct ControllersClient: Sendable {
    /// Lists the connected controllers.
    public var devices: @Sendable () async throws -> [ControllerDevice]

    /// Rumbles a controller at a strength.
    public var testRumble: @Sendable (UInt32, Double) async throws -> Void

    /// Shows lightbar colours on the connected controllers.
    public var showLights: @MainActor @Sendable (ControllerLightbars) -> Void

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - devices: Lists the connected controllers.
    ///   - testRumble: Rumbles a controller.
    ///   - showLights: Shows lightbar colours on the connected controllers.
    public init(
        devices: @escaping @Sendable () async throws -> [ControllerDevice],
        testRumble: @escaping @Sendable (UInt32, Double) async throws -> Void,
        showLights: @escaping @MainActor @Sendable (ControllerLightbars) -> Void
    ) {
        self.devices = devices
        self.testRumble = testRumble
        self.showLights = showLights
    }
}

extension ControllersClient: TestDependencyKey {
    /// Lists nothing, refuses rumble and shows no colours.
    public static let testValue = Self(
        devices: {
            []
        },
        testRumble: { _, _ in
            throw InputFailure.unavailable
        },
        showLights: { _ in
        }
    )
}

extension DependencyValues {
    /// Reaches the connected controllers.
    public var controllers: ControllersClient {
        get {
            self[ControllersClient.self]
        }
        set {
            self[ControllersClient.self] = newValue
        }
    }
}
