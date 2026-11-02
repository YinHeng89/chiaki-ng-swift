#include <algorithm>
#include <array>
#include <cassert>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <regex>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "account_ids.hpp"
#include "boundary.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "chiaki_bridge/media.hpp"
#include "console_ids.hpp"
#include "feedback_path.hpp"
#include "share_desk.hpp"
#include "stream_session.hpp"
#include "support/recording_listener.hpp"

namespace {

namespace play = libchiaking::play;
namespace controllers = libchiaking::controllers;

using chiaki_bridge::StreamTarget;

class BridgeFacts {
 public:
  static auto measured() -> play::Statistics {
    play::Statistics observed;
    observed.protocol_version = 12;
    auto& link = observed.link;
    link.available = true;
    link.video_units = 11;
    link.rejected_packets = 12;
    link.crypto_rejections = 13;
    link.assembled_video = 14;
    link.dependency_rejections = 15;
    link.assembly_rejections = 16;
    link.video_stale = 17;
    link.video_metadata = 18;
    link.video_duplicate = 19;
    link.video_invalid = 20;
    link.round_trip = {true, 21, 22, 7, 23, 24, 25, 26, 27};
    link.reception.present = true;
    link.reception.jitter_us = 23;
    link.reception.lost = 24;
    link.reception.received = 32;
    link.reorder_skipped = 33;
    link.reorder_dropped = 34;
    link.dropped_posts = 35;
    link.send_dropped = 36;
    observed.video.keyframe_requests = 37;
    observed.loop_errors = 38;
    link.reception.loss_ratio = 0.25;
    link.video_metrics.present = true;
    link.video_metrics.reports_present = true;
    link.video_metrics.throughput_bps = 26;
    link.video_metrics.loss_ratio = 0.5;
    link.video_metrics.receive_interval_us = 27;
    link.video_metrics.transfer_time_us = 28;
    link.video_metrics.reports_sent = 29;
    link.service_marks.present = true;
    link.service_marks.last_present = true;
    link.service_marks.last_dscp = 30;
    link.service_marks.last_ecn = 2;
    link.service_marks.packets = 31;
    return observed;
  }

  static auto described(const play::Statistics& observed)
      -> chiaki_bridge::StreamStatistics {
    return chiaki_bridge::StreamSession::statistics_of(observed);
  }

  static void link_statistics_follow_their_present_flags() {
    const auto all = described(measured());
    assert(all.protocol_version == 12U && all.link);
    const auto& link = *all.link;
    assert(link.video_units == 11 && link.rejected_packets == 12 &&
           link.crypto_rejections == 13);
    assert(link.assembled_video == 14 && link.dependency_rejections == 15);
    assert(link.assembly_rejections == 16 && link.video_stale == 17 &&
           link.video_metadata == 18);
    assert(link.video_duplicate == 19 && link.video_invalid == 20);
    assert(link.round_trip && link.round_trip->smoothed_us == 21 &&
           link.round_trip->variation_us == 22 &&
           link.round_trip->samples == 7 && link.round_trip->p99_us == 25 &&
           link.round_trip->recent_max_us == 27);
    assert(link.reception && link.reception->jitter_us == 23 &&
           link.reception->lost == 24);
    assert(link.reception->loss_ratio == 0.25 &&
           link.reception->received == 32);
    assert(link.video_metrics && link.video_metrics->throughput_bps == 26);
    assert(link.video_metrics->loss_ratio == 0.5 &&
           link.video_metrics->receive_interval_us == 27);
    assert(link.video_metrics->transfer_time_us == 28);
    assert(link.video_metrics->reports_sent == 29U);
    assert(link.service_marks && link.service_marks->last_dscp == 30 &&
           link.service_marks->last_ecn == 2);
    assert(link.service_marks->packets == 31);
    assert(link.reorder_skipped == 33 && link.reorder_dropped == 34);
    assert(link.dropped_posts == 35 && link.send_dropped == 36 &&
           all.keyframe_requests == 37 && all.loop_errors == 38);

    auto without = measured();
    without.link.round_trip.present = false;
    auto stats = described(without);
    assert(!stats.link->round_trip);
    assert(stats.link->reception && stats.link->service_marks &&
           stats.link->video_metrics);

    without = measured();
    without.link.reception.present = false;
    stats = described(without);
    assert(!stats.link->reception && stats.link->round_trip);

    without = measured();
    without.link.video_metrics.present = false;
    stats = described(without);
    assert(!stats.link->video_metrics);

    without = measured();
    without.link.video_metrics.reports_present = false;
    stats = described(without);
    assert(stats.link->video_metrics &&
           !stats.link->video_metrics->reports_sent);

    without = measured();
    without.link.service_marks.present = false;
    stats = described(without);
    assert(!stats.link->service_marks);

    without = measured();
    without.link.service_marks.last_present = false;
    stats = described(without);
    assert(stats.link->service_marks && !stats.link->service_marks->last_dscp &&
           !stats.link->service_marks->last_ecn &&
           stats.link->service_marks->packets == 31);

    without = measured();
    without.link.available = false;
    without.protocol_version.reset();
    stats = described(without);
    assert(!stats.link && !stats.protocol_version);
  }

