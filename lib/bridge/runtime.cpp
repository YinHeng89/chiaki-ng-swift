#include "runtime.hpp"

namespace chiaki_bridge {

auto Runtime::process() -> Runtime& {
  static auto* const runtime = new Runtime;
  return *runtime;
}

}  // namespace chiaki_bridge
