#include <utility>

#include "account_ids.hpp"
#include "boundary.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::consoles::Host;

auto ConsolesBridge::everything() -> ConsoleList {
  return Boundary::fenced(ConsoleList{}, [] {
    ConsoleList list;
    if (const auto opened = Opened::shared()) {
      for (const auto& console : opened->consoles().everything()) {
        list.push_back(CoreSession::facts_of(*console));
      }
    }
    return list;
  });
}

auto ConsolesBridge::paired_with(const Bytes& hardware_id,
                                 const Bytes& account_id) -> bool {
  return Boundary::fenced(false, [&] {
    const auto opened = Opened::shared();
    if (!opened) {
      return false;
    }
    const auto console = opened->console(hardware_id);
    const auto user = opened->user(account_id);
    return console && user && console->is_paired_with(*user);
  });
}

auto ConsolesBridge::forget(const Bytes& hardware_id)
    -> std::optional<ConsolesRefusal> {
  return Boundary::fenced(
      std::optional<ConsolesRefusal>{ConsolesRefusal::core_closed},
      [&]() -> std::optional<ConsolesRefusal> {
        const auto opened = Opened::shared();
        if (!opened) {
          return ConsolesRefusal::core_closed;
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return ConsolesRefusal::unknown_console;
        }
        if (!opened->consoles().forget(*console)) {
          return ConsolesRefusal::store_unavailable;
        }
        return std::nullopt;
      });
}

auto ConsolesBridge::unpair(const Bytes& account_id, const Bytes& hardware_id)
    -> std::optional<ConsolesRefusal> {
  const auto account = AccountIds::account_of(account_id);
  if (!account) {
    return ConsolesRefusal::unknown_user;
  }
  return Boundary::fenced(
      std::optional<ConsolesRefusal>{ConsolesRefusal::core_closed},
      [&]() -> std::optional<ConsolesRefusal> {
        const auto opened = Opened::shared();
        if (!opened) {
          return ConsolesRefusal::core_closed;
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return ConsolesRefusal::unknown_console;
        }
        if (!opened->consoles().unpair(*account, *console)) {
          return ConsolesRefusal::store_unavailable;
        }
        return std::nullopt;
      });
}

auto ConsolesBridge::check(const Request& request, const Bytes& hardware_id)
    -> CheckOutcome {
  return Boundary::fenced(
      CheckOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> CheckOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return CheckOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return CheckOutcome::refused(ConsolesRefusal::unknown_console);
        }
        const auto checked = console->check(request.token());
        if (!checked) {
          return CheckOutcome::unreachable(
              UnreachableFacts{console->presence(), checked.error()});
        }
        return CheckOutcome::checked(console->presence());
      });
}

auto ConsolesBridge::route(const Request& request, const Bytes& account_id,
                           const Bytes& hardware_id)
    -> std::optional<libchiaking::consoles::Route> {
  return Boundary::fenced(std::optional<libchiaking::consoles::Route>{},
                          [&]() -> std::optional<libchiaking::consoles::Route> {
                            const auto opened = Opened::shared();
                            if (!opened) {
                              return std::nullopt;
                            }
                            const auto console = opened->console(hardware_id);
                            const auto user = opened->user(account_id);
                            if (!console || !user) {
                              return std::nullopt;
                            }
                            const auto route =
                                console->route_for(*user, request.token());
                            if (!route) {
                              return std::nullopt;
                            }
                            return route.value();
                          });
}

auto ConsolesBridge::wake(const Request& request, const Bytes& account_id,
                          const Bytes& hardware_id, bool wait) -> WakeOutcome {
  return Boundary::fenced(
      WakeOutcome::refused(ConsolesRefusal::core_closed), [&]() -> WakeOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return WakeOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return WakeOutcome::refused(ConsolesRefusal::unknown_console);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return WakeOutcome::refused(ConsolesRefusal::unknown_user);
        }
        const auto woken = wait ? console->wake_and_wait(*user, request.token())
                                : console->wake(*user);
        if (!woken) {
          return WakeOutcome::declined(woken.error());
        }
        return WakeOutcome::woken();
      });
}

auto ConsolesBridge::rename(const Bytes& hardware_id, const std::string& name)
    -> ChangeOutcome {
  return Boundary::fenced(
      ChangeOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> ChangeOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return ChangeOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return ChangeOutcome::refused(ConsolesRefusal::unknown_console);
        }
        if (const auto renamed = console->rename(name); !renamed) {
          return ChangeOutcome::unchanged(renamed.error());
        }
        return ChangeOutcome::changed();
      });
}

auto ConsolesBridge::moved_to(const Bytes& hardware_id,
                              const std::string& address) -> ChangeOutcome {
  return Boundary::fenced(
      ChangeOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> ChangeOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return ChangeOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return ChangeOutcome::refused(ConsolesRefusal::unknown_console);
        }
        auto host = Host::create(address, console->generation());
        if (!host) {
          return ChangeOutcome::refused(
              host.error() == Host::Invalid::ipv6_needs_ps5
                  ? ConsolesRefusal::address_not_for_generation
                  : ConsolesRefusal::invalid_address);
        }
        if (const auto moved = console->moved_to(std::move(host.value()));
            !moved) {
          return ChangeOutcome::unchanged(moved.error());
        }
        return ChangeOutcome::changed();
      });
}

}  // namespace chiaki_bridge
