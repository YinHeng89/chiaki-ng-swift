#include <cmath>
#include <cstdint>
#include <cstdio>

#include "chiaki_bridge/media.hpp"

using chiaki_bridge::ControllerMotion;
using chiaki_bridge::MotionFusion;

static auto near(float value, float expected) -> bool {
  return std::fabs(value - expected) < 0.02F;
}

static auto length(const ControllerMotion& motion) -> float {
  return std::sqrt(
      motion.orient_x * motion.orient_x + motion.orient_y * motion.orient_y +
      motion.orient_z * motion.orient_z + motion.orient_w * motion.orient_w);
}

auto main() -> int {
  MotionFusion tracker;
  if (tracker.read()) {
    return 2;
  }
  tracker.recentre();
  if (tracker.read()) {
    return 3;
  }
  tracker.accelerometer(NAN, 1, 0, 0);
  if (tracker.read()) {
    return 4;
  }
  std::uint64_t time = 1000;
  for (int index = 0; index < 400; index++) {
    tracker.accelerometer(0, 1, 0, time);
    tracker.gyroscope(0, 0, 0, time);
    time += 4000;
  }
  auto motion = tracker.read();
  if (!motion || !near(motion->accel_y, 1) || !near(motion->gyro_x, 0) ||
      !near(length(*motion), 1)) {
    return 5;
  }
  const ControllerMotion rest = *motion;
  for (int index = 0; index < 50; index++) {
    tracker.gyroscope(0, 3.0F, 0, time);
    time += 4000;
  }
  motion = tracker.read();
  if (!motion || !near(motion->gyro_y, 3.0F) || !near(length(*motion), 1)) {
    return 6;
  }
  const float moved = std::fabs(motion->orient_x - rest.orient_x) +
                      std::fabs(motion->orient_y - rest.orient_y) +
                      std::fabs(motion->orient_z - rest.orient_z) +
                      std::fabs(motion->orient_w - rest.orient_w);
  if (moved < 0.05F) {
    return 7;
  }
  for (int index = 0; index < 50; index++) {
    tracker.accelerometer(0.5F, 0.8F, 0.2F, time);
    tracker.gyroscope(0, 0, 0, time);
    time += 4000;
  }
  tracker.recentre();
  motion = tracker.read();
  if (!motion || !near(motion->accel_x, 0) || !near(motion->accel_y, 1) ||
      !near(motion->accel_z, 0) || !near(length(*motion), 1)) {
    return 8;
  }
  std::puts(
      "PASS: motion fusion sampling, integration, non-finite rejection and "
      "console reset");
  return 0;
}