  static void each_target_launches_with_its_own_version_and_negotiation() {
    const chiaki_bridge::TakionSetup takion{
        .local_ps4 = {.version = 9, .negotiate = false},
        .local_ps5 = {.version = 12, .negotiate = true},
        .ps_now = {.version = 0, .negotiate = false},
        .ps_cloud = {.version = 20, .negotiate = true}};
    using chiaki_bridge::StreamSession;
    const auto ps4 =
        StreamSession::developer_of(takion.of(StreamTarget::local_ps4), {});
    const auto ps5 =
        StreamSession::developer_of(takion.of(StreamTarget::local_ps5), {});
    const auto classics =
        StreamSession::developer_of(takion.of(StreamTarget::ps_now), {});
    const auto cloud =
        StreamSession::developer_of(takion.of(StreamTarget::ps_cloud), {});
    assert(ps4 && ps5 && classics && cloud);
    assert(ps4->protocol_version() == 9U &&
           !ps4->negotiates_protocol_version());
    assert(ps5->protocol_version() == 12U &&
           ps5->negotiates_protocol_version());
    assert(!classics->protocol_version() &&
           !classics->negotiates_protocol_version());
    assert(cloud->protocol_version() == 20U &&
           cloud->negotiates_protocol_version());
  }

  static void stream_media_choices_reach_every_target() {
    using chiaki_bridge::StreamSession;
    const chiaki_bridge::TakionSetup takion;
    const auto untouched =
        StreamSession::developer_of(takion.of(StreamTarget::local_ps5), {});
    assert(untouched && !untouched->disables_audio() &&
           !untouched->disables_video());
    for (const auto target : {StreamTarget::local_ps4, StreamTarget::local_ps5,
                              StreamTarget::ps_now, StreamTarget::ps_cloud}) {
      const auto silenced = StreamSession::developer_of(
          takion.of(target), {.audio = true, .video = true});
      assert(silenced && silenced->disables_audio() &&
             silenced->disables_video());
    }
    const auto picture_off = StreamSession::developer_of(
        takion.of(StreamTarget::local_ps5), {.video = true});
    assert(picture_off && !picture_off->disables_audio() &&
           picture_off->disables_video());
  }

