#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <libchiaking/platform/platform.hpp>
#include <libchiaking/play.hpp>
#include <libchiaking/testing/in_memory_console_store.hpp>
#include <libchiaking/testing/in_memory_credential_store.hpp>
#include <libchiaking/testing/kakusan/in_memory_device_store.hpp>
#include <libchiaking/testing/play/scripted_link.hpp>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "chiaki_bridge/consoles.hpp"
#include "chiaki_bridge/core.hpp"
#include "chiaki_bridge/play.hpp"
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
namespace media = libchiaking::media;
namespace kakusan = libchiaking::kakusan;

using chiaki_bridge::KakusanEvent;
using chiaki_bridge_testing::RecordingListener;
using Ending = play::Outcome::Ending;
using Heard = RecordingListener::Heard;

using AccountBytes = std::array<std::uint8_t, libchiaking::psn_account_id_size>;

class Shelf {
 public:
  static auto one_sign_in()
      -> std::shared_ptr<libchiaking::testing::InMemoryCredentialStore> {
    using libchiaking::users::SavedSignIn;
    const AccountBytes account{6, 0, 0, 0, 0, 0, 0, 2};
    SavedSignIn saved{
        libchiaking::AccountId::from_bytes(std::as_bytes(std::span{account})),
        "Signed", libchiaking::users::Npsso{"synthetic-npsso"}};
    const SavedSignIn::Time expiry{std::chrono::milliseconds{4102444800000}};
    saved.store.emplace(libchiaking::users::AppToken{"synthetic-store-token"},
                        expiry);
    saved.store_refresh.emplace(
        libchiaking::users::AppRefreshToken{"synthetic-store-refresh"});
    saved.remote_play.emplace(
        libchiaking::users::BearerToken{"synthetic-remote-play-token"}, expiry);
    saved.remote_play_refresh.emplace(
        libchiaking::users::RemotePlayRefreshToken{
            "synthetic-remote-play-refresh"});
    saved.region = libchiaking::users::Region{"GB", "en"};
    auto store =
        std::make_shared<libchiaking::testing::InMemoryCredentialStore>(
            native_test_threading);
    assert(store->save(saved));
    return store;
  }
  static constexpr std::array<std::uint8_t,
                              libchiaking::consoles::HardwareId::size>
      away{0xa0, 0xb1, 0xc2, 0xd3, 0xe4, 0xf5};

  static auto one_console_away()
      -> std::shared_ptr<libchiaking::testing::InMemoryConsoleStore> {
    using libchiaking::consoles::ConsoleName;
    using libchiaking::consoles::Firmware;
    using libchiaking::consoles::HardwareId;
    const auto hardware =
        *HardwareId::from_bytes(std::as_bytes(std::span{away}));
    auto consoles =
        std::make_shared<libchiaking::testing::InMemoryConsoleStore>(
            native_test_threading);
    consoles->seed(libchiaking::consoles::SavedConsole{
        hardware, Firmware{Firmware::Family::ps5_1},
        *ConsoleName::create("Away", ConsoleName::Source::pairing),
        std::nullopt});
    const AccountBytes account{6, 0, 0, 0, 0, 0, 0, 2};
    std::array<std::byte, 16> registration{};
    std::array<std::byte, 16> remote_play{};
    registration.fill(std::byte{0x31});
    remote_play.fill(std::byte{0x5a});
    consoles->seed(libchiaking::consoles::SavedPairing{
        libchiaking::AccountId::from_bytes(std::as_bytes(std::span{account})),
        hardware,
        *libchiaking::consoles::PairingKeys::create(registration, remote_play,
                                                    2),
        std::nullopt});
    return consoles;
  }
};

class Audience final : public play::SharedAudience {
 public:
  void stream_started(const play::SharedStream&, play::ReceiveKeys) override {}
  void encrypted_datagram(const play::SharedDatagram&) noexcept override {}
  void feedback(const controllers::ControllerFeedback& feedback) override {
    const std::lock_guard lock(mutex_);
    seats_.push_back(feedback.seat);
  }
  void guest_seated(controllers::SeatNumber) override { seated_ = true; }
  void guest_seat_refused(const play::SeatRefusal&) override {}
  void guest_unseated(controllers::SeatNumber) override {}
  void became_unshareable(play::NotShareable) override {}
  auto service(std::chrono::milliseconds wait)
      -> std::chrono::milliseconds override {
    return wait;
  }
  void session_ended() override {}

