#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <libchiaking/platform/platform.hpp>
#include <libchiaking/testing/in_memory_console_store.hpp>
#include <libchiaking/testing/in_memory_credential_store.hpp>
#include <libchiaking/testing/kakusan/in_memory_device_store.hpp>
#include <libchiaking/testing/play/scripted_link.hpp>
#include <memory>
#include <new>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

#include "chiaki_bridge/core.hpp"
#include "chiaki_bridge/users.hpp"
#include "runtime.hpp"
#include "stream_session.hpp"
#include "support/memory_datacenter_store.hpp"
#include "support/recording_listener.hpp"

namespace {

auto& native_test_threading = chiaki_bridge::Runtime::process().threading();
auto& native_test_clock = chiaki_bridge::Runtime::process().clock();

namespace play = libchiaking::play;
namespace controllers = libchiaking::controllers;

class HeapWatch {
 public:
  static constexpr std::size_t needle_size = 4;
  static constexpr std::size_t header_size = 2 * sizeof(std::size_t);

  static auto allocate(std::size_t size, std::size_t alignment) noexcept
      -> void* {
    const std::size_t pad = std::max(alignment, header_size);
    void* base = nullptr;
    if (posix_memalign(&base, pad, pad + size) != 0) {
      return nullptr;
    }
    auto* payload = static_cast<std::byte*>(base) + pad;
    std::memcpy(payload - header_size, &size, sizeof size);
    std::memcpy(payload - sizeof pad, &pad, sizeof pad);
    return payload;
  }

  static void release(void* block) noexcept {
    if (block == nullptr) {
      return;
    }
    auto* payload = static_cast<std::byte*>(block);
    std::size_t size = 0;
    std::size_t pad = 0;
    std::memcpy(&size, payload - header_size, sizeof size);
    std::memcpy(&pad, payload - sizeof pad, sizeof pad);
    if (watching_.load()) {
      for (const auto& needle : needles_) {
        if (memmem(payload, size, needle.data(), needle.size()) != nullptr) {
          ++residue_;
        }
      }
    }
    std::free(payload - pad);
  }

  static void watch(std::string_view first, std::string_view second) {
    assert(first.size() == needle_size && second.size() == needle_size);
    std::ranges::copy(first, needles_[0].begin());
    std::ranges::copy(second, needles_[1].begin());
    residue_ = 0;
    watching_ = true;
  }

  static void stop() noexcept { watching_ = false; }

  static auto residue() noexcept -> std::size_t { return residue_.load(); }

  static auto holds(const void* object, std::size_t size,
                    std::string_view needle) noexcept -> bool {
    return memmem(object, size, needle.data(), needle.size()) != nullptr;
  }

 private:
  static inline std::array<std::array<char, needle_size>, 2> needles_{};
  static inline std::atomic<bool> watching_{};
  static inline std::atomic<std::size_t> residue_{};
};

class Residue {
 public:
  static constexpr std::array<std::uint8_t, libchiaking::psn_account_id_size>
      signed_in_account{9, 0, 0, 0, 0, 0, 0, 2};
  static constexpr std::string_view sign_in_seed =
      "Qz7seedWvKx1LmPdQz7seedWvKx1LmPd";
  static constexpr std::string_view remote_play_refresh =
      "Ex5rrfhNpLg0OuMzEx5rrfhNpLg0OuMz";

  static void open_core(const std::string& directory) {
    using libchiaking::users::SavedSignIn;
    SavedSignIn saved{libchiaking::AccountId::from_bytes(
                          std::as_bytes(std::span{signed_in_account})),
                      "player", libchiaking::users::Npsso{sign_in_seed}};
    saved.remote_play_refresh.emplace(
        libchiaking::users::RemotePlayRefreshToken{remote_play_refresh});
    saved.device = libchiaking::users::DeviceId::parse(
        "000000070041008012345678901234567890123456789012");
    auto credentials =
        std::make_shared<libchiaking::testing::InMemoryCredentialStore>(
            native_test_threading);
    assert(credentials->save(saved));
    assert(chiaki_bridge::CoreSession::open(
        directory, std::move(credentials),
        std::make_shared<libchiaking::testing::InMemoryConsoleStore>(
            native_test_threading),
        std::make_shared<chiaki_bridge_testing::MemoryDatacenterStore>(),
        std::make_shared<libchiaking::kakusan::testing::InMemoryDeviceStore>(
            native_test_threading)));
  }

  static void the_probe_sees_a_secret_that_was_not_wiped() {
    HeapWatch::watch("5528", "8130");
    {
      const auto kept = std::make_unique<std::array<char, 64>>();
      std::memcpy(kept->data() + 20, "5528", HeapWatch::needle_size);
    }
    {
      const auto kept = std::make_unique<std::array<char, 64>>();
      std::memcpy(kept->data() + 20, "8130", HeapWatch::needle_size);
    }
    HeapWatch::stop();
    assert(HeapWatch::residue() == 2);
  }

  static void reveal(const char* secret, std::size_t size, void* sink) {
    auto& expected = *static_cast<std::string_view*>(sink);
    assert((std::string_view{secret, size} == expected));
    expected = {};
  }

