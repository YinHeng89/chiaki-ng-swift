#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <libchiaking/kakusan.hpp>
#include <libchiaking/platform/platform.hpp>
#include <libchiaking/play.hpp>
#include <libchiaking/testing/in_memory_console_store.hpp>
#include <libchiaking/testing/in_memory_credential_store.hpp>
#include <libchiaking/testing/kakusan/in_memory_device_store.hpp>
#include <libchiaking/testing/kakusan/kakusan_pair.hpp>
#include <libchiaking/testing/play/scripted_link.hpp>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

#include "chiaki_bridge/core.hpp"
#include "chiaki_bridge/kakusan.hpp"
#include "chiaki_bridge/users.hpp"
#include "runtime.hpp"
#include "stream_session.hpp"
#include "support/memory_datacenter_store.hpp"
#include "support/stand_in_share.hpp"

namespace {

auto& native_test_threading = chiaki_bridge::Runtime::process().threading();
auto& native_test_clock = chiaki_bridge::Runtime::process().clock();

namespace play = libchiaking::play;
namespace controllers = libchiaking::controllers;
namespace media = libchiaking::media;
namespace kakusan = libchiaking::kakusan;

using chiaki_bridge::KakusanEvent;
using Kind = KakusanEvent::Kind;
using AccountBytes = std::array<std::uint8_t, libchiaking::psn_account_id_size>;

class Party final : public chiaki_bridge::StreamListener {
 public:
  struct Heard {
    KakusanEvent event;
    std::string text;

    auto has_pad() const -> bool { return event.pad.has_value(); }
    auto has_reserved_pad() const -> bool {
      return event.reserved_pad.has_value();
    }
    auto clean() const -> bool { return !event.refused && !event.refusal; }
  };

  static constexpr std::chrono::seconds patience{30};

  Party() : stream_(*this) {}

  auto on_video(const chiaki_bridge::EncodedFrame& frame)
      -> media::VideoResult override {
    const std::lock_guard lock(mutex_);
    pictures_.emplace_back(frame.bytes.begin(), frame.bytes.end());
    return {};
  }

  void on_connected(bool reconnected) override {
    if (!reconnected) {
      connected_ = true;
    }
  }

  void on_seat_joined(controllers::SeatNumber seat) override {
    const std::lock_guard lock(mutex_);
    joined_.push_back(seat.index());
  }

  void on_kakusan(const KakusanEvent& event, std::string_view text) override {
    const std::lock_guard lock(mutex_);
    heard_.push_back({event, std::string{text}});
  }

  template <class Done>
  static void until(Done&& done, const char* what) {
    const auto deadline = std::chrono::steady_clock::now() + patience;
    while (!done()) {
      if (std::chrono::steady_clock::now() > deadline) {
        std::fprintf(stderr, "timed out waiting for %s\n", what);
        std::abort();
      }
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
  }

  auto stream() noexcept -> chiaki_bridge::StreamSession& { return stream_; }

  auto connected() const noexcept -> bool { return connected_; }

  auto joined(std::uint8_t pad) const -> bool {
    const std::lock_guard lock(mutex_);
    return std::ranges::find(joined_, pad) != joined_.end();
  }

  auto heard() const -> std::vector<Heard> {
    const std::lock_guard lock(mutex_);
    return heard_;
  }

  auto last(Kind kind) const -> std::optional<Heard> {
    const std::lock_guard lock(mutex_);
    const auto found = std::ranges::find_if(
        heard_.rbegin(), heard_.rend(),
        [kind](const Heard& heard) { return heard.event.kind == kind; });
    return found == heard_.rend() ? std::nullopt : std::optional<Heard>{*found};
  }

  auto reached(kakusan::Progress progress) const -> std::optional<Heard> {
    const std::lock_guard lock(mutex_);
    const auto found =
        std::ranges::find_if(heard_, [progress](const Heard& heard) {
          return heard.event.kind == Kind::state_changed &&
                 heard.event.progress == progress;
        });
    return found == heard_.end() ? std::nullopt : std::optional<Heard>{*found};
  }

  auto await(Kind kind, const char* what) const -> Heard {
    until([&] { return last(kind).has_value(); }, what);
    return *last(kind);
  }

  auto await_state(kakusan::Progress progress, const char* what) const
      -> Heard {
    until([&] { return reached(progress).has_value(); }, what);
    return *reached(progress);
  }

  auto pictures() const -> std::vector<std::vector<std::byte>> {
    const std::lock_guard lock(mutex_);
    return pictures_;
  }

 private:
  mutable std::mutex mutex_;
  std::atomic<bool> connected_{};
  std::vector<std::uint8_t> joined_;
  std::vector<Heard> heard_;
  std::vector<std::vector<std::byte>> pictures_;
  chiaki_bridge::StreamSession stream_;
};

auto accepted(const chiaki_bridge::KakusanCommandOutcome& outcome) -> bool {
  return outcome.kind() == chiaki_bridge::KakusanCommandOutcome::Kind::accepted;
}

auto declined_as(const chiaki_bridge::KakusanCommandOutcome& outcome,
                 libchiaking::kakusan::Refusal::Kind kind) -> bool {
  return outcome.kind() ==
             chiaki_bridge::KakusanCommandOutcome::Kind::declined &&
         outcome.decline() == kind;
}

class Evening {
 public:
  static void a_guest_is_invited_seated_and_sees_the_hosts_picture(
      const chiaki_bridge::Bytes& account) {
    play(account, Ending::session_ends);
  }

