#include <array>
#include <cassert>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <libchiaking/platform/platform.hpp>
#include <libchiaking/testing/in_memory_console_store.hpp>
#include <libchiaking/testing/in_memory_credential_store.hpp>
#include <libchiaking/testing/kakusan/in_memory_device_store.hpp>
#include <memory>
#include <string>
#include <string_view>
#include <utility>

#include "chiaki_bridge/core.hpp"
#include "chiaki_bridge/users.hpp"
#include "runtime.hpp"
#include "support/memory_datacenter_store.hpp"

namespace {

auto& native_test_threading = chiaki_bridge::Runtime::process().threading();
auto& native_test_clock = chiaki_bridge::Runtime::process().clock();

namespace users = libchiaking::users;
using chiaki_bridge::Bytes;
using chiaki_bridge::CredentialsBridge;
using chiaki_bridge::RevealRefusal;
using users::CredentialKind;
using users::HeldCredential;

class Household {
 public:
  static constexpr std::string_view seed = "Qz7seedWvKx1LmPdQz7seedWvKx1LmPd";
  static constexpr std::string_view remote_play =
      "Bw9rmteCsDq3ViKjBw9rmteCsDq3ViKj";
  static constexpr std::string_view remote_play_refresh =
      "Ex5rrfhNpLg0OuMzEx5rrfhNpLg0OuMz";
  static constexpr std::string_view device =
      "000000070041008012345678901234567890123456789012";
  static constexpr std::int64_t remote_play_expires_ms = 4'000'000'000'000;
  static constexpr std::string_view store_refresh =
      "Hy2srfhTcMb8KaWeHy2srfhTcMb8KaWe";
  static constexpr std::int64_t seed_obtained_ms = 1'760'000'000'123;
  static constexpr std::int64_t seed_expires_ms = 4'100'000'000'456;
  static constexpr std::int64_t remote_play_obtained_ms = 1'760'000'001'789;
  static constexpr std::int64_t renewal_obtained_ms = 1'760'000'002'001;
  static constexpr std::int64_t renewal_expires_ms = 4'200'000'000'002;
  static constexpr std::int64_t store_renewal_obtained_ms = 1'760'000'003'003;
  static constexpr std::int64_t store_renewal_lapsed_ms = 1'000'000'000'004;

  static auto moment(std::int64_t milliseconds)
      -> std::chrono::system_clock::time_point {
    return std::chrono::system_clock::time_point{
        std::chrono::duration_cast<std::chrono::system_clock::duration>(
            std::chrono::milliseconds{milliseconds})};
  }

  static auto undated() -> users::SavedSignIn {
    users::SavedSignIn saved{libchiaking::AccountId{5}, "player",
                             users::Npsso{seed}};
    saved.remote_play.emplace(users::BearerToken{remote_play},
                              moment(remote_play_expires_ms));
    saved.remote_play_refresh.emplace(
        users::RemotePlayRefreshToken{remote_play_refresh});
    saved.device = users::DeviceId::parse(device);
    assert(saved.device);
    return saved;
  }

  static auto dated() -> users::SavedSignIn {
    auto saved = undated();
    saved.npsso_obtained_at = moment(seed_obtained_ms);
    saved.npsso_expires_at = moment(seed_expires_ms);
    saved.remote_play->obtained_at = moment(remote_play_obtained_ms);
    saved.remote_play_refresh->obtained_at = moment(renewal_obtained_ms);
    saved.remote_play_refresh->expires_at = moment(renewal_expires_ms);
    saved.store_refresh.emplace(users::AppRefreshToken{store_refresh},
                                moment(store_renewal_obtained_ms),
                                moment(store_renewal_lapsed_ms));
    return saved;
  }

  static auto bytes(std::uint8_t first) -> Bytes {
    return Bytes{first, 0, 0, 0, 0, 0, 0, 0};
  }

