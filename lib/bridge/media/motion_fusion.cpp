#include "chiaki_bridge/media.hpp"

namespace chiaki_bridge {

auto MotionFusion::stamp(std::uint64_t timestamp_us) noexcept
    -> std::chrono::microseconds {
  return std::chrono::microseconds{
      static_cast<std::chrono::microseconds::rep>(timestamp_us)};
}

void MotionFusion::accelerometer(float x, float y, float z,
                                 std::uint64_t timestamp_us) noexcept {
  tracker_.accelerometer({x, y, z}, stamp(timestamp_us));
}

void MotionFusion::gyroscope(float x, float y, float z,
                             std::uint64_t timestamp_us) noexcept {
  tracker_.gyroscope({x, y, z}, stamp(timestamp_us));
}

void MotionFusion::recentre() noexcept { tracker_.recentre(); }

void MotionFusion::tune(bool tilt_correction,
                        bool angular_velocity_deadband) noexcept {
  tracker_.set_tilt_correction(tilt_correction);
  tracker_.set_angular_velocity_deadband(angular_velocity_deadband);
}

auto MotionFusion::read() const noexcept -> std::optional<ControllerMotion> {
  if (!tracker_.sampled()) {
    return std::nullopt;
  }
  libchiaking::controllers::ControllerState state;
  tracker_.apply(state);
  return ControllerMotion{
      .gyro_x = state.gyro_x,
      .gyro_y = state.gyro_y,
      .gyro_z = state.gyro_z,
      .accel_x = state.accel_x,
      .accel_y = state.accel_y,
      .accel_z = state.accel_z,
      .orient_x = state.orient_x,
      .orient_y = state.orient_y,
      .orient_z = state.orient_z,
      .orient_w = state.orient_w,
  };
}

}  // namespace chiaki_bridge