  auto seated() const noexcept -> bool { return seated_; }

  auto heard(controllers::SeatNumber seat) const -> std::size_t {
    const std::lock_guard lock(mutex_);
    return static_cast<std::size_t>(std::ranges::count(seats_, seat));
  }

 private:
  mutable std::mutex mutex_;
  std::vector<controllers::SeatNumber> seats_;
  std::atomic<bool> seated_{};
};

class Sitting {
 public:
  Sitting() : stream_(heard_) {}
  Sitting(const Sitting&) = delete;
  auto operator=(const Sitting&) -> Sitting& = delete;

  auto heard() noexcept -> RecordingListener& { return heard_; }
  auto stream() noexcept -> chiaki_bridge::StreamSession& { return stream_; }

  auto log_text() -> std::string {
    std::string text;
    for (auto lines = stream_.read_logs(16); !lines.empty();
         lines = stream_.read_logs(16)) {
      for (const auto& line : lines) {
        text.append(line.message).push_back('\n');
      }
    }
    return text;
  }

 private:
  RecordingListener heard_;
  chiaki_bridge::StreamSession stream_;
};

#if CHIAKI_KAKUSAN
auto accepted(const chiaki_bridge::KakusanCommandOutcome& outcome) -> bool {
  return outcome.kind() == chiaki_bridge::KakusanCommandOutcome::Kind::accepted;
}

auto declined_as(const chiaki_bridge::KakusanCommandOutcome& outcome,
                 libchiaking::kakusan::Refusal::Kind kind) -> bool {
  return outcome.kind() ==
             chiaki_bridge::KakusanCommandOutcome::Kind::declined &&
         outcome.decline() == kind;
}
#endif

void settle_until(auto&& done) {
  while (!done()) {
    std::this_thread::sleep_for(std::chrono::milliseconds{2});
  }
}

}  // namespace