  explicit Household(const users::SavedSignIn& saved = undated())
      : credentials_(
            std::make_shared<libchiaking::testing::InMemoryCredentialStore>(
                native_test_threading)),
        directory_(std::filesystem::temp_directory_path() /
                   "chiaki-users-bridge-test") {
    assert(credentials_->save(saved));
    assert(credentials_->save(
        users::SavedHomeUser{libchiaking::AccountId{6}, "guest"}));
    std::filesystem::remove_all(directory_);
    std::filesystem::create_directories(directory_);
    assert(chiaki_bridge::CoreSession::open(
        directory_.string(), credentials_,
        std::make_shared<libchiaking::testing::InMemoryConsoleStore>(
            native_test_threading),
        std::make_shared<chiaki_bridge_testing::MemoryDatacenterStore>(),
        std::make_shared<libchiaking::kakusan::testing::InMemoryDeviceStore>(
            native_test_threading)));
    const auto welcomed = chiaki_bridge::UsersBridge::welcome_back();
    assert(welcomed && welcomed->admitted == 2 && welcomed->rejected == 0);
  }

  Household(const Household&) = delete;
  auto operator=(const Household&) -> Household& = delete;

  ~Household() {
    chiaki_bridge::CoreSession::close();
    std::filesystem::remove_all(directory_);
  }

  static auto player() -> Bytes { return bytes(5); }

  static auto guest() -> Bytes { return bytes(6); }

 private:
  std::shared_ptr<libchiaking::testing::InMemoryCredentialStore> credentials_;
  std::filesystem::path directory_;
};

class Seen {
 public:
  static void secret(const char* secret, std::size_t size, void* sink) {
    auto& seen = *static_cast<Seen*>(sink);
    ++seen.reveals;
    seen.matched = std::string_view{secret, size} == seen.expected;
  }

  std::string_view expected;
  std::size_t reveals{};
  bool matched{};
};

class UsersBridgeFacts {
 public:
  static void saved_dates_cross_and_a_passed_expiry_reads_expired() {
    const Household home{Household::dated()};
    const auto held = CredentialsBridge::held_by(Household::player());
    assert(held && held->size() == users::every_credential.size());
    const auto& seed = (*held)[0];
    assert(seed.obtained_at_ms == Household::seed_obtained_ms);
    assert(seed.expires_at_ms == Household::seed_expires_ms);
    assert(seed.state != HeldCredential::State::expired);
    const auto& store_renewal = (*held)[2];
    assert(store_renewal.held && store_renewal.obtained_at_ms ==
                                     Household::store_renewal_obtained_ms);
    assert(store_renewal.expires_at_ms == Household::store_renewal_lapsed_ms);
    assert(store_renewal.state == HeldCredential::State::expired);
    const auto& remote_play = (*held)[3];
    assert(remote_play.obtained_at_ms == Household::remote_play_obtained_ms);
    const auto& renewal = (*held)[4];
    assert(renewal.held &&
           renewal.obtained_at_ms == Household::renewal_obtained_ms);
    assert(renewal.expires_at_ms == Household::renewal_expires_ms);
    assert(renewal.state != HeldCredential::State::expired);
  }

  static void every_credential_crosses_with_its_facts() {
    const Household home;
    const auto held = CredentialsBridge::held_by(Household::player());
    assert(held && held->size() == users::every_credential.size());
    for (std::size_t index = 0; index < held->size(); ++index) {
      const auto& facts = (*held)[index];
      assert(facts.kind == users::every_credential[index]);
      assert(!facts.used_for.empty());
    }
    const auto& seed = (*held)[0];
    assert(seed.held && seed.state == HeldCredential::State::unverified);
    assert(!seed.obtained_at_ms && !seed.expires_at_ms &&
           !seed.last_reply_status);
    const auto& app = (*held)[1];
    assert(!app.held && app.state == HeldCredential::State::never_obtained);
    const auto& remote_play = (*held)[3];
    assert(remote_play.held &&
           remote_play.state == HeldCredential::State::usable);
    assert(remote_play.expires_at_ms == Household::remote_play_expires_ms);
  }

