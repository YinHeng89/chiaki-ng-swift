#pragma once

#include <cstddef>
#include <cstdint>
#include <libchiaking/consoles.hpp>
#include <libchiaking/kakusan.hpp>
#include <libchiaking/platform/platform.hpp>
#include <libchiaking/play.hpp>
#include <libchiaking/users.hpp>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace chiaki_bridge {

using ConsoleStoreHandle = std::shared_ptr<libchiaking::consoles::ConsoleStore>;
using CredentialStoreHandle =
    std::shared_ptr<libchiaking::users::CredentialStore>;
using DatacenterStoreHandle =
    std::shared_ptr<libchiaking::play::DatacenterStore>;
using DeviceStoreHandle = std::shared_ptr<libchiaking::kakusan::DeviceStore>;
using Bytes = std::vector<std::uint8_t>;
using Texts = std::vector<std::string>;

class Request {
 public:
  void cancel() const noexcept;
  auto cancelled() const noexcept -> bool;
  auto token() const noexcept -> libchiaking::platform::StopToken;

 private:
  mutable libchiaking::platform::StopSource source_;
};

struct ConsoleFacts {
  Bytes hardware_id;
  libchiaking::consoles::Firmware::Family firmware;
  std::string name;
  libchiaking::consoles::ConsoleName::Source name_source;
  std::optional<std::string> address;
  bool paired;
  libchiaking::consoles::Generation generation;
  libchiaking::consoles::Presence presence;
  bool saved;
  std::optional<std::string> running_title_id;
  std::optional<std::string> running_title_name;
};

using ConsoleList = std::vector<ConsoleFacts>;

struct CoreStores {
  CredentialStoreHandle credentials;
  ConsoleStoreHandle consoles;
  DatacenterStoreHandle datacenters;
  DeviceStoreHandle devices;
};

struct RememberedConsoles {
  bool loaded;
  std::size_t remembered;
  std::size_t rejected;
};

struct VersionFacts {
  std::string version;
  std::string commit;
};

class CoreSession {
 public:
  static auto open(const std::string& catalog_directory,
                   CredentialStoreHandle credentials,
                   ConsoleStoreHandle consoles,
                   DatacenterStoreHandle datacenters, DeviceStoreHandle devices)
      -> bool;
  static auto is_open() -> bool;
  static void close();
  static auto version() -> VersionFacts;
  static auto remember_saved_consoles() -> RememberedConsoles;
  static auto console(const Bytes& hardware_id) -> std::optional<ConsoleFacts>;
  static auto facts_of(const libchiaking::consoles::Console& console)
      -> ConsoleFacts;
};

}  // namespace chiaki_bridge