int main() {
  const auto directory =
      std::filesystem::temp_directory_path() / "chiaki-bridge-scripted-test";
  std::filesystem::remove_all(directory);
  std::filesystem::create_directories(directory);
  const std::string catalog_directory = directory.string();
  assert(chiaki_bridge::CoreSession::open(
      catalog_directory, Shelf::one_sign_in(), Shelf::one_console_away(),
      std::make_shared<chiaki_bridge_testing::MemoryDatacenterStore>(),
      std::make_shared<libchiaking::kakusan::testing::InMemoryDeviceStore>(
          native_test_threading)));
  const AccountBytes account{4, 0, 0, 0, 0, 0, 0, 1};
  const chiaki_bridge::Bytes player(account.begin(), account.end());
  assert(chiaki_bridge::UsersBridge::add_home_user(player, "Player").kind() ==
         chiaki_bridge::HomeUserOutcome::Kind::added);
  const AccountBytes signed_in{6, 0, 0, 0, 0, 0, 0, 2};
  const chiaki_bridge::Bytes member(signed_in.begin(), signed_in.end());
  const auto welcomed = chiaki_bridge::UsersBridge::welcome_back();
  assert(welcomed && welcomed->admitted == 2 && welcomed->rejected == 0);

  {
    const auto saved = chiaki_bridge::CoreSession::remember_saved_consoles();
    assert(saved.loaded && saved.remembered == 1 && saved.rejected == 0);
    const chiaki_bridge::Bytes away(Shelf::away.begin(), Shelf::away.end());
    const auto console = chiaki_bridge::CoreSession::console(away);
    assert(console &&
           console->presence == libchiaking::consoles::Presence::unknown);
    using chiaki_bridge::ConsolesBridge;
    using libchiaking::consoles::Route;
    assert(ConsolesBridge::paired_with(away, member));
    const chiaki_bridge::Request unhurried;
    assert(ConsolesBridge::route(unhurried, member, away) == Route::internet);
    assert(ConsolesBridge::route(unhurried, player, away) == Route::home);
    const chiaki_bridge::Request abandoned;
    abandoned.cancel();
    assert(!ConsolesBridge::route(abandoned, member, away));
  }

  {
    Sitting sitting;
    auto& heard = sitting.heard();
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.progress(play::ConnectStep::reaching_console);
    link.connect();
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::Rumble{0x40, 0x80}});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::MotionReset{}});
    link.feed_back(
        {controllers::SeatNumber::first(),
         controllers::Lightbar{controllers::SeatLight{0x10, 0x20, 0x30}}});
    link.ask_for_login_pin(true);
    link.block_picture(true);
    link.block_picture(false);
    link.open_keyboard("hello");
    link.change_keyboard_text("hello there");
    link.close_keyboard();
    const auto second = controllers::SeatNumber::create(1).value();
    link.ask_for_passcode(second, true);
    link.join(second, controllers::SeatLight{1, 2, 3});
    link.refuse(play::SeatRefusal::account_not_on_console(second));
    link.refuse(play::SeatRefusal::by_console(second, 7));
    link.drop(second);
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{
        [&] { outcome = sitting.stream().run_scripted(player, link); }};
    heard.until(Heard::seat_left);
    chiaki_bridge::ControllerSample input{};
    input.buttons = 1U << 20;
    assert(!sitting.stream().send_controller(0, input));
    input.buttons = 1;
    input.l2 = 9;
    assert(sitting.stream().send_controller(0, input));
    assert(!sitting.stream().send_controller(4, input));
    settle_until([&] {
      return !link.controller_samples(controllers::SeatNumber::first()).empty();
    });
    const std::array<std::uint16_t, 2> keys{0x04, 0x05};
    assert(sitting.stream().send_keyboard(0x02, 0x02, keys));
    const std::array<std::uint16_t, 2> repeated{0x04, 0x04};
    assert(!sitting.stream().send_keyboard(0, 0, repeated));
    assert(!sitting.stream().send_keyboard(0, 8, {}));
    settle_until([&] { return link.count("keyboard") != 0; });
    const auto keyframes = link.keyframe_requests();
    assert(sitting.stream().request_keyframe());
    settle_until([&] { return link.keyframe_requests() > keyframes; });
    link.finish();
    run.join();
    assert(!sitting.stream().request_keyframe());
    assert(outcome.ending().ending == Ending::finished &&
           !outcome.ending().left);
    assert(outcome.kind() == chiaki_bridge::StreamOutcome::Kind::ended &&
           !outcome.ending().cause && !outcome.ending().launch_refused);
    assert(heard.saw(Heard::connected, 0));
    assert(heard.count(Heard::disconnected) == 1);
    assert(heard.count(Heard::connect_progress) >= 1);
    assert(heard.count(Heard::start_attempt) == 0);
    assert(heard.saw(Heard::motion_reset));
    assert(heard.saw(Heard::lightbar, 0, 0x102030));
    assert(heard.saw(Heard::login_pin, 1));
    assert(heard.saw(Heard::picture_blocked));
    assert(heard.saw(Heard::picture_allowed));
    assert(heard.saw(Heard::seat_passcode, 1, 1));
    assert(heard.saw(Heard::seat_joined, 1));
    assert((heard.refusals() ==
            std::vector<play::SeatRefusal>{
                play::SeatRefusal::account_not_on_console(second),
                play::SeatRefusal::by_console(second, 7)}));
    assert(heard.saw(Heard::seat_left, 1));
    const auto rumbles = heard.rumbles();
    assert(rumbles.size() == 1 &&
           rumbles.front() == (RecordingListener::Rumble{0, 0x40, 0x80}));
    const auto keyboard = heard.keyboard();
    assert(keyboard.size() == 3);
    assert(keyboard[0].first == chiaki_bridge::KeyboardChange::opened &&
           keyboard[0].second == "hello");
    assert(keyboard[1].first == chiaki_bridge::KeyboardChange::text_changed &&
           keyboard[1].second == "hello there");
    assert(keyboard[2].first == chiaki_bridge::KeyboardChange::closed);
    assert(link.count("keyboard") == 1);
    const auto samples =
        link.controller_samples(controllers::SeatNumber::first());
    assert(!samples.empty() && samples.back().buttons == 1 &&
           samples.back().l2 == 9);
    assert(!sitting.stream().go_home());
  }

  {
    Sitting sitting;
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.connect();
    link.quit(play::ConsoleQuit{play::ConsoleQuit::Reason::console_in_use});
    const auto outcome = sitting.stream().run_scripted(player, link);
    assert(outcome.ending().ending == Ending::console_quit);
    assert(outcome.ending().quit == play::ConsoleQuit::Reason::console_in_use);
    assert(sitting.heard().saw(
        Heard::disconnected,
        static_cast<int>(play::ConsoleQuit::Reason::console_in_use)));
  }

  {
    Sitting sitting;
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.refuse_start(
        play::EndReason{play::EndReason::Cause::session_request_in_use,
                        {.step = play::EndReason::Step::session_request,
                         .console_reason = 0x80108b10,
                         .http_status = 403}});
    const auto outcome = sitting.stream().run_scripted(player, link);
    assert(outcome.ending().ending == Ending::start_failed);
    assert(outcome.ending().cause ==
           play::EndReason::Cause::session_request_in_use);
    assert(outcome.ending().step == play::EndReason::Step::session_request);
    assert(outcome.ending().console_reason == 0x80108b10 &&
           outcome.ending().http_status == 403);
    assert(sitting.heard().count(Heard::connected) == 0);
    assert(!sitting.log_text().empty() || !outcome.diagnostics().empty());
  }

  {
    Sitting sitting;
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.connect();
    link.then([&sitting](play::testing::ScriptedLink&) {
      sitting.stream().cancel();
    });
    const auto outcome = sitting.stream().run_scripted(player, link);
    assert(outcome.ending().ending == Ending::left && outcome.ending().left);
    assert(sitting.stream().run_scripted(player, link).kind() ==
           chiaki_bridge::StreamOutcome::Kind::unrecorded);
  }

  {
    Sitting sitting;
    auto& heard = sitting.heard();
    sitting.stream().route_haptics(chiaki_bridge::HapticDelivery::blocks);
    const auto before = sitting.stream().statistics();
    assert(!before.protocol_version && before.units == 0 &&
           (!before.link || !before.link->round_trip));
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.report_protocol_version(12);
    link.connect();
    media::StreamDescription description;
    description.audio.channels = 2;
    description.audio.bits = 16;
    description.audio.rate = 48000;
    description.audio.frame_size = 480;
    description.profiles.push_back(
        {1280, 720, {std::byte{1}, std::byte{2}, std::byte{3}}});
    description.picture =
        media::GrantedPicture{media::VideoCodec::h265, 1280, 720, 60, 10000};
    link.describe(description);
    for (const std::uint16_t index : {std::uint16_t{1}, std::uint16_t{2}}) {
      media::VideoFrame::Facts facts;
      facts.bytes = {std::byte{5}, std::byte{6}, std::byte{7}, std::byte{8}};
      facts.frame_index = index;
      link.show(media::VideoFrame{facts});
    }
    const std::vector<std::byte> pcm(300, std::byte{0x11});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::HapticAudio{pcm}});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::HapticAudio{pcm}});
    controllers::TriggerEffects effects;
    effects.left.mode = 0x21;
    effects.right.mode = 0x26;
    link.feed_back({controllers::SeatNumber::first(), effects});
    link.ask_for_login_pin(false);
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{
        [&] { outcome = sitting.stream().run_scripted(player, link); }};
    heard.until(Heard::login_pin);
    assert(!sitting.stream().submit_login_pin("73x1"));
    assert(sitting.stream().submit_login_pin("7351"));
    settle_until([&] { return link.login_pin().view() == "7351"; });
    assert(link.count("login_pin") == 1);
    assert(sitting.stream().add_couch_player(
        1, controllers::ControllerKind::dualsense, player));
    assert(!sitting.stream().add_couch_player(
        4, controllers::ControllerKind::dualsense, player));
    assert(!sitting.stream().add_couch_player(
        1, controllers::ControllerKind::dualsense,
        chiaki_bridge::Bytes{1, 2, 3}));
    settle_until([&] { return link.count("seat_join") != 0; });
    const auto second = controllers::SeatNumber::create(1).value();
    link.ask_for_passcode(second, false);
    heard.until(Heard::seat_passcode);
    assert(sitting.stream().submit_seat_passcode(1, "8642"));
    settle_until([&] { return link.count("seat_passcode") != 0; });
    using Request = play::testing::ScriptedLink::SeatRequest;
    assert(link.seat_requests().back().kind == Request::Kind::passcode);
    assert(link.seat_requests().back().seat == second);
    std::array<std::uint8_t, chiaki_bridge::Stream::feedback_report_size>
        report{};
    assert(sitting.stream().take_feedback(0, report));
    assert((report[0] & 2) != 0 && report[257] == 0x21 && report[268] == 0x26);
    const auto stats = sitting.stream().statistics();
    assert(stats.protocol_version == 12U);
    assert(stats.granted && stats.granted->codec == media::VideoCodec::h265 &&
           stats.granted->width == 1280 && stats.granted->height == 720);
    assert(stats.granted->max_fps == 60 &&
           stats.granted->bitrate_kbps == 10000);
    assert(sitting.stream().feedback_statistics().buffered_bytes ==
           600 - 2 * 256);
    link.finish();
    run.join();
    assert(outcome.ending().ending == Ending::finished);
    const auto videos = heard.videos();
    assert(videos.size() == 2);
    assert(videos[0] == (RecordingListener::Video{4, 3}));
    assert(videos[1] == (RecordingListener::Video{4, 0}));
    assert(heard.haptic_blocks() == 2);
    const auto text = sitting.log_text();
    assert(!text.empty());
    assert(text.find("7351") == std::string::npos &&
           text.find("8642") == std::string::npos);
    assert(!sitting.stream().take_feedback(0, report));
  }

  {
    Sitting sitting;
    auto& heard = sitting.heard();
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.connect();
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{
        [&] { outcome = sitting.stream().run_scripted(player, link); }};
    heard.until(Heard::connected);
    const auto second = controllers::SeatNumber::create(1).value();
    assert(sitting.stream().add_couch_player(
        1, controllers::ControllerKind::dualsense, {}));
    settle_until([&] { return link.count("seat_join") != 0; });
    link.join(second, controllers::SeatLight{1, 2, 3});
    heard.until(Heard::seat_joined);
    link.fail(play::EndReason{play::EndReason::Cause::control_network_failure});
    heard.until(Heard::reconnecting);
    heard.until_saw(Heard::seat_left, 1);
    assert(heard.count(Heard::disconnected) == 0);
    assert(link.count("wake_console") == 1);
    link.connect();
    heard.until_saw(Heard::connected, 1);
    assert(heard.saw(Heard::connected, 0));
    assert(link.count("start") == 2);
    assert(heard.count(Heard::disconnected) == 0 &&
           heard.count(Heard::seat_left) == 1);
    assert(sitting.stream().add_couch_player(
        1, controllers::ControllerKind::dualsense, {}));
    settle_until([&] { return link.count("seat_join") >= 2; });
    link.finish();
    run.join();
    assert(outcome.ending().ending == Ending::finished &&
           heard.count(Heard::disconnected) == 1);
  }

  {
    Sitting sitting;
    auto& heard = sitting.heard();
    sitting.stream().route_haptics(chiaki_bridge::HapticDelivery::frames);
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.report_protocol_version(12);
    link.connect();
    media::StreamDescription description;
    description.audio.channels = 2;
    description.audio.bits = 16;
    description.audio.rate = 48000;
    description.audio.frame_size = 480;
    description.profiles.push_back(
        {1280, 720, {std::byte{1}, std::byte{2}, std::byte{3}}});
    link.describe(description);
    const std::vector<std::byte> pcm(300, std::byte{0x22});
    const std::vector<std::byte> torn(3, std::byte{0x22});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::HapticAudio{pcm}});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::HapticAudio{torn}});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::MotionReset{}});
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{
        [&] { outcome = sitting.stream().run_scripted(player, link); }};
    heard.until(Heard::motion_reset);
    assert(heard.haptic_frames() == (std::vector<std::size_t>{256, 44}));
    const auto feedback = sitting.stream().feedback_statistics();
    assert(feedback.malformed == 1 && feedback.buffered_bytes == 0);

    const auto second = controllers::SeatNumber::create(1).value();
    const auto third = controllers::SeatNumber::create(2).value();
    const auto fourth = controllers::SeatNumber::create(3).value();
    assert(sitting.stream().add_couch_player(
        1, controllers::ControllerKind::dualsense, {}));
    assert(sitting.stream().add_couch_player(
        2, controllers::ControllerKind::dualsense, {}));
    settle_until([&] { return link.count("seat_join") >= 2; });
    link.join(second, controllers::SeatLight{1, 2, 3});
    link.join(third, controllers::SeatLight{4, 5, 6});
    heard.until_count(Heard::seat_joined, 2);

    Audience audience;
    const auto session = sitting.stream().session();
    assert(session);
    auto sharing = session->share().begin(audience);
    assert(sharing);
    auto guest = session->share().seat_guest(
        {play::GuestTag{1}, controllers::ControllerKind::dualsense,
         std::nullopt, fourth});
    assert(guest);
    settle_until([&] { return link.count("seat_join") >= 3; });
    link.join(fourth, controllers::SeatLight{7, 8, 9});
    settle_until([&] { return audience.seated(); });

    controllers::TriggerEffects effects;
    effects.left.mode = 0x21;
    effects.right.mode = 0x26;
    link.feed_back({second, effects});
    link.feed_back({third, effects});
    link.feed_back({fourth, effects});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::MotionReset{}});
    heard.until_count(Heard::motion_reset, 2);
    assert(audience.heard(fourth) == 1);
    std::array<std::uint8_t, chiaki_bridge::Stream::feedback_report_size>
        report{};
    report.fill(0xff);
    assert(!sitting.stream().take_feedback(3, report));
    assert(std::ranges::all_of(report,
                               [](std::uint8_t byte) { return byte == 0; }));
    assert(sitting.stream().remove_couch_player(1));
    assert(!sitting.stream().take_feedback(1, report));
    link.feed_back(
        {controllers::SeatNumber::first(),
         controllers::TriggerIntensity{controllers::FeedbackIntensity::weak}});
    link.feed_back(
        {controllers::SeatNumber::first(), controllers::MotionReset{}});
    heard.until_count(Heard::motion_reset, 3);
    assert(!sitting.stream().take_feedback(1, report));
    assert(sitting.stream().take_feedback(2, report));
    assert((report[0] & 2) != 0 && report[257] == 0x21 && report[268] == 0x26);
    sharing.value().stop();
    link.finish();
    run.join();
    assert(outcome.ending().ending == Ending::finished);
  }

  {
    namespace progress = libchiaking::progress;
    using Route = progress::InternetRoute;
    Sitting sitting;
    auto& heard = sitting.heard();
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.route({Route::Step::opening_account_session, Route::Purpose::control,
                std::nullopt, std::nullopt});
    link.route({Route::Step::waiting_for_console, Route::Purpose::control,
                std::nullopt, std::nullopt});
    link.route({Route::Step::testing_candidates, Route::Purpose::control,
                Route::Candidates{2, 1, 0}, std::nullopt});
    link.route({Route::Step::route_chosen, Route::Purpose::control,
                std::nullopt, Route::Kind::public_address});
    link.route({Route::Step::switching_control, Route::Purpose::stream,
                std::nullopt, std::nullopt});
    link.connect();
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{[&] {
      outcome =
          sitting.stream().run_scripted(member, link, play::Where::internet);
    }};
    heard.until(Heard::connected);
    const auto routed = heard.connects();
    assert(routed.size() == 5);
    assert(routed[0].step == play::ConnectStep::opening_account_session);
    assert(routed[0].route->step == Route::Step::opening_account_session);
    assert(routed[0].route->purpose == Route::Purpose::control &&
           !routed[0].status().wait);
    assert(routed[1].step == play::ConnectStep::opening_account_session);
    assert(routed[1].route->step == Route::Step::waiting_for_console);
    assert(routed[1].status().wait->reason ==
               progress::WaitReason::console_joining &&
           !routed[1].status().wait->next_try_in);
    assert(routed[2].step == play::ConnectStep::reaching_console);
    assert(routed[2].route->step == Route::Step::testing_candidates &&
           routed[2].route->candidates);
    assert(routed[2].route->candidates->local == 2 &&
           routed[2].route->candidates->public_address == 1);
    assert(routed[2].route->candidates->port_guessed == 0 &&
           !routed[2].route->chosen);
    assert(routed[3].route->step == Route::Step::route_chosen &&
           !routed[3].route->candidates);
    assert(routed[3].route->chosen == Route::Kind::public_address);
    assert(routed[4].step == play::ConnectStep::opening_stream_route);
    assert(routed[4].route->step == Route::Step::switching_control);
    assert(routed[4].route->purpose == Route::Purpose::stream);
    for (const auto& row : routed) {
      assert(row.status().attempt == 1 && !row.reconnecting);
      assert(!row.previous_failure);
      assert(!row.status().position &&
             row.status().elapsed >= std::chrono::microseconds{0});
    }
    link.fail(play::EndReason{play::EndReason::Cause::control_network_failure});
    heard.until(Heard::reconnecting);
    settle_until([&] { return heard.connects().size() >= 6; });
    const auto retry = heard.connects()[5];
    assert(retry.reconnecting && retry.status().attempt == 2);
    assert(retry.step == play::ConnectStep::opening_account_session);
    assert(retry.status().wait->reason ==
               progress::WaitReason::connection_retry &&
           retry.status().wait->next_try_in == std::chrono::milliseconds{2000});
    assert(retry.previous_failure->cause ==
               play::EndReason::Cause::control_network_failure &&
           !retry.previous_failure->console_quit);
    assert(!retry.route);
    link.connect();
    heard.until_saw(Heard::connected, 1);
    link.finish();
    run.join();
    assert(outcome.ending().ending == Ending::finished);
  }

  {
    namespace progress = libchiaking::progress;
    using namespace std::chrono_literals;
    const auto cloud = libchiaking::catalog::ServiceGeneration::ps5_cloud;
    Sitting sitting;
    auto& heard = sitting.heard();
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{[&] {
      outcome = sitting.stream().run_scripted(member, link, play::Where::cloud);
    }};
    link.launch_progress(
        play::LaunchProgress::at(
            cloud, play::LaunchActivity::reserving_server,
            {.step = play::LaunchProgress::Step{7, 10},
             .attempt = 2,
             .wait =
                 progress::Wait{progress::WaitReason::previous_session_closing,
                                10000ms}})
            ->after(3s));
    link.launch_progress(*play::LaunchProgress::at(
        cloud, play::LaunchActivity::measuring_datacenters,
        {.step = play::LaunchProgress::Step{8, 10},
         .measured = play::LaunchProgress::Step{3, 9}}));
    link.launch_progress(*play::LaunchProgress::at(
        cloud, play::LaunchActivity::allocating_server,
        {.queue_position = 4,
         .attempt = 1,
         .wait = progress::Wait{progress::WaitReason::server_queue, 15000ms}}));
    settle_until([&] { return heard.launches().size() >= 3; });
    const auto launches = heard.launches();
    assert(std::ranges::none_of(
        launches, [](const auto& launch) { return launch.second; }));
    const auto& reserving = launches[0].first;
    const auto& measuring = launches[1].first;
    const auto& allocating = launches[2].first;
    assert(reserving.activity() == play::LaunchActivity::reserving_server);
    assert(reserving.status().position == (progress::Position{7, 10}));
    assert(reserving.status().attempt == 2 && reserving.status().elapsed == 3s);
    assert(reserving.status().wait->reason ==
               progress::WaitReason::previous_session_closing &&
           reserving.status().wait->next_try_in == 10000ms);
    assert(!reserving.measured());
    assert(measuring.activity() ==
               play::LaunchActivity::measuring_datacenters &&
           measuring.measured()->number == 3);
    assert(measuring.measured()->of == 9 && !measuring.status().wait);
    assert(measuring.status().position->number == 8 &&
           measuring.status().attempt == 1 && !measuring.status().elapsed);
    assert(allocating.activity() == play::LaunchActivity::allocating_server &&
           allocating.queue_position() == 4U);
    assert(allocating.status().wait->reason ==
               progress::WaitReason::server_queue &&
           allocating.status().wait->next_try_in == 15000ms);
    assert(!allocating.status().position);
    sitting.stream().cancel();
    run.join();
    assert(outcome.ending().ending == Ending::left);
  }

  {
    Sitting sitting;
    auto& heard = sitting.heard();
    auto& stream = sitting.stream();
    heard.on_launch([&stream] {
      static_cast<void>(stream.statistics());
      static_cast<void>(stream.go_home());
      stream.cancel();
    });
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{[&] {
      outcome = stream.run_scripted(member, link, play::Where::cloud);
    }};
    link.launch_progress(*play::LaunchProgress::at(
        libchiaking::catalog::ServiceGeneration::ps5_cloud,
        play::LaunchActivity::reserving_server));
    run.join();
    assert(!heard.launches().empty());
    assert(outcome.ending().ending == Ending::left && outcome.ending().left);
    assert(heard.count(Heard::connected) == 0);
  }

