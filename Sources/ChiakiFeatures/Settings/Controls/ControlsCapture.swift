import ChiakiModels
import Foundation

/// One binding being captured: the control it is for, the input it listens to and the preset it lands in.
///
/// A capture only ever listens. When the input it receives already drives another control, the two controls
/// swap inputs and ``ControlsChange`` offers to undo it.
public struct ControlsCapture: Equatable, Sendable {
    /// The capture's id; completions for another id are ignored.
    public let id: UUID

    /// The control being bound.
    public let target: PlayStationControl

    /// The preset the binding goes into; `nil` for the selected preset.
    public var presetID: UUID?

    /// What kind of input is listened to.
    public var source: InputSource

    /// The controller family whose button names describe the captured input.
    public var family: ControllerFamily

    /// The button layout of the controller being bound.
    public var layout: ButtonLayout

    /// The configuration to restore when the capture ends without an input, set when starting it gave the
    /// controller its own preset.
    public var restores: ControlsConfiguration?

    /// Starts a capture.
    ///
    /// - Parameters:
    ///   - id: The capture's id.
    ///   - target: The control being bound.
    ///   - presetID: The preset the binding goes into.
    ///   - source: What kind of input is listened to.
    ///   - family: The family whose button names describe the input.
    ///   - layout: The button layout of the controller being bound.
    ///   - restores: The configuration to restore when the capture ends without an input.
    public init(
        id: UUID,
        target: PlayStationControl,
        presetID: UUID? = nil,
        source: InputSource = .macKey,
        family: ControllerFamily = .playStation,
        layout: ButtonLayout = .position,
        restores: ControlsConfiguration? = nil
    ) {
        self.id = id
        self.target = target
        self.presetID = presetID
        self.source = source
        self.family = family
        self.layout = layout
        self.restores = restores
    }
}

/// The latest change the Controls pane can undo: what happened, how to name controller buttons when
/// describing it, and the configuration from before it.
public struct ControlsChange: Equatable, Sendable {
    /// What a change did.
    public enum Summary: Equatable, Sendable {
        /// An input now drives a control that nothing else gave up.
        case assigned(InputBinding)

        /// An input moved to a control from `from`, which received `exchanged` or was left unbound.
        case moved(InputBinding, from: PlayStationControl, exchanged: InputBinding?)

        /// A control lost its input of one source.
        case cleared(PlayStationControl)

        /// A controller with this name was forgotten.
        case forgot(String)

        /// A player went back to each controller's own preset.
        case playerPresetRemoved(Int)
    }

    /// The change's id; an undo or expiry for another id is ignored.
    public let id: UUID

    /// What the change did.
    public let summary: Summary

    /// The name of the preset the change created for a controller or player, if it created one.
    public let createdPreset: String?

    /// The family whose button names describe controller inputs in the change.
    public let family: ControllerFamily

    /// The button layout of the controller the change was made for.
    public let layout: ButtonLayout

    /// The configuration from before the change.
    public let previous: ControlsConfiguration

    /// Records a change.
    ///
    /// - Parameters:
    ///   - id: The change's id.
    ///   - summary: What the change did.
    ///   - createdPreset: The name of the preset the change created, if any.
    ///   - family: The family whose button names describe controller inputs.
    ///   - layout: The controller's button layout.
    ///   - previous: The configuration from before the change.
    public init(
        id: UUID,
        summary: Summary,
        createdPreset: String? = nil,
        family: ControllerFamily = .playStation,
        layout: ButtonLayout = .position,
        previous: ControlsConfiguration
    ) {
        self.id = id
        self.summary = summary
        self.createdPreset = createdPreset
        self.family = family
        self.layout = layout
        self.previous = previous
    }

    /// Builds the summary of an assignment from what else it changed.
    ///
    /// - Parameters:
    ///   - binding: The input and the control it now drives.
    ///   - result: What else changed.
    /// - Returns: The summary.
    public static func summary(of binding: InputBinding, result: InputPreset.Assignment) -> Summary {
        guard let displaced = result.displaced else {
            return .assigned(binding)
        }
        return .moved(binding, from: displaced, exchanged: result.exchanged)
    }
}

/// Whose bindings the Controls pane shows and edits.
public enum ControlsEditTarget: Hashable, Sendable {
    /// The keyboard and mouse, which play as player 1.
    case keyboard

    /// One controller, by preference key, whether or not it is connected.
    case controller(String)

    /// One player's own bindings, by index, 0 for player 1.
    case player(Int)
}
