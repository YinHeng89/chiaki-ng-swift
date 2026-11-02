#include <span>
#include <utility>

#include "account_ids.hpp"
#include "boundary.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "console_ids.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::consoles::AccountConsole;
using libchiaking::consoles::DeviceUid;
using libchiaking::consoles::Generation;
using libchiaking::consoles::Host;
using libchiaking::consoles::PairingPin;
using libchiaking::consoles::PairingProgress;

PairingBridge::Steps::Steps(PairingProgressWatcher watcher,
                            void* context) noexcept
    : watcher_(watcher), context_(context) {}

void PairingBridge::Steps::on_progress(const PairingProgress& progress) {
  if (watcher_ != nullptr) {
    watcher_(&progress, context_);
  }
}

auto PairingBridge::outcome_of(const Paired& result) -> PairingOutcome {
  if (result) {
    return PairingOutcome::paired(CoreSession::facts_of(*result.value()));
  }
  return PairingOutcome::failed(result.error());
}

auto PairingBridge::pair_at_home(const Request& request,
                                 const Bytes& account_id,
                                 const std::string& address,
                                 Generation generation, const char* pin,
                                 PairingProgressWatcher watcher, void* context)
    -> PairingOutcome {
  if (account_id.size() != libchiaking::psn_account_id_size) {
    return PairingOutcome::refused(PairingRefusal::unknown_user);
  }
  if (pin == nullptr) {
    return PairingOutcome::refused(PairingRefusal::invalid_pin);
  }
  return Boundary::fenced(
      PairingOutcome::refused(PairingRefusal::core_closed),
      [&]() -> PairingOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return PairingOutcome::refused(PairingRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return PairingOutcome::refused(PairingRefusal::unknown_user);
        }
        auto digits = PairingPin::parse(pin);
        if (!digits) {
          return PairingOutcome::refused(PairingRefusal::invalid_pin);
        }
        auto host = Host::create(address, generation);
        if (!host) {
          if (host.error() == Host::Invalid::ipv6_needs_ps5) {
            return PairingOutcome::failed(libchiaking::consoles::PairingFailure{
                libchiaking::consoles::PairingFailure::Reason::
                    address_not_for_generation});
          }
          return PairingOutcome::refused(PairingRefusal::invalid_address);
        }
        Steps steps{watcher, context};
        return outcome_of(opened->consoles().pair_at_home(
            *user, host.value(), generation, std::move(*digits),
            request.token(), &steps));
      });
}

auto PairingBridge::pair_over_internet(
    const Request& request, const Bytes& account_id, const Bytes& device_uid,
    const std::string& name, Generation generation,
    PairingProgressWatcher watcher, void* context) -> PairingOutcome {
  if (account_id.size() != libchiaking::psn_account_id_size) {
    return PairingOutcome::refused(PairingRefusal::unknown_user);
  }
  if (device_uid.size() != libchiaking::consoles::DeviceUid::size) {
    return PairingOutcome::refused(PairingRefusal::unknown_console);
  }
  return Boundary::fenced(
      PairingOutcome::refused(PairingRefusal::core_closed),
      [&]() -> PairingOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return PairingOutcome::refused(PairingRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return PairingOutcome::refused(PairingRefusal::unknown_user);
        }
        const auto device = ConsoleIds::device_of(device_uid.data());
        if (!device) {
          return PairingOutcome::refused(PairingRefusal::unknown_console);
        }
        auto console =
            generation == Generation::ps4 && device->is_main_ps4()
                ? std::optional<AccountConsole>{AccountConsole::main_ps4()}
                : AccountConsole::create(*device, name, generation, true);
        if (!console) {
          return PairingOutcome::refused(PairingRefusal::unknown_console);
        }
        Steps steps{watcher, context};
        return outcome_of(opened->consoles().pair_over_the_internet(
            *user, *console, &steps, request.token()));
      });
}

}  // namespace chiaki_bridge
