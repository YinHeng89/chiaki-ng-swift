#include "chiaki_bridge/core.hpp"

namespace chiaki_bridge {

void Request::cancel() const noexcept {
  static_cast<void>(source_.request_stop());
}

auto Request::cancelled() const noexcept -> bool {
  return source_.stop_requested();
}

auto Request::token() const noexcept -> libchiaking::platform::StopToken {
  return source_.token();
}

}  // namespace chiaki_bridge
