/// Where a starting stream is before its first frame.
///
/// Console and guest streams count the core's start retries. Cloud streams move forward through
/// ``CloudStartStep``s; the queue position and the datacenter choice are waits inside a step.
public enum StreamStartStage: Equatable, Sendable {
    /// A console or guest stream is connecting; `attempt` counts the core's retries from zero.
    case connecting(attempt: Int)

    /// A cloud stream is at a step, possibly inside a wait the user sees.
    case cloud(CloudStartStep, wait: CloudStartWait? = nil)

    /// The cloud step, when the stream is a cloud stream.
    public var cloudStep: CloudStartStep? {
        if case .cloud(let step, _) = self {
            return step
        }
        return nil
    }

    /// The cloud wait, when the stream is a cloud stream inside one.
    public var cloudWait: CloudStartWait? {
        if case .cloud(_, let wait) = self {
            return wait
        }
        return nil
    }

    /// The datacenter choice, when the cloud stream offered one.
    public var datacenterChoice: CloudDatacenterChoice? {
        if case .datacenter(let choice) = cloudWait {
            return choice
        }
        return nil
    }

    /// The queue position, when the cloud stream is queued.
    public var queuePosition: Int? {
        if case .queued(let position) = cloudWait {
            return position
        }
        return nil
    }

    /// Records that the core retried a console or guest start.
    ///
    /// - Parameter attempt: The retry, counted from one.
    /// - Returns: `true` when `attempt` directly follows the current attempt.
    public mutating func retried(_ attempt: Int) -> Bool {
        guard case .connecting(let current) = self, attempt == current + 1 else {
            return false
        }
        self = .connecting(attempt: attempt)
        return true
    }

    /// Moves a cloud start to a later step.
    ///
    /// An open datacenter choice carries over to the new step; a queue position does not.
    ///
    /// - Parameter step: The step the core reported.
    /// - Returns: `true` when `step` comes after the current step.
    public mutating func advance(to step: CloudStartStep) -> Bool {
        guard case .cloud(let current, var wait) = self, step > current else {
            return false
        }
        if case .queued = wait {
            wait = nil
        }
        self = .cloud(step, wait: wait)
        return true
    }

    /// Records the cloud queue position, or that the queue was left.
    ///
    /// - Parameter position: The position, or `nil` once the account is no longer queued.
    /// - Returns: `true` when the wait changed; a datacenter choice is never replaced by the queue.
    public mutating func queue(at position: Int?) -> Bool {
        guard case .cloud(let step, let wait) = self else {
            return false
        }
        switch (wait, position) {
        case (.datacenter, _), (nil, nil):
            return false
        case (.queued(let current), let position?) where current == position:
            return false
        case (_, let position?):
            self = .cloud(step, wait: .queued(position: position))
        case (.queued, nil):
            self = .cloud(step, wait: nil)
        }
        return true
    }

    /// Opens the datacenter choice for an offer.
    ///
    /// - Parameter offer: The datacenters offered.
    /// - Returns: `true` when the cloud start had no choice yet and the offer is not empty.
    public mutating func offer(_ offer: CloudDatacenterLaunchOffer) -> Bool {
        guard case .cloud(let step, let wait) = self, !offer.isEmpty else {
            return false
        }
        if case .datacenter = wait {
            return false
        }
        self = .cloud(step, wait: .datacenter(CloudDatacenterChoice(offer: offer)))
        return true
    }

    /// Moves the open datacenter choice.
    ///
    /// - Parameter change: Applies one ``CloudDatacenterChoice`` transition and returns whether it moved.
    /// - Returns: `true` when there is a choice and `change` moved it.
    public mutating func updateDatacenterChoice(_ change: (inout CloudDatacenterChoice) -> Bool) -> Bool {
        guard case .cloud(let step, .datacenter(var choice)) = self, change(&choice) else {
            return false
        }
        self = .cloud(step, wait: .datacenter(choice))
        return true
    }

    /// Closes the datacenter choice because the core reported the datacenter it connected to.
    ///
    /// - Returns: `true` when a choice was closed.
    public mutating func datacenterSelected() -> Bool {
        guard case .cloud(let step, .datacenter) = self else {
            return false
        }
        self = .cloud(step, wait: nil)
        return true
    }
}