  static void console_intensity_is_reported_and_local_rumble_stays_raw() {
    using chiaki_bridge::ConsoleFeedback;
    assert(ConsoleFeedback::scale_of(std::uint8_t{0}) == 0.0F);
    assert(ConsoleFeedback::scale_of(std::uint8_t{1}) == 1.0F);
    assert(ConsoleFeedback::scale_of(std::uint8_t{2}) == 0.5F);
    assert(ConsoleFeedback::scale_of(std::uint8_t{3}) == 0.33F);
    assert(ConsoleFeedback::scale_of(std::uint8_t{7}) == 0.33F);
    chiaki_bridge_testing::RecordingListener heard;
    {
      const auto stream = chiaki_bridge::Stream::open(heard);
      const auto untouched = stream->feedback_intensities();
      assert(untouched.haptic == 1 && untouched.trigger == 1);
    }
    chiaki_bridge::FeedbackPath feedback{heard};
    const auto first = controllers::SeatNumber::first();
    assert(feedback.accept({.seat = first,
                            .fact = controllers::HapticIntensity{
                                controllers::FeedbackIntensity::weak}}));
    assert(feedback.accept({.seat = first,
                            .fact = controllers::TriggerIntensity{
                                controllers::FeedbackIntensity::medium}}));
    const auto intensities = feedback.intensities();
    assert(intensities.haptic == 3 && intensities.trigger == 2);
    assert(feedback.accept(
        {.seat = first,
         .fact = controllers::Rumble{.left = 200, .right = 90}}));
    assert((heard.rumbles() ==
            std::vector<chiaki_bridge_testing::RecordingListener::Rumble>{
                {0, 200, 90}}));
  }

#if CHIAKI_KAKUSAN
  static void a_guests_seat_carries_the_chosen_account_controller_and_seat() {
    using chiaki_bridge::ShareDesk;
    const chiaki_bridge::Bytes account{9, 8, 7, 6, 5, 4, 3, 2};
    const auto chosen = ShareDesk::seating_of(
        2, controllers::ControllerKind::dualsense, account);
    assert(chosen &&
           chosen->controller == controllers::ControllerKind::dualsense);
    assert(chosen->as == chiaki_bridge::AccountIds::account_of(account));
    assert(chosen->preferred == controllers::SeatNumber::create(2));
    const auto plain =
        ShareDesk::seating_of(0, controllers::ControllerKind::dualshock4, {});
    assert(plain &&
           plain->controller == controllers::ControllerKind::dualshock4 &&
           !plain->as && !plain->preferred);
    const auto unset = ShareDesk::seating_of(
        1, controllers::ControllerKind::console_default, {});
    assert(unset &&
           unset->controller == controllers::ControllerKind::console_default);
    assert(
        !ShareDesk::seating_of(4, controllers::ControllerKind::dualsense, {}));
    assert(!ShareDesk::seating_of(1, controllers::ControllerKind::dualsense,
                                  chiaki_bridge::Bytes{1, 2, 3}));
    chiaki_bridge_testing::RecordingListener heard;
    const auto stream = chiaki_bridge::Stream::open(heard);
    const chiaki_bridge::Bytes guest(libchiaking::kakusan::GuestId::size, 0);
    assert(stream
               ->give_seat(guest, 2, controllers::ControllerKind::dualsense,
                           account)
               .refusal() == chiaki_bridge::KakusanCommandRefusal::not_armed);
    assert(stream
               ->give_seat(chiaki_bridge::Bytes{1}, 2,
                           controllers::ControllerKind::dualsense, account)
               .decline() ==
           libchiaking::kakusan::Refusal::Kind::invalid_argument);
  }
#endif

  static void
  a_controller_sample_reaches_the_core_with_its_touches_and_motion() {
    chiaki_bridge::ControllerSample input{};
    input.buttons = 0x4000;
    input.l2 = 9;
    input.right_y = -12;
    input.first_touch =
        chiaki_bridge::TouchSample{.id = 0x85, .x = 100, .y = 200};
    input.motion = chiaki_bridge::ControllerMotion{};
    input.motion->gyro_z = 3;
    input.motion->orient_w = 0.5F;
    input.trigger_states = chiaki_bridge::TriggerStates{.left = 4, .right = 5};
    const auto sample = chiaki_bridge::StreamSession::sample_of(input);
    assert(sample.buttons == 0x4000 && sample.l2 == 9 && sample.right_y == -12);
    assert(sample.touches[0].id == 5 && sample.touches[0].x == 100 &&
           sample.touches[0].y == 200);
    assert(sample.touches[1].id == -1);
    assert(sample.gyro_z == 3 && sample.orient_w == 0.5F);
    assert(sample.trigger_states ==
           (std::array<std::uint8_t, 2>{std::uint8_t{4}, std::uint8_t{5}}));
    const auto resting = chiaki_bridge::StreamSession::sample_of({});
    assert(resting.touches[0].id == -1 && resting.accel_y == 1.0F &&
           resting.orient_w == 1.0F && !resting.trigger_states);
  }

