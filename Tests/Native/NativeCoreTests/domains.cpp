#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <libchiaking/platform/platform.hpp>
#include <libchiaking/testing/in_memory_console_store.hpp>
#include <libchiaking/testing/in_memory_credential_store.hpp>
#include <libchiaking/testing/kakusan/in_memory_device_store.hpp>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <vector>

#include "chiaki_bridge/catalog.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "chiaki_bridge/core.hpp"
#include "chiaki_bridge/kakusan.hpp"
#include "chiaki_bridge/play.hpp"
#include "chiaki_bridge/stream.hpp"
#include "chiaki_bridge/users.hpp"
#include "support/memory_datacenter_store.hpp"
#include "support/recording_listener.hpp"

namespace {

auto& native_test_threading =
    *new libchiaking::platform::DefaultThreadingProvider;
auto& native_test_clock = *new libchiaking::platform::SteadyClock;

auto account_of(
    const std::array<std::uint8_t, libchiaking::psn_account_id_size>& bytes)
    -> libchiaking::AccountId {
  return libchiaking::AccountId::from_bytes(std::as_bytes(std::span{bytes}));
}

auto hardware_of(
    const std::array<std::uint8_t, libchiaking::consoles::HardwareId::size>&
        bytes) -> libchiaking::consoles::HardwareId {
  return *libchiaking::consoles::HardwareId::from_bytes(
      std::as_bytes(std::span{bytes}));
}

auto seeded_consoles(
    const std::array<std::uint8_t, libchiaking::psn_account_id_size>& account,
    const std::array<std::uint8_t, libchiaking::consoles::HardwareId::size>&
        hardware)
    -> std::shared_ptr<libchiaking::testing::InMemoryConsoleStore> {
  using libchiaking::consoles::ConsoleName;
  using libchiaking::consoles::Firmware;
  auto consoles = std::make_shared<libchiaking::testing::InMemoryConsoleStore>(
      native_test_threading);
  consoles->seed(libchiaking::consoles::SavedConsole{
      hardware_of(hardware), Firmware{Firmware::Family::ps5_1},
      *ConsoleName::create("Den", ConsoleName::Source::pairing), std::nullopt});
  std::array<std::byte, 16> registration{};
  std::array<std::byte, 16> remote_play{};
  registration.fill(std::byte{0x31});
  remote_play.fill(std::byte{0x5a});
  consoles->seed(libchiaking::consoles::SavedPairing{
      libchiaking::AccountId::from_bytes(std::as_bytes(std::span{account})),
      hardware_of(hardware),
      *libchiaking::consoles::PairingKeys::create(registration, remote_play, 2),
      std::nullopt});
  return consoles;
}

auto sitting(chiaki_bridge::StreamListener& listener)
    -> std::unique_ptr<chiaki_bridge::Stream> {
  auto stream = chiaki_bridge::Stream::open(listener);
  assert(stream);
  return stream;
}

}  // namespace

