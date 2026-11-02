#include "boundary.hpp"
#include "chiaki_bridge/network.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

auto NetworkBridge::nat_type(const Request& request) -> NatTypeOutcome {
  return Boundary::fenced(NatTypeOutcome::closed(), [&]() -> NatTypeOutcome {
    const auto opened = Opened::shared();
    if (!opened) {
      return NatTypeOutcome::closed();
    }
    auto found = opened->play().nat_type(request.token());
    if (!found) {
      return NatTypeOutcome::failed(found.error().reason);
    }
    return NatTypeOutcome::found(found.value());
  });
}

}  // namespace chiaki_bridge
