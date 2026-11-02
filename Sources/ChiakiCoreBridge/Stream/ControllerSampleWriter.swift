import ChiakiBridge
import ChiakiModels

/// Writes a `ControllerState` as the controller sample the core sends to the console.
public enum ControllerSampleWriter {
    /// The sample for a controller state.
    ///
    /// - Parameter state: The state to send.
    /// - Returns: The core's sample.
    public static func sample(of state: ControllerState) -> chiaki_bridge.ControllerSample {
        var sample = chiaki_bridge.ControllerSample()
        sample.buttons = state.buttons
        sample.l2 = state.leftTrigger
        sample.r2 = state.rightTrigger
        sample.left_x = state.leftX
        sample.left_y = state.leftY
        sample.right_x = state.rightX
        sample.right_y = state.rightY
        sample.first_touch.value = state.touches.first.map(touch(of:))
        sample.second_touch.value = state.touches.second.map(touch(of:))
        sample.motion.value = state.motion.map(motion(of:))
        sample.trigger_states.value = state.triggerStates.map { triggers in
            var states = chiaki_bridge.TriggerStates()
            states.left = triggers.left
            states.right = triggers.right
            return states
        }
        return sample
    }

    private static func touch(of touch: ControllerTouch) -> chiaki_bridge.TouchSample {
        var sample = chiaki_bridge.TouchSample()
        sample.id = touch.id & 0x7f
        sample.x = touch.x
        sample.y = touch.y
        return sample
    }

    private static func motion(of motion: ControllerMotion) -> chiaki_bridge.ControllerMotion {
        var sample = chiaki_bridge.ControllerMotion()
        sample.gyro_x = motion.gyro.x
        sample.gyro_y = motion.gyro.y
        sample.gyro_z = motion.gyro.z
        sample.accel_x = motion.accel.x
        sample.accel_y = motion.accel.y
        sample.accel_z = motion.accel.z
        sample.orient_x = motion.orientation.x
        sample.orient_y = motion.orientation.y
        sample.orient_z = motion.orientation.z
        sample.orient_w = motion.orientation.w
        return sample
    }
}
