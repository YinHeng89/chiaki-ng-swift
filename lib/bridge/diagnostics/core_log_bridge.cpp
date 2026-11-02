#include "boundary.hpp"
#include "chiaki_bridge/diagnostics.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

auto CoreLogBridge::read(std::size_t limit) -> CoreLogLines {
  return Boundary::fenced(CoreLogLines{}, [&] {
    CoreLogLines lines;
    const auto opened = Opened::shared();
    if (!opened) {
      return lines;
    }
    for (const auto& entry : opened->read_idle_logs(limit)) {
      lines.push_back({entry.severity(), entry.line()});
    }
    return lines;
  });
}

}  // namespace chiaki_bridge