  static auto secret_names(const std::filesystem::path& header)
      -> std::set<std::string> {
    std::ifstream file{header};
    assert(file.good());
    const std::string text{std::istreambuf_iterator<char>{file},
                           std::istreambuf_iterator<char>{}};
    const std::regex name{
        "[A-Za-z_0-9]*(npsso|token|refresh|seed|passcode|password|secret|"
        "bearer)[A-Za-z_0-9]*|"
        "[A-Za-z_0-9]*_key\\b",
        std::regex::icase};
    std::set<std::string> names;
    for (std::sregex_iterator found{text.begin(), text.end(), name};
         found != std::sregex_iterator{}; ++found) {
      const auto word = found->str();
      if (std::ranges::any_of(word, [](unsigned char letter) {
            return std::islower(letter) != 0;
          })) {
        names.insert(word);
      }
    }
    return names;
  }

  static auto installed(
      std::string id, std::string concept_id,
      std::optional<libchiaking::consoles::InstalledTitle::LastUse> used)
      -> libchiaking::consoles::InstalledTitle {
    auto title = libchiaking::consoles::InstalledTitle::create(
        {.title_id = id,
         .start_id = id,
         .name = "Game " + id,
         .cover_url = "https://image.api.playstation.com/cover.png",
         .platform = libchiaking::consoles::Generation::ps5,
         .last_used = used,
         .recently_played = true,
         .concept_id = std::move(concept_id)});
    assert(title);
    return *title;
  }

  static void each_console_carries_its_own_recently_played_order_and_times() {
    using libchiaking::consoles::InstalledTitle;
    using Known = InstalledTitle::LastUse::Known;
    using Moment = std::chrono::system_clock::time_point;
    const std::array<std::uint8_t, libchiaking::consoles::HardwareId::size>
        living{0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6};
    const std::array<std::uint8_t, libchiaking::consoles::HardwareId::size>
        bedroom{0x11, 0x22, 0x33, 0x44, 0x55, 0x66};
    const auto first = chiaki_bridge::ConsoleIds::hardware_of(living.data());
    const auto second = chiaki_bridge::ConsoleIds::hardware_of(bedroom.data());
    assert(first && second);
    const std::string shared = "PPSA01234_00";
    const std::string other = "PPSA05678_00";
    const InstalledTitle::LastUse here{
        Moment{std::chrono::milliseconds{1'760'000'000'000}},
        Known::on_this_console};
    const InstalledTitle::LastUse earlier{
        Moment{std::chrono::milliseconds{1'750'000'000'000}},
        Known::on_this_console};
    const InstalledTitle::LastUse account{
        Moment{std::chrono::milliseconds{1'740'000'000'000}},
        Known::on_the_account};
    const std::vector<InstalledTitle> on_living{
        installed(shared, "10000001", here),
        installed(other, "10000002", earlier)};
    const std::vector<InstalledTitle> on_bedroom{
        installed(other, "10000002", here),
        installed(shared, "10000001", account),
        installed("PPSA09999_00", "", std::nullopt)};
    using chiaki_bridge::ConsoleTitlesBridge;
    const auto first_shelf = ConsoleTitlesBridge::shelf_of(*first, on_living);
    const auto second_shelf =
        ConsoleTitlesBridge::shelf_of(*second, on_bedroom);
    const auto ids = [](const chiaki_bridge::ConsoleShelf& shelf) {
      std::vector<std::string> titles;
      for (const auto& title : shelf.titles) {
        titles.push_back(title.title_id);
      }
      return titles;
    };
    assert((first_shelf.hardware_id ==
            chiaki_bridge::Bytes(living.begin(), living.end())));
    assert((second_shelf.hardware_id ==
            chiaki_bridge::Bytes(bedroom.begin(), bedroom.end())));
    assert((ids(first_shelf) == std::vector<std::string>{shared, other}));
    assert((ids(second_shelf) ==
            std::vector<std::string>{other, shared, "PPSA09999_00"}));
    assert(first_shelf.titles[0].last_used_ms == 1'760'000'000'000);
    assert(first_shelf.titles[1].last_used_ms == 1'750'000'000'000);
    assert(second_shelf.titles[1].last_used_ms == 1'740'000'000'000);
    assert(!second_shelf.titles[2].last_used_ms);
    assert(first_shelf.titles[0].last_use_known == Known::on_this_console);
    assert(first_shelf.titles[1].last_use_known == Known::on_this_console);
    assert(second_shelf.titles[1].last_use_known == Known::on_the_account);
    assert(!second_shelf.titles[2].last_use_known);
    assert(second_shelf.titles[0].concept_id == "10000002");
    assert(second_shelf.titles[1].concept_id == "10000001");
    assert(second_shelf.titles[2].concept_id.empty());
    assert(ConsoleTitlesBridge::shelf_of(*first, {}).titles.empty());
  }

