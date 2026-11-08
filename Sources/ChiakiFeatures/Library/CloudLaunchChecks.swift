import ChiakiModels
import Foundation

/// The progress of the checks the stream service runs before a cloud game launches, shown as a row of steps on
/// the game's detail and moving from starting through each step to cleared, launched, refused or unanswered.
public struct CloudLaunchChecks: Equatable, Sendable {
    /// One check shown in the launch step row.
    public enum Step: String, CaseIterable, Sendable {
        /// PS Now membership; PS Plus Premium cloud streaming; ownership of the game; the game being a cloud
        /// title; region and parental restrictions; and the game's release.
        case membership, premium, yourCopy, cloudGame, restrictions, release

        /// The step's short label under its symbol.
        public var label: LocalizedStringResource {
            switch self {
            case .membership:
                .libraryLaunchStepMembership
            case .premium:
                .libraryLaunchStepPremium
            case .yourCopy:
                .libraryLaunchStepYourCopy
            case .cloudGame:
                .libraryLaunchStepCloudGame
            case .restrictions:
                .libraryLaunchStepRestrictions
            case .release:
                .libraryLaunchStepRelease
            }
        }

        /// Maps a check reported by the core onto its step, or `nil` for the library load that has no step of
        /// its own.
        ///
        /// - Parameter check: The check the core reported.
        public init?(_ check: CloudLaunchCheck) {
            switch check {
            case .loadingLibrary:
                return nil
            case .membership:
                self = .membership
            case .cloudStreaming:
                self = .premium
            case .ownership, .entitlement:
                self = .yourCopy
            case .cloudGame:
                self = .cloudGame
            case .exclusions:
                self = .restrictions
            case .release:
                self = .release
            }
        }

        /// The steps checked for a game: membership and release for PS Now titles, and the full PS Plus
        /// Premium row otherwise.
        ///
        /// - Parameter game: The game being launched.
        /// - Returns: The steps in the order they are checked.
        public static func row(for game: CloudGame) -> [Step] {
            game.streamServiceType == "psnow"
                ? [.membership, .release]
                : [.premium, .yourCopy, .cloudGame, .restrictions, .release]
        }
    }

    /// How one step is marked in the row.
    public enum Mark: Equatable, Sendable {
        /// Not reached yet; running now; passed; the step at which the stream service refused or the checks stopped.
        case unchecked, checking, passed, refused
    }

    /// Where the launch checks have got to.
    public enum Phase: Equatable, Sendable {
        /// The checks were requested but no step has reported yet.
        case starting
        /// The stream service is checking the given step.
        case checking(Step)
        /// Every check passed, carrying what the stream service cleared the launch with, if anything.
        case cleared(CloudLaunchClearanceToken?)
        /// The cleared launch was handed to the stream.
        case launched
        /// The stream service refused the launch, during the given step when one was running.
        case refused(during: Step?, CloudClearanceRefusal)
        /// The checks could not be completed, during the given step when one was running.
        case unanswered(during: Step?, CatalogFailure)
    }

    /// The launch request being checked.
    public let request: CloudLaunchRequest
    /// The attempt that started these checks, so answers from an earlier attempt are ignored.
    public let attempt: UUID
    /// The game whose card shows the checks, which is the bundle when a game inside a bundle is launched.
    public let gameID: String
    /// The steps shown for the launched game.
    public let steps: [Step]
    /// Where the checks have got to.
    public private(set) var phase = Phase.starting

    /// Starts the checks for a launch request, before any step has reported.
    ///
    /// - Parameters:
    ///   - request: The launch request being checked.
    ///   - attempt: The attempt that started the checks.
    ///   - card: The game whose card shows the checks, or `nil` when it is the launched game.
    public init(request: CloudLaunchRequest, attempt: UUID, shownOn card: String? = nil) {
        self.request = request
        self.attempt = attempt
        gameID = card ?? request.game.id
        steps = Step.row(for: request.game)
    }

    /// The identifier of the game being launched, which differs from ``gameID`` when it was chosen from a
    /// bundle.
    public var launchedID: String {
        request.game.id
    }

    /// Whether the checks are still waiting on the stream service.
    public var isRunning: Bool {
        switch phase {
        case .starting, .checking:
            true
        case .cleared, .launched, .refused, .unanswered:
            false
        }
    }

    /// The player-facing reason the checks stopped, or `nil` while they run or once they pass.
    public var reason: LocalizedStringResource? {
        switch phase {
        case .refused(_, let refusal):
            CloudClearanceRefusalMessage.text(for: refusal)
        case .unanswered(_, let failure):
            failure.needsSignIn
                ? CloudPlaybackFailureMessage.text(for: .signInRequired)
                : .libraryLaunchStepUnanswered
        case .starting, .checking, .cleared, .launched:
            nil
        }
    }

    /// The request to hand to the stream once the checks clear, updated with what the stream service cleared it
    /// with; `nil` until then.
    public var handOff: CloudLaunchRequest? {
        guard case .cleared(let launch) = phase else {
            return nil
        }
        return request.cleared(by: launch)
    }

    /// How a step is marked given where the checks have got to: steps before the current one pass, the
    /// current one is checking or refused, and later ones are unchecked.
    ///
    /// - Parameter step: The step to mark.
    /// - Returns: The step's mark.
    public func mark(_ step: Step) -> Mark {
        guard let index = steps.firstIndex(of: step) else {
            return .unchecked
        }
        switch phase {
        case .starting:
            return .unchecked
        case .cleared, .launched:
            return .passed
        case .checking(let current):
            return mark(index, reaching: current, as: .checking)
        case .refused(let during, _), .unanswered(let during, _):
            guard let during else {
                return .unchecked
            }
            return mark(index, reaching: during, as: .refused)
        }
    }

    private func mark(_ index: Int, reaching step: Step, as reached: Mark) -> Mark {
        guard let position = steps.firstIndex(of: step) else {
            return .unchecked
        }
        if index < position {
            return .passed
        }
        return index == position
            ? reached
            : .unchecked
    }

    private var current: Step? {
        if case .checking(let step) = phase {
            return step
        }
        return nil
    }

    /// Moves the checks to the step a reported check belongs to, ignoring reports once the checks finished
    /// and reports that would step backwards.
    ///
    /// - Parameter check: The check the core reported.
    public mutating func observe(_ check: CloudLaunchCheck) {
        guard isRunning, let step = Step(check), steps.contains(step) else {
            return
        }
        if let current, let previous = steps.firstIndex(of: current), let next = steps.firstIndex(of: step),
           next < previous {
            return
        }
        phase = .checking(step)
    }

    /// Records the stream service's answer, clearing or refusing the launch at the current step, or marking it
    /// unanswered when the stream service could not be asked.
    ///
    /// - Parameter result: The stream service's clearance, or the reason no answer came back.
    public mutating func finish(_ result: Result<CloudLaunchDecision, CatalogFailure>) {
        guard isRunning else {
            return
        }
        switch result {
        case .success(.cleared(let launch)):
            phase = .cleared(launch)
        case .success(.refused(let refusal)):
            phase = .refused(during: current, refusal)
        case .failure(let failure):
            phase = .unanswered(during: current, failure)
        }
    }

    /// Marks cleared checks as handed to the stream.
    public mutating func launched() {
        guard case .cleared = phase else {
            return
        }
        phase = .launched
    }
}
