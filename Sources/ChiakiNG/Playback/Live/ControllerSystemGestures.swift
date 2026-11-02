import PlatformUI
import GameController
import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Reference-counts the holders that need controller system gestures disabled and reports when capture must
/// start or stop.
struct ControllerSystemGestureHolds: Equatable {
    /// Whether any holder currently keeps system gestures captured.
    enum State: Equatable {
        /// No holder is active and system gestures behave normally.
        case idle
        /// One or more holders, identified by their tokens, keep system gestures captured.
        case holding(Set<UUID>)
    }

    /// The side effect a hold change requires from the owner.
    enum Effect: Equatable {
        /// Nothing needs to change.
        case none
        /// The first hold arrived, so system gestures must be captured.
        case beginCapture
        /// The last hold was released, so system gestures must be restored.
        case endCapture
    }

    /// The current set of active holds.
    private(set) var state = State.idle

    /// Registers a hold and reports whether it is the first one.
    /// - Parameter hold: The token identifying the new hold.
    /// - Returns: ``ControllerSystemGestureHolds/Effect/beginCapture`` for the first hold, otherwise
    ///   ``ControllerSystemGestureHolds/Effect/none``.
    mutating func acquire(_ hold: UUID) -> Effect {
        switch state {
        case .idle:
            state = .holding([hold])
            return .beginCapture
        case .holding(var holds):
            holds.insert(hold)
            state = .holding(holds)
            return .none
        }
    }

    /// Removes a hold and reports whether it was the last one.
    /// - Parameter hold: The token of the hold to remove; unknown tokens are ignored.
    /// - Returns: ``ControllerSystemGestureHolds/Effect/endCapture`` when no holds remain, otherwise
    ///   ``ControllerSystemGestureHolds/Effect/none``.
    mutating func release(_ hold: UUID) -> Effect {
        guard case .holding(var holds) = state, holds.remove(hold) != nil else {
            return .none
        }
        if holds.isEmpty {
            state = .idle
            return .endCapture
        }
        state = .holding(holds)
        return .none
    }
}

/// A token that keeps controller system gestures disabled for as long as it lives and releases its hold when
/// deallocated.
@MainActor final class ControllerSystemGestureHold {
    private let id: UUID
    private let owner: ControllerSystemGestureOwner

    /// Creates a hold token bound to its owner.
    /// - Parameters:
    ///   - id: The identifier the owner registered for this hold.
    ///   - owner: The owner to notify when the token is deallocated.
    init(id: UUID, owner: ControllerSystemGestureOwner) {
        self.id = id
        self.owner = owner
    }

    isolated deinit {
        owner.release(id)
    }
}

/// Disables system gestures such as the Home and Share buttons on every connected controller while any hold
/// is alive, and restores each button's previous state when the last hold ends.
@MainActor final class ControllerSystemGestureOwner {
    private struct Saved {
        weak var element: GCControllerElement?
        let state: GCControllerElement.SystemGestureState
    }

    private struct Capture {
        let previousBackgroundMonitoring: Bool
        let observer: NSObjectProtocol
        var saved: [ObjectIdentifier: Saved] = [:]
    }

    /// The reference count of active holds.
    private(set) var holds = ControllerSystemGestureHolds()
    private var capture: Capture?

    /// Takes a new hold, capturing system gestures on all current and later connected controllers if this is
    /// the first.
    /// - Returns: A token that releases the hold when it is deallocated.
    func acquire() -> ControllerSystemGestureHold {
        let id = UUID()
        if holds.acquire(id) == .beginCapture {
            beginCapture()
        }
        return ControllerSystemGestureHold(id: id, owner: self)
    }

    fileprivate func release(_ id: UUID) {
        if holds.release(id) == .endCapture {
            endCapture()
        }
    }

    private func beginCapture() {
        let observer = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.disableSystemGestures()
            }
        }
        capture = Capture(
            previousBackgroundMonitoring: GCController.shouldMonitorBackgroundEvents,
            observer: observer
        )
        GCController.shouldMonitorBackgroundEvents = true
        disableSystemGestures()
    }

    private func endCapture() {
        guard let capture else {
            return
        }
        self.capture = nil
        NotificationCenter.default.removeObserver(capture.observer)
        for saved in capture.saved.values {
            saved.element?.preferredSystemGestureState = saved.state
        }
        GCController.shouldMonitorBackgroundEvents = capture.previousBackgroundMonitoring
    }

    private func disableSystemGestures() {
        guard var current = capture else {
            return
        }
        current.saved = current.saved.filter {
            $0.value.element != nil
        }
        for controller in GCController.controllers() {
            for element in controller.physicalInputProfile.buttons.values
                where element.isBoundToSystemGesture {
                let key = ObjectIdentifier(element)
                if current.saved[key] == nil {
                    current.saved[key] = Saved(element: element, state: element.preferredSystemGestureState)
                }
                element.preferredSystemGestureState = .disabled
            }
        }
        capture = current
    }
}
