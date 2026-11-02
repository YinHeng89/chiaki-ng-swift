#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "console_ids.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

auto AccountConsolesBridge::on_account(
    const Request& request, const Bytes& account_id,
    libchiaking::consoles::Generation generation) -> AccountConsolesOutcome {
  return Boundary::fenced(
      AccountConsolesOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> AccountConsolesOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return AccountConsolesOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return AccountConsolesOutcome::refused(ConsolesRefusal::unknown_user);
        }
        const auto listed = opened->consoles().consoles_on_account(
            *user, generation, request.token());
        if (!listed) {
          return AccountConsolesOutcome::unanswered(listed.error());
        }
        AccountConsoleList consoles;
        for (const auto& console : listed.value()) {
          AccountConsoleFacts facts{};
          facts.device_uid = IdentifierBytes::of(console.device_uid());
          facts.name = console.name();
          facts.generation = console.generation();
          facts.remote_play_enabled = console.remote_play_enabled();
          facts.main_ps4 = console.is_main_ps4();
          consoles.push_back(facts);
        }
        return AccountConsolesOutcome::listed(std::move(consoles));
      });
}

}  // namespace chiaki_bridge