int main() {
  const std::array<std::uint8_t, libchiaking::psn_account_id_size> account{
      1, 2, 3, 4, 5, 6, 7, 8};
  const std::array<std::uint8_t, libchiaking::psn_account_id_size> stranger{
      9, 9, 9, 9, 9, 9, 9, 9};
  const std::array<std::uint8_t, libchiaking::consoles::HardwareId::size>
      hardware{0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff};
  const std::array<std::uint8_t, libchiaking::consoles::HardwareId::size>
      absent{1, 1, 1, 1, 1, 1};
  auto credentials =
      std::make_shared<libchiaking::testing::InMemoryCredentialStore>(
          native_test_threading);
  assert(credentials->save(
      libchiaking::users::SavedHomeUser{account_of(account), "Living room"}));
  const auto consoles = seeded_consoles(account, hardware);
  auto datacenters =
      std::make_shared<chiaki_bridge_testing::MemoryDatacenterStore>();
  using libchiaking::play::DatacenterMeasurement;
  const std::array measured{*DatacenterMeasurement::create(
      *libchiaking::play::DatacenterName::parse("frankfurt"),
      DatacenterMeasurement::RoundTrip{24},
      DatacenterMeasurement::Time{
          std::chrono::milliseconds{1'700'000'000'000}})};
  assert(datacenters->save(libchiaking::catalog::ServiceGeneration::old_service,
                           measured));
  assert(datacenters->save(libchiaking::catalog::ServiceGeneration::ps5_cloud,
                           measured));
  auto devices =
      std::make_shared<libchiaking::kakusan::testing::InMemoryDeviceStore>(
          native_test_threading);

  using chiaki_bridge::UsersBridge;
  using chiaki_bridge::UsersRefusal;
  using libchiaking::consoles::Generation;
  const chiaki_bridge::Bytes known_account(account.begin(), account.end());
  const chiaki_bridge::Bytes stranger_account(stranger.begin(), stranger.end());
  const chiaki_bridge::Bytes short_account(account.begin(), account.end() - 1);
  assert(!chiaki_bridge::CoreSession::is_open());
  assert(!UsersBridge::find(known_account));
  assert(!UsersBridge::welcome_back());

  const auto directory =
      std::filesystem::temp_directory_path() / "chiaki-bridge-domains-test";
  std::filesystem::remove_all(directory);
  std::filesystem::create_directories(directory);
  const std::string catalog_directory = directory.string();
  assert(chiaki_bridge::CoreSession::open(catalog_directory, credentials,
                                          consoles, datacenters, devices));
  assert(chiaki_bridge::CoreSession::is_open());
  assert(!chiaki_bridge::CoreSession::open(catalog_directory, credentials,
                                           consoles, datacenters, devices));

  const auto welcomed = UsersBridge::welcome_back();
  assert(welcomed && welcomed->admitted == 1 && welcomed->rejected == 0);
  const auto living_room = UsersBridge::find(known_account);
  assert(living_room && living_room->online_id == "Living room");
  assert(living_room->account_id == known_account);
  assert(!living_room->has_psn_account);
  assert(living_room->sign_in_state ==
         libchiaking::users::SignInState::signed_out);
  assert(!living_room->tier);
  assert(!UsersBridge::find(stranger_account));
  assert(!UsersBridge::find(short_account));
  const auto short_added = UsersBridge::add_home_user(short_account, "Guest");
  assert(short_added.kind() == chiaki_bridge::HomeUserOutcome::Kind::refused &&
         short_added.refusal() == UsersRefusal::unknown_user);
  assert(UsersBridge::add_home_user(stranger_account, "Guest").kind() ==
         chiaki_bridge::HomeUserOutcome::Kind::added);
  assert(credentials->saved_home_user(account_of(account)) &&
         credentials->saved_home_user(account_of(stranger)));
  assert(UsersBridge::everyone().size() == 2);
  const chiaki_bridge::Request unhurried;
  const auto refreshed = UsersBridge::refresh(unhurried, stranger_account);
  assert(refreshed.kind() == chiaki_bridge::RefreshOutcome::Kind::unanswered &&
         refreshed.why_unanswered().reason ==
             libchiaking::users::Unanswered::Reason::signed_out);
  const auto short_refreshed = UsersBridge::refresh(unhurried, short_account);
  assert(short_refreshed.kind() ==
             chiaki_bridge::RefreshOutcome::Kind::refused &&
         short_refreshed.refusal() == UsersRefusal::unknown_user);
  assert(!UsersBridge::sign_out(stranger_account));
  assert(UsersBridge::sign_out(short_account) == UsersRefusal::unknown_user);
  assert(credentials->saved_home_user(account_of(account)) &&
         !credentials->saved_home_user(account_of(stranger)));
  assert(!UsersBridge::find(stranger_account));

  using chiaki_bridge::ConsolesBridge;
  using chiaki_bridge::ConsolesRefusal;
  using libchiaking::consoles::Route;
  const chiaki_bridge::Bytes den(hardware.begin(), hardware.end());
  const chiaki_bridge::Bytes nowhere_console(absent.begin(), absent.end());
  const auto saved = chiaki_bridge::CoreSession::remember_saved_consoles();
  assert(saved.loaded && saved.remembered == 1 && saved.rejected == 0);
  const auto console = chiaki_bridge::CoreSession::console(den);
  assert(console && console->saved && console->paired);
  assert(console->generation == Generation::ps5);
  assert(console->name == "Den");
  assert(console->firmware == libchiaking::consoles::Firmware::Family::ps5_1);
  assert(console->presence == libchiaking::consoles::Presence::unknown);
  assert(ConsolesBridge::paired_with(den, known_account));
  assert(!ConsolesBridge::paired_with(den, stranger_account));
  assert(!chiaki_bridge::CoreSession::console(nowhere_console));
  assert(ConsolesBridge::everything().size() == 1);

  const auto renaming = ConsolesBridge::rename(den, "Basement");
  assert(renaming.kind() == chiaki_bridge::ChangeOutcome::Kind::changed);
  assert(consoles->console_saves == 1);
  assert(consoles->console(hardware_of(hardware))->name.text() == "Basement");
  assert(consoles->console(hardware_of(hardware))->name.source() ==
         libchiaking::consoles::ConsoleName::Source::renamed);
  assert(ConsolesBridge::rename(nowhere_console, "Nowhere").refusal() ==
         ConsolesRefusal::unknown_console);
  assert(ConsolesBridge::moved_to(den, "").refusal() ==
         ConsolesRefusal::invalid_address);
  const auto unaddressed =
      ConsolesBridge::wake(unhurried, known_account, den, false);
  assert(unaddressed.kind() == chiaki_bridge::WakeOutcome::Kind::declined &&
         unaddressed.decline() ==
             libchiaking::consoles::WakeRefusal::no_address);
  assert(ConsolesBridge::route(unhurried, known_account, den) == Route::home);
  assert(!ConsolesBridge::route(unhurried, stranger_account, den));
  assert(!ConsolesBridge::route(unhurried, known_account, nowhere_console));
  assert(!ConsolesBridge::route(unhurried, short_account, den));
  const auto unwelcome =
      ConsolesBridge::wake(unhurried, stranger_account, den, false);
  assert(unwelcome.kind() == chiaki_bridge::WakeOutcome::Kind::refused &&
         unwelcome.refusal() == ConsolesRefusal::unknown_user);
  assert(ConsolesBridge::unpair(short_account, den) ==
         ConsolesRefusal::unknown_user);

  using chiaki_bridge::DiscoveryBridge;
  const auto valid = DiscoveryBridge::ranges({"192.168.1.0/24"}, true);
  assert(valid.kind() == chiaki_bridge::SearchOutcome::Kind::covered &&
         valid.targets() > 0);
  const auto unreadable = DiscoveryBridge::ranges({"not a subnet"}, true);
  assert(unreadable.kind() == chiaki_bridge::SearchOutcome::Kind::invalid &&
         unreadable.why_invalid() ==
             libchiaking::consoles::SearchRanges::Invalid::subnet);

  using chiaki_bridge::PairingBridge;
  using chiaki_bridge::PairingRefusal;
  const auto unpaired =
      PairingBridge::pair_at_home(unhurried, known_account, "192.168.1.9",
                                  Generation::ps5, "1234", nullptr, nullptr);
  assert(unpaired.refusal() == PairingRefusal::invalid_pin);
  const auto unknown = PairingBridge::pair_at_home(
      unhurried, stranger_account, "192.168.1.9", Generation::ps5, "12345678",
      nullptr, nullptr);
  assert(unknown.refusal() == PairingRefusal::unknown_user);
  const auto misaddressed = PairingBridge::pair_at_home(
      unhurried, known_account, "not an address", Generation::ps5, "12345678",
      nullptr, nullptr);
  assert(misaddressed.refusal() == PairingRefusal::invalid_address);
  const chiaki_bridge::Request abandoned;
  abandoned.cancel();
  const auto cancelled = PairingBridge::pair_at_home(
      abandoned, known_account, "127.0.0.1", Generation::ps5, "12345678",
      nullptr, nullptr);
  assert(cancelled.kind() == chiaki_bridge::PairingOutcome::Kind::failed &&
         cancelled.failure().reason ==
             libchiaking::consoles::PairingFailure::Reason::cancelled);

  using chiaki_bridge::StreamRefusal;
  using libchiaking::consoles::Route;
  using StartKind = libchiaking::play::StartRefusal::Kind;
  const chiaki_bridge::Bytes player(account.begin(), account.end());
  const chiaki_bridge::Bytes outsider(stranger.begin(), stranger.end());
  const chiaki_bridge::Bytes nowhere(absent.begin(), absent.end());
  chiaki_bridge_testing::RecordingListener viewer;
  chiaki_bridge_testing::RecordingListener blind;
  blind.refuse_video();
  {
    auto stream = sitting(viewer);
    const auto refused = stream->run_console(outsider, den, Route::home);
    assert(refused.kind() == chiaki_bridge::StreamOutcome::Kind::refused &&
           refused.refusal() == StreamRefusal::unknown_user);
    const auto again = stream->run_console(player, den, Route::home);
    assert(again.kind() == chiaki_bridge::StreamOutcome::Kind::unrecorded);
  }
  {
    auto stream = sitting(viewer);
    assert(stream->run_console(player, nowhere, Route::home).refusal() ==
           StreamRefusal::unknown_console);
  }
  {
    auto stream = sitting(blind);
    assert(stream->run_console(player, den, Route::home).refusal() ==
           StreamRefusal::no_decoder);
  }
  {
    auto stream = sitting(viewer);
    assert(
        stream->set_picture({.height = 1080,
                             .fps = 60,
                             .bitrate_kbps = 15000,
                             .codec = libchiaking::media::VideoCodec::h265}));
    const auto refused = stream->run_console(player, den, Route::home);
    assert(refused.start_refusal().kind == StartKind::console_unreachable);
    assert(refused.start_refusal().unreachable ==
           libchiaking::consoles::Unreachable::no_address);
  }
  {
    auto stream = sitting(viewer);
    assert(stream->run_console(player, den, Route::internet)
               .start_refusal()
               .kind == StartKind::needs_psn_sign_in);
  }
  {
    auto stream = sitting(viewer);
    assert(stream->run_cloud(player, {}).refusal() ==
           StreamRefusal::invalid_title);
  }
  {
    auto stream = sitting(viewer);
    const auto refused = stream->run_cloud(
        player, {.product_id = "EP9000-PPSA01968_00-DEATHSTRANDINGEU"});
    assert(refused.start_refusal().kind == StartKind::needs_psn_sign_in);
    stream->cancel();
    assert(!stream->go_home());
    assert(!stream->choose_datacenter("Auto"));
  }

  using chiaki_bridge::PlayBridge;
  using chiaki_bridge::StreamTarget;
  using libchiaking::catalog::ServiceGeneration;
  const auto datacenters_known =
      PlayBridge::known_datacenters(ServiceGeneration::ps5_cloud);
  assert(datacenters_known.size() == 1 &&
         datacenters_known.front().name == "frankfurt");
  assert(PlayBridge::forget_datacenters(ServiceGeneration::ps5_cloud));
  assert(datacenters->held(libchiaking::catalog::ServiceGeneration::ps5_cloud)
             .empty());

  assert(PlayBridge::supports_audio_channels(StreamTarget::local_ps5, 6));
  assert(!PlayBridge::supports_audio_channels(StreamTarget::local_ps4, 6));
  assert(PlayBridge::supports_audio_channels(StreamTarget::local_ps4, 2));
  assert(PlayBridge::supports_audio_channels(StreamTarget::ps_cloud, 8));
  assert(!PlayBridge::supports_audio_channels(StreamTarget::local_ps5, 5));
  assert(PlayBridge::supports_audio_3d(StreamTarget::local_ps5));
  assert(PlayBridge::supports_audio_3d(StreamTarget::ps_cloud));
  assert(!PlayBridge::supports_audio_3d(StreamTarget::local_ps4));
  assert(!PlayBridge::supports_audio_3d(StreamTarget::ps_now));

#if CHIAKI_KAKUSAN
  using chiaki_bridge::KakusanDevices;
  using chiaki_bridge::KakusanRefusal;
  using RecognitionKind = libchiaking::kakusan::Recognition::Kind;
  using RememberKind = libchiaking::kakusan::RememberRefusal::Kind;
  assert(!devices->identity());
  libchiaking::kakusan::IdentityKey::Bytes seeded{};
  seeded.fill(std::byte{1});
  assert(devices->save(libchiaking::kakusan::SavedDevice{
      libchiaking::kakusan::IdentityKey{seeded}, "Alex",
      std::chrono::system_clock::time_point{std::chrono::milliseconds{1000}},
      std::chrono::system_clock::time_point{std::chrono::milliseconds{2000}}}));
  const auto identified = KakusanDevices::this_device();
  assert(identified.kind() ==
         chiaki_bridge::ThisDeviceOutcome::Kind::identified);
  const chiaki_bridge::Bytes key = identified.device().identity;
  assert(key.size() == libchiaking::kakusan::IdentityKey::size &&
         identified.device().fingerprint.size() ==
             libchiaking::kakusan::Fingerprint::size);
  assert(devices->identity() && devices->identity_saves() == 1);
  assert(
      std::ranges::any_of(devices->identity()->fingerprint.bytes(),
                          [](std::byte byte) { return byte != std::byte{}; }));
  assert(std::ranges::any_of(key, [](std::uint8_t byte) { return byte != 0; }));
  assert(KakusanDevices::this_device().device().identity == key &&
         devices->identity_saves() == 1);
  const auto listed = KakusanDevices::remembered();
  assert(listed.kind() == chiaki_bridge::RememberedOutcome::Kind::listed &&
         listed.devices().size() == 1);
  const chiaki_bridge::Bytes alex(libchiaking::kakusan::IdentityKey::size, 1);
  const chiaki_bridge::Bytes unfamiliar(libchiaking::kakusan::IdentityKey::size,
                                        9);
  auto known = KakusanDevices::recognise(alex);
  assert(known.kind == RecognitionKind::recognised && known.device);
  assert(known.device->nickname == "Alex" &&
         known.device->first_verified_ms == 1000 &&
         known.device->last_seen_ms == 2000);
  assert(std::ranges::any_of(known.device->fingerprint,
                             [](std::uint8_t byte) { return byte != 0; }));
  assert(KakusanDevices::recognise(unfamiliar).kind ==
         RecognitionKind::unknown);
  known = KakusanDevices::recognise(unfamiliar, "alex");
  assert(known.kind == RecognitionKind::changed_key && known.device &&
         known.device->identity == alex);
  assert(KakusanDevices::recognise(alex, "ALEX").kind ==
         RecognitionKind::recognised);
  assert(KakusanDevices::recognise(unfamiliar, "Sam").kind ==
         RecognitionKind::unknown);
  assert(KakusanDevices::recognise(chiaki_bridge::Bytes{1, 2}).kind ==
         RecognitionKind::unknown);
  assert(KakusanDevices::normalised_nickname("  Sam  ") == "Sam");
  assert(!KakusanDevices::normalised_nickname("   "));
  assert(!KakusanDevices::normalised_nickname(std::string(41, 'a')));
  assert(!KakusanDevices::normalised_nickname("A\a"));
  using RememberCase = chiaki_bridge::RememberOutcome::Kind;
  const auto renamed_self = KakusanDevices::rename(key, "Sam");
  assert(renamed_self.kind() == RememberCase::declined &&
         renamed_self.decline().kind == RememberKind::unknown_device);
  const auto renamed_short =
      KakusanDevices::rename(chiaki_bridge::Bytes{1}, "Sam");
  assert(renamed_short.kind() == RememberCase::refused &&
         renamed_short.refusal() == KakusanRefusal::invalid_identity);
  const auto renamed_alex = KakusanDevices::rename(alex, " Lex ");
  assert(renamed_alex.kind() == RememberCase::remembered &&
         renamed_alex.device().nickname == "Lex" &&
         devices->devices().back().nickname == "Lex");
  const auto renamed_badly = KakusanDevices::rename(alex, "\a");
  assert(renamed_badly.kind() == RememberCase::declined &&
         renamed_badly.decline().kind == RememberKind::invalid_nickname);
  assert(KakusanDevices::forget(alex) && devices->devices().empty());
  assert(!KakusanDevices::forget(chiaki_bridge::Bytes{}));
  assert(KakusanDevices::recognise(alex).kind == RecognitionKind::unknown);
  const auto previewed =
      KakusanDevices::preview_invitation("not an invitation");
  assert(previewed.kind() == chiaki_bridge::PreviewOutcome::Kind::declined &&
         previewed.decline() ==
             libchiaking::kakusan::Refusal::Kind::invalid_text);
  const auto previewed_nothing = KakusanDevices::preview_invitation("");
  assert(previewed_nothing.kind() ==
             chiaki_bridge::PreviewOutcome::Kind::refused &&
         previewed_nothing.refusal() == KakusanRefusal::invalid_text);
  {
    using RefusalKind = libchiaking::kakusan::Refusal::Kind;
    auto stream = sitting(viewer);
    using CommandKind = chiaki_bridge::KakusanCommandOutcome::Kind;
    assert(stream->invite_guest().refusal() ==
           chiaki_bridge::KakusanCommandRefusal::not_armed);
    assert(stream->arm_kakusan({.capacity = 5, .local_seats = 1}).decline() ==
           RefusalKind::invalid_argument);
    const auto armed = stream->arm_kakusan({.capacity = 2, .local_seats = 1});
    assert(armed.kind() == CommandKind::accepted);
    assert(stream->invite_guest().decline() == RefusalKind::not_sharing);
    const auto widened = stream->set_capacity(3);
    assert(widened.kind() == CommandKind::accepted);
    assert(stream->set_local_seats(4).decline() ==
           RefusalKind::invalid_argument);
    assert(stream->remember_device(key, "Sam", false).decline().kind ==
           RememberKind::unknown_device);
    assert(KakusanDevices::recognise(key).kind == RecognitionKind::unknown);
  }
#endif

  const std::array<std::uint8_t, libchiaking::psn_account_id_size> nobody{
      7, 7, 7, 7, 7, 7, 7, 7};
  using chiaki_bridge::CatalogBridge;
  using chiaki_bridge::CatalogRefusal;
  using chiaki_bridge::TitleChecksBridge;
  const chiaki_bridge::Bytes nobody_account(nobody.begin(), nobody.end());
  const std::string title = "EP9000-PPSA01234_00-0000000000000000";
  assert(CatalogBridge::my_games(unhurried, nobody_account, false, nullptr,
                                 nullptr)
             .refusal() == CatalogRefusal::unknown_user);
  assert(CatalogBridge::recheck_ownership(unhurried, nobody_account, title)
             .refusal() == CatalogRefusal::unknown_user);
  assert(CatalogBridge::recheck_ownership(unhurried, known_account, "")
             .refusal() == CatalogRefusal::invalid_product);
  assert(
      TitleChecksBridge::storefront(unhurried, known_account, "").refusal() ==
      CatalogRefusal::invalid_product);
  assert(
      TitleChecksBridge::store_page(unhurried, known_account, "").refusal() ==
      CatalogRefusal::invalid_product);
  assert(!CatalogBridge::explain(nobody_account, title));
  assert(!CatalogBridge::explain(known_account, ""));
  const auto explained = CatalogBridge::explain(known_account, title);
  assert(explained && !explained->listed);
  assert(CatalogBridge::cloud_access(unhurried, nobody_account).refusal() ==
         CatalogRefusal::unknown_user);
  assert(TitleChecksBridge::details_by_concept(unhurried, known_account,
                                               "not a concept")
             .refusal() == CatalogRefusal::invalid_concept);
  std::vector<libchiaking::catalog::LaunchCheck> checks;
  const auto note_check = [](libchiaking::catalog::LaunchCheck check,
                             void* sink) {
    static_cast<std::vector<libchiaking::catalog::LaunchCheck>*>(sink)
        ->push_back(check);
  };
  const auto stranger_cleared = TitleChecksBridge::clear_for_launch(
      unhurried, nobody_account, title, note_check, &checks);
  assert(stranger_cleared.refusal() == CatalogRefusal::unknown_user &&
         checks.empty());
  assert(TitleChecksBridge::clear_for_launch(unhurried, known_account, "",
                                             note_check, &checks)
             .refusal() == CatalogRefusal::invalid_product);
  const auto unchecked = TitleChecksBridge::clear_for_launch(
      unhurried, known_account, title, note_check, &checks);
  assert(!checks.empty() &&
         checks.front() == libchiaking::catalog::LaunchCheck::loading_library);
  assert(unchecked.kind() == chiaki_bridge::ClearanceOutcome::Kind::declined &&
         unchecked.decline().kind ==
             libchiaking::catalog::LaunchRefusal::Kind::check_unavailable);
  TitleChecksBridge::release(nullptr);
  assert(UsersBridge::sign_in_again(
             unhurried, nobody_account, "npsso", std::nullopt,
             "000000070041008012345678901234567890123456789012", "c")
             .refusal() == UsersRefusal::unknown_user);
  assert(UsersBridge::sign_in(unhurried, "npsso", std::nullopt, "not a device",
                              "c")
             .refusal() == UsersRefusal::invalid_device);

  assert(!ConsolesBridge::forget(den));
  assert(consoles->removals == 1 && consoles->console_count() == 0);
  assert(!chiaki_bridge::CoreSession::console(den));
  assert(ConsolesBridge::forget(den) == ConsolesRefusal::unknown_console);

  chiaki_bridge::CoreSession::close();
  assert(!chiaki_bridge::CoreSession::is_open());
  assert(UsersBridge::sign_in(unhurried, "npsso", std::nullopt, "", "c")
             .refusal() == UsersRefusal::core_closed);
  assert(UsersBridge::sign_out(known_account) == UsersRefusal::core_closed);
  assert(
      CatalogBridge::my_games(unhurried, known_account, false, nullptr, nullptr)
          .refusal() == CatalogRefusal::core_closed);
  assert(TitleChecksBridge::clear_for_launch(unhurried, known_account, title,
                                             note_check, &checks)
             .refusal() == CatalogRefusal::core_closed);
  std::filesystem::remove_all(directory);
  return 0;
}