  static void the_console_drops_a_seated_guest(
      const chiaki_bridge::Bytes& account) {
    play(account, Ending::console_drops_guest);
  }

 private:
  enum class Ending : std::uint8_t { session_ends, console_drops_guest };

  static void play(const chiaki_bridge::Bytes& account, Ending ending) {
    using kakusan::Progress;
    kakusan::testing::InMemoryDeviceStore host_devices{native_test_threading};
    kakusan::testing::InMemoryDeviceStore guest_devices{native_test_threading};
    auto paired = kakusan::testing::KakusanPair::create(
        chiaki_bridge::Opened::shared()->platform().factory(),
        {host_devices, guest_devices},
        kakusan::testing::KakusanPair::Time::real);
    assert(paired);
    auto& pair = *paired.value();

    Party host;
    Party guest;
    chiaki_bridge::StandInShare::use(host.stream(), pair.host());
    chiaki_bridge::StandInShare::use(guest.stream(), pair.guest());

    const chiaki_bridge::KakusanHosting hosting{.capacity = 4,
                                                .local_seats = 2};
    assert(accepted(host.stream().arm_kakusan(hosting)));

    play::testing::ScriptedLink link{native_test_threading, native_test_clock};
    link.connect();
    auto hosted_outcome = chiaki_bridge::StreamOutcome::unrecorded();
    std::thread hosted{
        [&] { hosted_outcome = host.stream().run_scripted(account, link); }};
    Party::until([&] { return host.connected(); }, "the host to play");

    const auto first = controllers::SeatNumber::create(1).value();
    const auto second = controllers::SeatNumber::create(2).value();
    assert(host.stream().add_couch_player(
        1, controllers::ControllerKind::dualsense, {}));
    Party::until([&] { return link.count("seat_join") == 1; },
                 "the local seat request");
    link.join(first, controllers::SeatLight{0, 0, 255});
    Party::until([&] { return host.joined(1); }, "the local seat");

    Party::until(
        [&] {
          return declined_as(host.stream().arm_kakusan(hosting),
                             kakusan::Refusal::Kind::busy);
        },
        "the session to be shared");
    assert(accepted(host.stream().set_capacity(4)));
    link.start_shared_stream();
    const auto shared = host.await(Kind::stream_shared, "the shared stream");
    assert(shared.event.video_fps ==
           play::testing::ScriptedLink::shared_media().frames_per_second);

    const auto invite = host.stream().invite_guest();
    assert(accepted(invite) && !invite.guest().empty());
    const auto invited = invite.guest();
    Party::until(
        [&] {
          const auto seen = host.heard();
          return std::ranges::any_of(seen, [&](const Party::Heard& heard) {
            return heard.event.kind == Kind::invitation_ready &&
                   heard.event.guest == invited;
          });
        },
        "the invitation");
    const auto invitation = host.last(Kind::invitation_ready).value();
    assert(invitation.event.guest == invited && !invitation.text.empty());

    auto visited_outcome = chiaki_bridge::GuestOutcome::declined(
        libchiaking::kakusan::Refusal::Kind::internal);
    std::thread visited{[&] {
      visited_outcome = guest.stream().join_kakusan(invitation.text, false);
    }};

    const auto reply = guest.await(Kind::reply_ready, "the guest's reply");
    assert(!reply.text.empty());
    const auto imported = host.stream().import_reply(reply.text);
    assert(accepted(imported) && imported.guest() == invited);

    const auto hosts_code = host.await(Kind::code_ready, "the host's code");
    const auto guests_code = guest.await(Kind::code_ready, "the guest's code");
    assert(hosts_code.text.size() == kakusan::VerificationCode::size &&
           hosts_code.event.guest == invited);
    assert(guests_code.text.size() == kakusan::VerificationCode::size);
    assert(accepted(host.stream().enter_guest_code(invited, guests_code.text)));
    assert(accepted(guest.stream().enter_host_code(hosts_code.text)));
    guest.await_state(Progress::waiting_for_seat,
                      "the guest to wait for a seat");
    const auto admitted = host.await_state(Progress::waiting_for_seat,
                                           "the host to admit the guest");
    assert(admitted.event.guest == invited && !admitted.has_pad());

    const auto keyframes = link.keyframe_requests();
    assert(accepted(host.stream().give_seat(
        invited, 0, controllers::ControllerKind::dualsense, {})));
    Party::until([&] { return link.count("seat_join") == 2; },
                 "the guest's seat request");
    Party::until(
        [&] {
          const auto seen = host.heard();
          return std::ranges::any_of(seen, &Party::Heard::has_reserved_pad);
        },
        "the host to hear the reserved seat");
    const auto before_join = host.heard();
    const auto held =
        std::ranges::find_if(before_join, &Party::Heard::has_reserved_pad);
    assert(held->event.kind == Kind::state_changed &&
           held->event.guest == invited);
    assert(held->event.progress == Progress::waiting_for_seat &&
           held->event.reserved_pad == 2 && !held->has_pad());
    assert(held->event.grant && held->event.grant->number == 3 &&
           held->event.grant->generation != 0);
    assert(std::ranges::none_of(before_join, [](const Party::Heard& heard) {
      return heard.event.kind == Kind::player_seated || heard.has_pad();
    }));
    link.join(second, controllers::SeatLight{0, 255, 0});

    const auto playing =
        guest.await_state(Progress::playing, "the guest to play");
    assert(playing.event.grant && playing.event.grant->generation != 0 &&
           playing.clean());
    const auto on_the_console = [](const Party::Heard& heard) {
      return heard.event.kind == Kind::state_changed &&
             heard.event.progress == Progress::playing && heard.has_pad();
    };
    Party::until(
        [&] { return std::ranges::any_of(host.heard(), on_the_console); },
        "the host to see the guest on the console");
    const auto seated = host.heard();
    const auto on_console = std::ranges::find_if(seated, on_the_console);
    assert(on_console->event.guest == invited && on_console->event.pad == 2);
    const auto joined =
        std::ranges::find_if(seated, [](const Party::Heard& heard) {
          return heard.event.kind == Kind::player_seated;
        });
    assert(joined != seated.end() && joined < on_console);
    assert(joined->event.guest == invited && joined->event.pad == 2);
    assert(std::ranges::none_of(seated, [](const Party::Heard& heard) {
      return heard.event.kind == Kind::player_unseated;
    }));
    assert(
        std::ranges::none_of(seated.begin(), joined, &Party::Heard::has_pad));
    const auto reserved =
        std::ranges::find_if(seated, &Party::Heard::has_reserved_pad);
    assert(reserved != seated.end() && reserved < joined);
    assert(reserved->event.reserved_pad == joined->event.pad);
    assert(reserved->event.grant == playing.event.grant);
    assert(std::ranges::none_of(joined, seated.end(),
                                &Party::Heard::has_reserved_pad));
    assert(on_console->event.grant == playing.event.grant);
    const auto seats = host.await(Kind::seats_changed, "the seat count");
    assert(seats.event.seats && seats.event.seats->capacity == 4 &&
           seats.event.seats->local_seats == 2 &&
           seats.event.seats->remote_seats == 1);
    assert(seats.event.seats->reserved_seats == 0);

    Party::until([&] { return link.keyframe_requests() > keyframes; },
                 "the guest's keyframe request");
    link.send_shared_media();
    const auto media = play::testing::ScriptedLink::shared_media();
    Party::until(
        [&] {
          return guest.pictures().size() == media.video_frames.size() + 1;
        },
        "the host's picture on the guest");
    const auto pictures = guest.pictures();
    assert(!pictures.front().empty());
    for (std::size_t index = 0; index < media.video_frames.size(); ++index) {
      const auto& sent = media.video_frames[index];
      const auto& shown = pictures[index + 1];
      assert(shown.size() == sent.size());
      assert(std::memcmp(shown.data(), sent.data(), sent.size()) == 0);
      assert(pictures.front().size() != sent.size() ||
             std::memcmp(pictures.front().data(), sent.data(), sent.size()) !=
                 0);
    }
    assert(host.pictures().empty());

    chiaki_bridge::ControllerSample input{};
    input.buttons = 1;
    input.l2 = 9;
    Party::until(
        [&] {
          static_cast<void>(guest.stream().send_controller(0, input));
          const auto samples = link.controller_samples(second);
          return std::ranges::any_of(
              samples, [](const controllers::ControllerState& state) {
                return state.buttons == 1 && state.l2 == 9;
              });
        },
        "the guest's controller on the console");
    assert(link.controller_samples(first).empty());

    if (ending == Ending::console_drops_guest) {
      link.drop(second);
      const auto dropped =
          host.await(Kind::player_unseated, "the console to drop the guest");
      assert(dropped.event.guest == invited && dropped.event.pad == 2);
      const auto gone =
          host.await_state(Progress::gone, "the host to lose the guest");
      assert(gone.event.guest == invited && !gone.has_pad());
      assert(gone.event.ended == kakusan::EndReason::Kind::session_ended &&
             gone.clean());
      link.finish();
      hosted.join();
      visited.join();
      assert(hosted_outcome.ending().ending == play::Outcome::Ending::finished);
      return;
    }

    link.finish();
    hosted.join();
    visited.join();
    assert(hosted_outcome.ending().ending == play::Outcome::Ending::finished);
    assert(visited_outcome.kind() == chiaki_bridge::GuestOutcome::Kind::ended &&
           visited_outcome.ending().status ==
               kakusan::VisitOutcome::Status::completed &&
           !visited_outcome.ending().refused);
    const auto ended = host.await(Kind::sharing_ended, "the sharing to end");
    assert(ended.clean());
    const auto left = guest.await_state(Progress::gone, "the guest to be told");
    assert(left.event.by_peer);
    assert(host_devices.identity_saves() == 1 &&
           guest_devices.identity_saves() == 1);
  }
};

struct StunOverride {
  static void only_a_usable_list_replaces_the_cores_servers() {
    using chiaki_bridge::KakusanDevices;
    using chiaki_bridge::KakusanUnavailable;
    const chiaki_bridge::Texts custom{"stun.example.com:3478",
                                      "192.0.2.1:19302"};
    using StunCase = chiaki_bridge::StunServersOutcome::Kind;
    assert(KakusanDevices::use_stun_servers(custom).kind() == StunCase::used);
    assert(KakusanDevices::use_stun_servers({}).kind() == StunCase::used);

    const chiaki_bridge::Texts crowded(
        libchiaking::kakusan::Kakusan::most_stun_servers + 1,
        "stun.example.com:3478");
    const auto refused = KakusanDevices::use_stun_servers(crowded);
    assert(refused.kind() == StunCase::unavailable &&
           refused.why_unavailable() ==
               KakusanUnavailable::invalid_stun_servers);
    const chiaki_bridge::Texts too_long{std::string(
        libchiaking::kakusan::Kakusan::longest_stun_server + 1, 'a')};
    assert(KakusanDevices::use_stun_servers(too_long).why_unavailable() ==
           KakusanUnavailable::invalid_stun_servers);
    assert(KakusanDevices::use_stun_servers({""}).why_unavailable() ==
           KakusanUnavailable::invalid_stun_servers);
  }
};

}  // namespace

int main() {
  const auto directory = std::filesystem::temp_directory_path() /
                         "chiaki-bridge-kakusan-pair-test";
  std::filesystem::remove_all(directory);
  std::filesystem::create_directories(directory);
  const std::string catalog_directory = directory.string();
  assert(chiaki_bridge::CoreSession::open(
      catalog_directory,
      std::make_shared<libchiaking::testing::InMemoryCredentialStore>(
          native_test_threading),
      std::make_shared<libchiaking::testing::InMemoryConsoleStore>(
          native_test_threading),
      std::make_shared<chiaki_bridge_testing::MemoryDatacenterStore>(),
      std::make_shared<kakusan::testing::InMemoryDeviceStore>(
          native_test_threading)));
  const AccountBytes account_bytes{4, 0, 0, 0, 0, 0, 0, 1};
  const chiaki_bridge::Bytes account(account_bytes.begin(),
                                     account_bytes.end());
  assert(chiaki_bridge::UsersBridge::add_home_user(account, "Player").kind() ==
         chiaki_bridge::HomeUserOutcome::Kind::added);

  StunOverride::only_a_usable_list_replaces_the_cores_servers();
  Evening::a_guest_is_invited_seated_and_sees_the_hosts_picture(account);
  Evening::the_console_drops_a_seated_guest(account);

  chiaki_bridge::CoreSession::close();
  std::filesystem::remove_all(directory);
  return 0;
}
