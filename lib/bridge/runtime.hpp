#pragma once

#include <libchiaking/platform/platform.hpp>

namespace chiaki_bridge {

class Runtime {
 public:
  static auto process() -> Runtime&;

  Runtime(const Runtime&) = delete;
  auto operator=(const Runtime&) -> Runtime& = delete;

  auto threading() noexcept -> libchiaking::platform::ThreadingProvider& {
    return threading_;
  }
  auto clock() noexcept -> libchiaking::platform::ClockProvider& {
    return clock_;
  }
  auto wall_clock() noexcept -> libchiaking::platform::ClockProvider& {
    return wall_clock_;
  }

 private:
  Runtime() = default;

  libchiaking::platform::DefaultThreadingProvider threading_;
  libchiaking::platform::SteadyClock clock_;
  libchiaking::platform::SystemClock wall_clock_;
};

}  // namespace chiaki_bridge