  static void a_home_user_holds_nothing() {
    const Household home;
    const auto held = CredentialsBridge::held_by(Household::guest());
    assert(held && held->size() == users::every_credential.size());
    for (const auto& facts : *held) {
      assert(!facts.held && !facts.obtained_at_ms && !facts.expires_at_ms);
      assert(facts.state == HeldCredential::State::never_obtained);
    }
    for (const auto kind : users::every_credential) {
      Seen none;
      assert(CredentialsBridge::reveal(Household::guest(), kind, Seen::secret,
                                       &none) == RevealRefusal::signed_out);
      assert(none.reveals == 0);
    }
  }

  static void a_held_credential_is_handed_to_the_sink_once() {
    const Household home;
    const std::array<std::pair<CredentialKind, std::string_view>, 3> held{{
        {CredentialKind::sign_in_seed, Household::seed},
        {CredentialKind::remote_play_token, Household::remote_play},
        {CredentialKind::remote_play_refresh_token,
         Household::remote_play_refresh},
    }};
    for (const auto& [kind, secret] : held) {
      Seen seen;
      seen.expected = secret;
      assert(!CredentialsBridge::reveal(Household::player(), kind, Seen::secret,
                                        &seen));
      assert(seen.reveals == 1 && seen.matched);
    }
  }

  static void a_credential_that_is_not_held_reaches_no_sink() {
    const Household home;
    for (const auto kind :
         {CredentialKind::app_token, CredentialKind::app_refresh_token,
          CredentialKind::library_token,
          CredentialKind::old_service_checkout_token}) {
      Seen seen;
      assert(CredentialsBridge::reveal(Household::player(), kind, Seen::secret,
                                       &seen) == RevealRefusal::not_held);
      assert(seen.reveals == 0);
    }
  }

  static void an_account_that_is_not_eight_bytes_is_unknown() {
    const Household home;
    const Bytes short_account{5, 0, 0};
    assert(!CredentialsBridge::held_by(short_account));
    Seen seen;
    assert(CredentialsBridge::reveal(short_account,
                                     CredentialKind::sign_in_seed, Seen::secret,
                                     &seen) == RevealRefusal::unknown_user);
    assert(seen.reveals == 0);
    assert(!chiaki_bridge::UsersBridge::find(short_account));
    assert(chiaki_bridge::UsersBridge::find(Household::player()));
  }

  static void refusals_keep_their_meaning() {
    using Reason = users::NotRevealed::Reason;
    assert(CredentialsBridge::refusal_of(Reason::not_held) ==
           RevealRefusal::not_held);
    assert(CredentialsBridge::refusal_of(Reason::signed_out) ==
           RevealRefusal::signed_out);
  }

  static void a_closed_core_reveals_nothing() {
    Seen seen;
    assert(!CredentialsBridge::held_by(Household::player()));
    assert(CredentialsBridge::reveal(Household::player(),
                                     CredentialKind::sign_in_seed, Seen::secret,
                                     &seen) == RevealRefusal::core_closed);
    assert(CredentialsBridge::reveal(Household::player(),
                                     CredentialKind::sign_in_seed, nullptr,
                                     &seen) == RevealRefusal::unknown_user);
    assert(seen.reveals == 0);
  }
};

}  // namespace

int main() {
  UsersBridgeFacts::saved_dates_cross_and_a_passed_expiry_reads_expired();
  UsersBridgeFacts::every_credential_crosses_with_its_facts();
  UsersBridgeFacts::a_home_user_holds_nothing();
  UsersBridgeFacts::a_held_credential_is_handed_to_the_sink_once();
  UsersBridgeFacts::a_credential_that_is_not_held_reaches_no_sink();
  UsersBridgeFacts::an_account_that_is_not_eight_bytes_is_unknown();
  UsersBridgeFacts::refusals_keep_their_meaning();
  UsersBridgeFacts::a_closed_core_reveals_nothing();
  return 0;
}