#if CHIAKI_KAKUSAN
  {
    Sitting sitting;
    auto& heard = sitting.heard();
    const chiaki_bridge::KakusanHosting hosting{.capacity = 3,
                                                .local_seats = 1};
    assert(accepted(sitting.stream().arm_kakusan(hosting)));
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    std::uint32_t version = 9;
    while (!play::SessionShare::shares_protocol_version(version)) {
      ++version;
    }
    link.report_protocol_version(version);
    link.connect();
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{
        [&] { outcome = sitting.stream().run_scripted(player, link); }};
    heard.until(Heard::connected);
    settle_until([&] {
      return declined_as(sitting.stream().arm_kakusan(hosting),
                         kakusan::Refusal::Kind::busy) ||
             !heard.shared(KakusanEvent::Kind::sharing_failed).empty();
    });
    assert(heard.shared(KakusanEvent::Kind::sharing_failed).empty());
    assert(accepted(sitting.stream().set_capacity(4)));
    assert(declined_as(sitting.stream().invite_guest(),
                       kakusan::Refusal::Kind::not_sharing));
    assert(accepted(sitting.stream().set_local_seats(2)));
    assert(declined_as(sitting.stream().set_local_seats(5),
                       kakusan::Refusal::Kind::invalid_argument));
    assert(heard.shared(KakusanEvent::Kind::sharing_failed).empty());
    link.finish();
    run.join();
    assert(outcome.ending().ending == Ending::finished);
    assert(heard.shared(KakusanEvent::Kind::sharing_ended).size() == 1);
    assert(declined_as(sitting.stream().invite_guest(),
                       kakusan::Refusal::Kind::not_sharing));
  }

  {
    Sitting sitting;
    auto& heard = sitting.heard();
    assert(accepted(
        sitting.stream().arm_kakusan({.capacity = 2, .local_seats = 1})));
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.connect();
    auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread run{[&] {
      outcome = sitting.stream().run_scripted(member, link, play::Where::cloud);
    }};
    heard.until(Heard::connected);
    settle_until([&] {
      return !heard.shared(KakusanEvent::Kind::sharing_failed).empty();
    });
    const auto failed = heard.shared(KakusanEvent::Kind::sharing_failed);
    assert(failed.size() == 1 && failed.front().event.refused ==
                                     kakusan::Refusal::Kind::cannot_be_shared);
    link.finish();
    run.join();
    assert(outcome.ending().ending == Ending::finished);
  }

  {
    Sitting sitting;
    auto& heard = sitting.heard();
    assert(declined_as(sitting.stream().enter_host_code("1234"),
                       kakusan::Refusal::Kind::not_visiting));
    const auto outcome = sitting.stream().join_kakusan("RCP1:AAAA", false);
    assert(outcome.kind() == chiaki_bridge::GuestOutcome::Kind::ended &&
           outcome.ending().status ==
               kakusan::VisitOutcome::Status::visit_failed);
    assert(outcome.ending().refused == kakusan::Refusal::Kind::invalid_text);
    const auto unavailable = heard.shared(KakusanEvent::Kind::unavailable);
    assert(unavailable.size() == 1 && unavailable.front().event.refused ==
                                          kakusan::Refusal::Kind::invalid_text);
    assert(heard.count(Heard::connected) == 0);
    assert(declined_as(sitting.stream().leave_kakusan(),
                       kakusan::Refusal::Kind::not_visiting));
  }
#endif

  {
    Sitting sitting;
    sitting.heard().refuse_video();
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.connect();
    const auto outcome = sitting.stream().run_scripted(player, link);
    assert(outcome.refusal() == chiaki_bridge::StreamRefusal::no_decoder);
  }

  {
    Sitting sitting;
    const chiaki_bridge::Bytes stranger{9, 0, 0, 0, 0, 0, 0, 9};
    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    const auto outcome = sitting.stream().run_scripted(stranger, link);
    assert(outcome.refusal() == chiaki_bridge::StreamRefusal::unknown_user);
  }

  using chiaki_bridge::PlayBridge;
  using chiaki_bridge::StreamTarget;
  assert(PlayBridge::built_protocol_version(StreamTarget::local_ps4) == 9);
  assert(PlayBridge::built_protocol_version(StreamTarget::local_ps5) == 20);
  assert(PlayBridge::built_protocol_version(StreamTarget::ps_now) == 12);
  assert(PlayBridge::built_protocol_version(StreamTarget::ps_cloud) == 23);

  chiaki_bridge::CoreSession::close();
  std::filesystem::remove_all(directory);
  return 0;
}
