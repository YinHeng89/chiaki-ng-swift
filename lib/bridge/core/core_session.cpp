#include <libchiaking/version.hpp>
#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/core.hpp"
#include "console_ids.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

auto CoreSession::open(const std::string& catalog_directory,
                       CredentialStoreHandle credentials,
                       ConsoleStoreHandle consoles,
                       DatacenterStoreHandle datacenters,
                       DeviceStoreHandle devices) -> bool {
  if (catalog_directory.empty()) {
    return false;
  }
  return Boundary::fenced(false, [&] {
    return Opened::open(catalog_directory,
                        CoreStores{std::move(credentials), std::move(consoles),
                                   std::move(datacenters), std::move(devices)});
  });
}

auto CoreSession::is_open() -> bool {
  return Boundary::fenced(false, [] { return Opened::shared() != nullptr; });
}

void CoreSession::close() {
  Boundary::fenced(0, [] {
    Opened::close();
    return 0;
  });
}

auto CoreSession::version() -> VersionFacts {
  return Boundary::fenced(VersionFacts{}, [] {
    const auto current = libchiaking::Version::current();
    auto text = std::to_string(current.major_number()) + "." +
                std::to_string(current.minor_number()) + "." +
                std::to_string(current.patch_number());
    if (!current.prerelease().empty()) {
      text += "-";
      text += current.prerelease();
    }
    return VersionFacts{std::move(text), std::string{current.commit()}};
  });
}

auto CoreSession::remember_saved_consoles() -> RememberedConsoles {
  return Boundary::fenced(RememberedConsoles{false, 0, 0}, [] {
    RememberedConsoles result{false, 0, 0};
    const auto opened = Opened::shared();
    if (!opened) {
      return result;
    }
    const auto saved = opened->consoles().remember_saved();
    if (saved) {
      result.loaded = true;
      result.remembered = saved.value().consoles.size();
      result.rejected = saved.value().rejected;
    }
    return result;
  });
}

auto CoreSession::console(const Bytes& hardware_id)
    -> std::optional<ConsoleFacts> {
  if (hardware_id.size() != libchiaking::consoles::HardwareId::size) {
    return std::nullopt;
  }
  return Boundary::fenced(std::optional<ConsoleFacts>{},
                          [&]() -> std::optional<ConsoleFacts> {
                            const auto opened = Opened::shared();
                            if (!opened) {
                              return std::nullopt;
                            }
                            const auto found = opened->console(hardware_id);
                            if (!found) {
                              return std::nullopt;
                            }
                            return facts_of(*found);
                          });
}

auto CoreSession::facts_of(const libchiaking::consoles::Console& console)
    -> ConsoleFacts {
  ConsoleFacts facts{};
  facts.hardware_id = IdentifierBytes::of(console.hardware_id());
  facts.firmware = console.firmware().family();
  facts.name = console.name();
  facts.name_source = console.name_source();
  if (const auto address = console.last_address()) {
    facts.address = address->text();
  }
  facts.paired = console.is_paired();
  facts.generation = console.generation();
  facts.presence = console.presence();
  facts.saved = console.is_saved();
  if (const auto running = console.running_title()) {
    facts.running_title_id = running->title_id;
    facts.running_title_name = running->name;
  }
  return facts;
}

}  // namespace chiaki_bridge
