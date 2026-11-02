#pragma once

#include <cstddef>
#include <cstdint>
#include <libchiaking/chiaki_ng.hpp>
#include <libchiaking/consoles.hpp>
#include <libchiaking/kakusan.hpp>
#include <libchiaking/platform/stock_providers.hpp>
#include <libchiaking/play.hpp>
#include <libchiaking/play_types.hpp>
#include <libchiaking/users.hpp>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "account_ids.hpp"
#include "chiaki_bridge/core.hpp"

namespace chiaki_bridge {

class Opened {
 public:
  static auto open(const std::string& catalog_directory, CoreStores stores)
      -> bool;
  static auto shared() -> std::shared_ptr<Opened>;
  static void close();

  Opened(const std::string& catalog_directory, CoreStores stores);
  Opened(const Opened&) = delete;
  auto operator=(const Opened&) -> Opened& = delete;

  auto platform() noexcept -> libchiaking::platform::DefaultPlatform& {
    return platform_;
  }
  auto chiaki() noexcept -> libchiaking::ChiakiNg& { return *chiaki_; }
  auto users() noexcept -> libchiaking::users::SignedInUsers& {
    return chiaki_->users();
  }
  auto consoles() noexcept -> libchiaking::consoles::KnownConsoles& {
    return chiaki_->consoles();
  }
  auto catalog() noexcept -> libchiaking::catalog::Catalog& {
    return chiaki_->catalog();
  }
  auto play() noexcept -> libchiaking::play::Play& { return chiaki_->play(); }
  auto directory() const noexcept -> const std::string& { return directory_; }
  auto user(const Bytes& account_id)
      -> std::shared_ptr<libchiaking::users::PsUser>;
  auto console(const Bytes& hardware_id)
      -> std::shared_ptr<libchiaking::consoles::Console>;
  auto kakusan() -> std::shared_ptr<libchiaking::kakusan::Kakusan>;
  auto use_stun_servers(const std::vector<std::string>& stun_servers) -> bool;
  void stream_follows_log();
  void stream_released_log();
  auto read_idle_logs(std::size_t limit)
      -> std::vector<libchiaking::diagnostics::SessionJournal::Entry>;

 private:
  static auto slot() -> std::shared_ptr<Opened>&;
  static auto guard() -> std::mutex&;

  std::string directory_;
  libchiaking::platform::DefaultPlatform platform_;
  CoreStores stores_;
  libchiaking::platform::DefaultStorageProvider records_;
  std::optional<libchiaking::ChiakiNg> chiaki_;
  std::mutex log_mutex_;
  std::size_t log_followers_{};
  libchiaking::diagnostics::SessionJournal idle_log_;
};

}  // namespace chiaki_bridge