  static void the_c_headers_left_in_the_bridge_name_no_secrets() {
    std::size_t seen = 0;
    for (const auto& entry :
         std::filesystem::directory_iterator{NX_BRIDGE_DIRECTORY}) {
      if (entry.path().extension() == ".h") {
        ++seen;
        assert(secret_names(entry.path()).empty());
      }
    }
    assert(seen > 0);
  }

  static void timestamps_keep_milliseconds_and_truncate_finer_times() {
    using std::chrono::microseconds;
    using std::chrono::milliseconds;
    using std::chrono::sys_time;
    using Timestamp = chiaki_bridge::Timestamp;
    assert(Timestamp::milliseconds_of(sys_time<milliseconds>{
               milliseconds{1'760'000'000'250}}) == 1'760'000'000'250);
    assert(Timestamp::milliseconds_of(sys_time<milliseconds>{}) == 0);
    assert(Timestamp::milliseconds_of(
               sys_time<milliseconds>{milliseconds{-1}}) == -1);
    assert(Timestamp::milliseconds_of(sys_time<milliseconds>::max()) ==
           milliseconds::max().count());
    assert(Timestamp::milliseconds_of(
               sys_time<microseconds>{microseconds{1'999}}) == 1);
    assert(Timestamp::milliseconds_of(
               sys_time<microseconds>{microseconds{-1'999}}) == -1);
    assert(Timestamp::milliseconds_of(Timestamp::moment_of(-1'500)) == -1'500);
    assert(Timestamp::moment_of(1'760'000'000'250).time_since_epoch() ==
           milliseconds{1'760'000'000'250});
  }
};

}  // namespace

int main() {
  BridgeFacts::link_statistics_follow_their_present_flags();
  BridgeFacts::each_target_launches_with_its_own_version_and_negotiation();
#if CHIAKI_KAKUSAN
  BridgeFacts::a_guests_seat_carries_the_chosen_account_controller_and_seat();
#endif
  BridgeFacts::stream_media_choices_reach_every_target();
  BridgeFacts::
      a_controller_sample_reaches_the_core_with_its_touches_and_motion();
  BridgeFacts::console_intensity_is_reported_and_local_rumble_stays_raw();
  BridgeFacts::the_c_headers_left_in_the_bridge_name_no_secrets();
  BridgeFacts::each_console_carries_its_own_recently_played_order_and_times();
  BridgeFacts::timestamps_keep_milliseconds_and_truncate_finer_times();
  return 0;
}