  static void a_revealed_credential_leaves_nothing_behind() {
    const auto welcomed = chiaki_bridge::UsersBridge::welcome_back();
    assert(welcomed && welcomed->admitted == 1 && welcomed->rejected == 0);
    HeapWatch::watch("WvKx", "NpLg");
    using libchiaking::users::CredentialKind;
    const chiaki_bridge::Bytes account(signed_in_account.begin(),
                                       signed_in_account.end());
    for (const auto& [kind, secret] :
         {std::pair{CredentialKind::sign_in_seed, sign_in_seed},
          std::pair{CredentialKind::remote_play_refresh_token,
                    remote_play_refresh}}) {
      std::string_view expected = secret;
      assert(!chiaki_bridge::CredentialsBridge::reveal(
          account, kind, &Residue::reveal, &expected));
      assert(expected.empty());
    }
    chiaki_bridge::CoreSession::close();
    HeapWatch::stop();
    assert(HeapWatch::residue() == 0);
  }

  static void a_login_pin_and_a_seat_passcode_leave_nothing_behind() {
    const std::array<std::uint8_t, libchiaking::psn_account_id_size> account{
        4, 0, 0, 0, 0, 0, 0, 1};
    const chiaki_bridge::Bytes player(account.begin(), account.end());
    assert(chiaki_bridge::UsersBridge::add_home_user(player, "Player").kind() ==
           chiaki_bridge::HomeUserOutcome::Kind::added);
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.connect();
    link.ask_for_login_pin(false);
    chiaki_bridge_testing::RecordingListener heard;
    auto stream = std::make_unique<chiaki_bridge::StreamSession>(heard);
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{[&] { outcome = stream->run_scripted(player, link); }};
    while (!stream->session() ||
           stream->session()->state() != play::SessionState::playing) {
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
    HeapWatch::watch("4417", "9026");
    {
      const std::array<char, 4> pin{'4', '4', '1', '7'};
      assert(
          stream->submit_login_pin(std::string_view{pin.data(), pin.size()}));
    }
    while (link.count("login_pin") == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
    assert(stream->await_login_pin());
    assert(stream->add_couch_player(1, controllers::ControllerKind::dualsense,
                                    {}));
    while (link.count("seat_join") == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
    link.ask_for_passcode(controllers::SeatNumber::create(1).value(), false);
    while (stream->session()
               ->seats()
               .seat(controllers::SeatNumber::create(1).value())
               .state() != play::SeatState::entering_passcode) {
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
    {
      const std::array<char, 4> passcode{'9', '0', '2', '6'};
      assert(stream->submit_seat_passcode(
          1, std::string_view{passcode.data(), passcode.size()}));
    }
    while (link.count("seat_passcode") == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
    assert(link.login_pin().view() == "4417");
    assert(!HeapWatch::holds(stream.get(), sizeof(chiaki_bridge::StreamSession),
                             "4417"));
    assert(!HeapWatch::holds(stream.get(), sizeof(chiaki_bridge::StreamSession),
                             "9026"));
    link.finish();
    run.join();
    assert(outcome.ending().ending == play::Outcome::Ending::finished);
    stream.reset();
    chiaki_bridge::CoreSession::close();
    HeapWatch::stop();
    assert(HeapWatch::residue() == 0);
  }
};

}  // namespace

void* operator new(std::size_t size) {
  if (void* block = HeapWatch::allocate(size, alignof(std::max_align_t))) {
    return block;
  }
  throw std::bad_alloc{};
}

void* operator new[](std::size_t size) { return operator new(size); }

void* operator new(std::size_t size, const std::nothrow_t&) noexcept {
  return HeapWatch::allocate(size, alignof(std::max_align_t));
}

void* operator new[](std::size_t size, const std::nothrow_t&) noexcept {
  return HeapWatch::allocate(size, alignof(std::max_align_t));
}

void* operator new(std::size_t size, std::align_val_t alignment) {
  if (void* block =
          HeapWatch::allocate(size, static_cast<std::size_t>(alignment))) {
    return block;
  }
  throw std::bad_alloc{};
}

void* operator new[](std::size_t size, std::align_val_t alignment) {
  return operator new(size, alignment);
}

void operator delete(void* block) noexcept { HeapWatch::release(block); }

void operator delete[](void* block) noexcept { HeapWatch::release(block); }

void operator delete(void* block, std::size_t) noexcept {
  HeapWatch::release(block);
}

void operator delete[](void* block, std::size_t) noexcept {
  HeapWatch::release(block);
}

void operator delete(void* block, std::align_val_t) noexcept {
  HeapWatch::release(block);
}

void operator delete[](void* block, std::align_val_t) noexcept {
  HeapWatch::release(block);
}

void operator delete(void* block, std::size_t, std::align_val_t) noexcept {
  HeapWatch::release(block);
}

void operator delete[](void* block, std::size_t, std::align_val_t) noexcept {
  HeapWatch::release(block);
}

void operator delete(void* block, const std::nothrow_t&) noexcept {
  HeapWatch::release(block);
}

void operator delete[](void* block, const std::nothrow_t&) noexcept {
  HeapWatch::release(block);
}

int main() {
  Residue::the_probe_sees_a_secret_that_was_not_wiped();
  const auto directory =
      std::filesystem::temp_directory_path() / "chiaki-bridge-residue-test";
  std::filesystem::remove_all(directory);
  std::filesystem::create_directories(directory);
  Residue::open_core(directory.string());
  Residue::a_login_pin_and_a_seat_passcode_leave_nothing_behind();
  Residue::open_core(directory.string());
  Residue::a_revealed_credential_leaves_nothing_behind();
  std::filesystem::remove_all(directory);
  return 0;
}
