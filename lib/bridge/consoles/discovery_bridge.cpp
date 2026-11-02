#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::consoles::SearchRanges;

DiscoveryBridge::Lookout::Lookout(NetworkViewWatcher watcher,
                                  void* context) noexcept
    : watcher_(watcher), context_(context) {}

void DiscoveryBridge::Lookout::on_view(
    const libchiaking::consoles::NetworkView& view) {
  if (watcher_ == nullptr) {
    return;
  }
  NetworkView facts{};
  for (const auto& console : view.nearby) {
    facts.nearby.push_back(CoreSession::facts_of(*console));
  }
  facts.targets = view.targets;
  facts.visited = view.visited;
  facts.network_available = view.network_available;
  facts.permission_denied = view.permission_denied;
  facts.broadcast_ranges = view.broadcast_ranges;
  for (const auto& subnet : view.unicast_ranges) {
    facts.unicast_ranges.push_back(subnet.text());
  }
  watcher_(&facts, context_);
}

auto DiscoveryBridge::ranges(const Texts& subnets, bool unicast)
    -> SearchOutcome {
  auto parsed = SearchRanges::parse(subnets, unicast);
  if (!parsed) {
    return SearchOutcome::invalid(parsed.error());
  }
  return SearchOutcome::covered(parsed.value().target_count());
}

auto DiscoveryBridge::search(const Request& request, const Texts& subnets,
                             bool unicast, NetworkViewWatcher watcher,
                             void* context) -> SearchOutcome {
  return Boundary::fenced(
      SearchOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> SearchOutcome {
        auto parsed = SearchRanges::parse(subnets, unicast);
        if (!parsed) {
          return SearchOutcome::invalid(parsed.error());
        }
        const auto opened = Opened::shared();
        if (!opened) {
          return SearchOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto targets = parsed.value().target_count();
        Lookout lookout{watcher, context};
        const auto searched = opened->consoles().find_on_my_network(
            parsed.value(), lookout, request.token());
        if (!searched) {
          return SearchOutcome::failed(
              SearchFailureFacts{targets, searched.error()});
        }
        return SearchOutcome::covered(targets);
      });
}

}  // namespace chiaki_bridge
