#include "opened.hpp"

#include <utility>

#include "boundary.hpp"
#include "console_ids.hpp"
#include "runtime.hpp"

namespace chiaki_bridge {

Opened::Opened(const std::string& catalog_directory, CoreStores stores)
    : directory_(catalog_directory),
      platform_(
          libchiaking::platform::HttpTransportSettings{
              .transport = libchiaking::platform::HttpTransport::multi},
          Runtime::process().threading(), Runtime::process().clock(),
          Runtime::process().wall_clock()),
      stores_(std::move(stores)),
      records_(directory_ + "/records"),
      idle_log_(platform_.threading(), platform_.clock(), 1) {
  auto opened = libchiaking::ChiakiNg::open(
      platform_.factory(),
      libchiaking::ChiakiNg::Stores{*stores_.credentials, *stores_.consoles,
                                    *stores_.datacenters, stores_.devices.get(),
                                    records_});
  if (opened) {
    chiaki_.emplace(std::move(opened.value()));
  }
}

auto Opened::kakusan() -> std::shared_ptr<libchiaking::kakusan::Kakusan> {
  auto shared = chiaki_->kakusan();
  if (!shared) {
    return nullptr;
  }
  return std::make_shared<libchiaking::kakusan::Kakusan>(
      std::move(shared.value()));
}

auto Opened::use_stun_servers(const std::vector<std::string>& stun_servers)
    -> bool {
  return chiaki_->use_stun_servers(stun_servers).has_value();
}

void Opened::stream_follows_log() {
  const std::lock_guard lock(log_mutex_);
  ++log_followers_;
  idle_log_.retain();
}

void Opened::stream_released_log() {
  const std::lock_guard lock(log_mutex_);
  if (log_followers_ > 0) {
    --log_followers_;
  }
}

auto Opened::read_idle_logs(std::size_t limit)
    -> std::vector<libchiaking::diagnostics::SessionJournal::Entry> {
  const std::lock_guard lock(log_mutex_);
  std::vector<libchiaking::diagnostics::SessionJournal::Entry> entries;
  const auto drain = [&] {
    while (entries.size() < limit) {
      auto entry = idle_log_.read();
      if (!entry) {
        return true;
      }
      entries.push_back(std::move(*entry));
    }
    return false;
  };
  if (log_followers_ == 0 && !idle_log_.following()) {
    if (!drain()) {
      return entries;
    }
    idle_log_.follow(platform_.log());
  }
  drain();
  return entries;
}

auto Opened::slot() -> std::shared_ptr<Opened>& {
  static auto* const held = new std::shared_ptr<Opened>;
  return *held;
}

auto Opened::guard() -> std::mutex& {
  static auto* const mutex = new std::mutex;
  return *mutex;
}

auto Opened::open(const std::string& catalog_directory, CoreStores stores)
    -> bool {
  const std::lock_guard lock(guard());
  if (slot() || !stores.credentials || !stores.consoles ||
      !stores.datacenters || !stores.devices) {
    return false;
  }
  auto opening = std::make_shared<Opened>(catalog_directory, std::move(stores));
  if (!opening->chiaki_) {
    return false;
  }
  slot() = std::move(opening);
  return true;
}

auto Opened::shared() -> std::shared_ptr<Opened> {
  const std::lock_guard lock(guard());
  return slot();
}

void Opened::close() {
  std::shared_ptr<Opened> closing;
  {
    const std::lock_guard lock(guard());
    closing = std::exchange(slot(), nullptr);
  }
}

auto Opened::user(const Bytes& account_id)
    -> std::shared_ptr<libchiaking::users::PsUser> {
  const auto account = AccountIds::account_of(account_id);
  return account ? users().find(*account) : nullptr;
}

auto Opened::console(const Bytes& hardware_id)
    -> std::shared_ptr<libchiaking::consoles::Console> {
  const auto id = ConsoleIds::hardware_of(hardware_id);
  return id ? consoles().find(*id) : nullptr;
}

}  // namespace chiaki_bridge
