#include "stream_session.hpp"

#include <algorithm>
#include <chrono>
#include <format>
#include <limits>
#include <utility>

#include "account_ids.hpp"
#include "boundary.hpp"
#include "cleared_launch.hpp"

using libchiaking::catalog::ServiceGeneration;
using libchiaking::consoles::Generation;
using libchiaking::controllers::ControllerFeedback;
using libchiaking::controllers::ControllerKind;
using libchiaking::controllers::ControllerState;
using libchiaking::controllers::SeatNumber;
using libchiaking::media::AudioResult;
using libchiaking::media::AudioUnit;
using libchiaking::media::AudioVerdict;
using libchiaking::media::VideoCodec;
using libchiaking::media::VideoResult;
using libchiaking::platform::LogSeverity;
using libchiaking::play::AccessCode;
using libchiaking::play::DatacenterName;
using libchiaking::play::DatacenterPreference;
using libchiaking::play::DeveloperTuning;
using libchiaking::play::InternetOptions;
using libchiaking::play::LaunchProgress;
using libchiaking::play::LaunchRefused;
using libchiaking::play::Leave;
using libchiaking::play::LoginPin;
using libchiaking::play::Microphone;
using libchiaking::play::PictureRequest;
using libchiaking::play::Preferences;
using libchiaking::play::SeatRefusal;
using libchiaking::play::Session;
using libchiaking::play::SessionState;
using libchiaking::play::SoundRequest;
using libchiaking::play::StartRefusal;

auto chiaki_bridge::TakionSetup::of(StreamTarget target) const noexcept
    -> TakionTuning {
  switch (target) {
    case StreamTarget::local_ps4:
      return local_ps4;
    case StreamTarget::local_ps5:
      return local_ps5;
    case StreamTarget::ps_now:
      return ps_now;
    case StreamTarget::ps_cloud:
      break;
  }
  return ps_cloud;
}

auto chiaki_bridge::Stream::open(StreamListener& listener)
    -> std::unique_ptr<Stream> {
  return std::make_unique<chiaki_bridge::StreamSession>(listener);
}

namespace chiaki_bridge {

StreamSession::StreamSession(StreamListener& listener)
    : listener_(listener),
      audio_(log_),
      feedback_(listener),
      picture_(PictureRequest::create(1080, 60, 30000, VideoCodec::h264)
                   .value_or(PictureRequest{})) {}

StreamSession::~StreamSession() {
#if CHIAKI_KAKUSAN
  shared_.stop_sharing();
#endif
  published_session_.store(nullptr, std::memory_order_release);
  {
    const std::lock_guard lock(mutex_);
    session_.reset();
  }
  log_.journal()->retain();
  if (log_owner_) {
    log_owner_->stream_released_log();
  }
}

auto StreamSession::sample_of(const ControllerSample& input) noexcept
    -> ControllerState {
  ControllerState sample;
  sample.buttons = input.buttons;
  sample.l2 = input.l2;
  sample.r2 = input.r2;
  sample.left_x = input.left_x;
  sample.left_y = input.left_y;
  sample.right_x = input.right_x;
  sample.right_y = input.right_y;
  const auto place = [&sample](std::size_t index,
                               const std::optional<TouchSample>& touch) {
    if (touch) {
      sample.touches[index] = {static_cast<std::int8_t>(touch->id & 0x7f),
                               touch->x, touch->y};
    }
  };
  place(0, input.first_touch);
  place(1, input.second_touch);
  if (const auto& motion = input.motion) {
    sample.gyro_x = motion->gyro_x;
    sample.gyro_y = motion->gyro_y;
    sample.gyro_z = motion->gyro_z;
    sample.accel_x = motion->accel_x;
    sample.accel_y = motion->accel_y;
    sample.accel_z = motion->accel_z;
    sample.orient_x = motion->orient_x;
    sample.orient_y = motion->orient_y;
    sample.orient_z = motion->orient_z;
    sample.orient_w = motion->orient_w;
  }
  if (const auto& triggers = input.trigger_states) {
    sample.trigger_states = {triggers->left, triggers->right};
  }
  return sample;
}

auto StreamSession::refused(StreamRefusal refusal) -> Outcome {
  return Outcome::refused(refusal);
}

auto StreamSession::refused(StartRefusal::Kind kind) -> Outcome {
  return Outcome::start_refused(
      StartRefusalFacts{kind, std::nullopt, std::nullopt, 0});
}

auto StreamSession::launch_facts_of(const LaunchRefused& refused)
    -> LaunchRefusalFacts {
  LaunchRefusalFacts facts;
  facts.kind = refused.kind();
  facts.http_status = refused.http_status();
  if (const auto* clearance = refused.clearance()) {
    ClearanceFacts cleared;
    cleared.kind = clearance->kind();
    cleared.tier_held = clearance->tier_held();
    if (const auto time = clearance->time()) {
      cleared.time_ms = Timestamp::milliseconds_of(*time);
    }
    cleared.notice = clearance->notice();
    if (const auto offer = clearance->library_offer()) {
      cleared.library_sku = offer->sku_id;
    }
    if (const auto cause = clearance->cause()) {
      cleared.needs_sign_in = cause->needs_sign_in();
      if (cause->http_status() != 0) {
        facts.http_status = cause->http_status();
      }
    }
    facts.clearance = std::move(cleared);
  }
  facts.upgrade_url = refused.upgrade_url();
  facts.display_price = refused.display_price();
  facts.service_refusal = refused.ps_refusal();
  if (const auto best = refused.best_round_trip()) {
    facts.best_round_trip_ms = best->count();
  }
  if (const auto* datacenter = refused.datacenter()) {
    facts.datacenter = datacenter->text();
  }
  facts.no_server = refused.no_server();
  return facts;
}

auto StreamSession::outcome_of(const StartRefusal& refusal) -> Outcome {
  StartRefusalFacts facts{refusal.kind(), std::nullopt, std::nullopt, 0};
  facts.unreachable = refusal.unreachable();
  if (const auto& launch = refusal.launch()) {
    facts.launch_refused = launch_facts_of(*launch);
    facts.http_status = facts.launch_refused->http_status;
  }
  return Outcome::start_refused(std::move(facts));
}

auto StreamSession::outcome_of(const libchiaking::play::Outcome& ended)
    -> Outcome {
  StreamEndFacts facts{};
  facts.ending = ended.ending();
  facts.left = ended.was_left();
  facts.cause = ended.cause();
  if (const auto* reason = ended.reason()) {
    facts.step = reason->step();
    facts.console_reason = reason->console_reason();
    facts.http_status = reason->http_status();
    facts.action_url = reason->action_url();
  }
  if (const auto& quit = ended.quit()) {
    facts.quit = quit->reason();
  }
  if (const auto& fault = ended.media_fault()) {
    facts.media_failure = fault->kind;
  }
  facts.rest = ended.rest();
  if (const auto* launch = ended.launch_refused()) {
    facts.launch_refused = launch_facts_of(*launch);
    if (facts.launch_refused->http_status != 0) {
      facts.http_status = facts.launch_refused->http_status;
    }
  }
  facts.diagnostics = ended.trace();
  return Outcome::ended(std::move(facts));
}

auto StreamSession::link_of(const libchiaking::play::LinkStatistics& link)
    -> std::optional<LinkFacts> {
  if (!link.available) {
    return std::nullopt;
  }
  LinkFacts facts;
  facts.video_units = link.video_units;
  facts.rejected_packets = link.rejected_packets;
  facts.crypto_rejections = link.crypto_rejections;
  facts.assembled_video = link.assembled_video;
  facts.dependency_rejections = link.dependency_rejections;
  facts.assembly_rejections = link.assembly_rejections;
  facts.fec_repaired_frames = link.fec_repaired_frames;
  facts.video_stale = link.video_stale;
  facts.video_metadata = link.video_metadata;
  facts.video_duplicate = link.video_duplicate;
  facts.video_invalid = link.video_invalid;
  facts.reorder_skipped = link.reorder_skipped;
  facts.reorder_dropped = link.reorder_dropped;
  facts.dropped_posts = link.dropped_posts;
  facts.send_dropped = link.send_dropped;
  if (link.round_trip.present) {
    facts.round_trip =
        RoundTripFacts{.smoothed_us = link.round_trip.smoothed_us,
                       .variation_us = link.round_trip.variation_us,
                       .samples = link.round_trip.samples,
                       .p99_us = link.round_trip.p99_us,
                       .recent_max_us = link.round_trip.recent_max_us};
  }
  if (link.reception.present) {
    facts.reception = ReceptionFacts{.jitter_us = link.reception.jitter_us,
                                     .received = link.reception.received,
                                     .lost = link.reception.lost,
                                     .loss_ratio = link.reception.loss_ratio};
  }
  if (link.video_metrics.present) {
    VideoMetricFacts metrics{
        .throughput_bps = link.video_metrics.throughput_bps,
        .loss_ratio = link.video_metrics.loss_ratio,
        .receive_interval_us = link.video_metrics.receive_interval_us,
        .transfer_time_us = link.video_metrics.transfer_time_us,
        .reports_sent = std::nullopt};
    if (link.video_metrics.reports_present) {
      metrics.reports_sent = link.video_metrics.reports_sent;
    }
    facts.video_metrics = metrics;
  }
  if (link.service_marks.present) {
    ServiceMarkFacts marks;
    marks.packets = link.service_marks.packets;
    if (link.service_marks.last_present) {
      marks.last_dscp = link.service_marks.last_dscp;
      marks.last_ecn = link.service_marks.last_ecn;
    }
    facts.service_marks = marks;
  }
  if (link.server.present) {
    facts.server =
        ServerFacts{.available_down_kbps = link.server.available_down_kbps,
                    .used_down_kbps = link.server.used_down_kbps,
                    .used_up_kbps = link.server.used_up_kbps,
                    .round_trip_ms = link.server.round_trip_ms,
                    .loss_percent = link.server.loss_percent,
                    .upstream_loss_percent = link.server.upstream_loss_percent,
                    .audio_channels = link.server.audio_channels,
                    .width = link.server.width,
                    .height = link.server.height,
                    .corrupt_frames = link.server.corrupt_frames};
  }
  return facts;
}

auto StreamSession::statistics_of(const libchiaking::play::Statistics& observed)
    -> StreamStatistics {
  StreamStatistics statistics;
  statistics.units = observed.video.units;
  statistics.bytes = observed.video.bytes;
  statistics.lost = observed.video.lost;
  statistics.recovered = observed.video.recovered;
  statistics.decoder_failures = observed.video.decoder_rejections;
  statistics.last_decoder_error = observed.video.last_decoder_error;
  statistics.keyframe_requests = observed.video.keyframe_requests;
  statistics.loop_errors = observed.loop_errors;
  statistics.link = link_of(observed.link);
  statistics.protocol_version = observed.protocol_version;
  return statistics;
}

auto StreamSession::session() const -> std::shared_ptr<Session> {
  const std::lock_guard lock(mutex_);
  return session_;
}

#if CHIAKI_KAKUSAN
auto StreamSession::visit() const noexcept
    -> libchiaking::kakusan::GuestVisit* {
  return shared_.visit();
}
#endif

auto StreamSession::unclaimed() const -> bool {
  const std::lock_guard lock(mutex_);
  return phase_ == Phase::created && !cancelled_;
}

auto StreamSession::decodes_video() const -> bool {
  return listener_.decodes_video();
}

auto StreamSession::accepting() const -> bool {
  if (const auto active = session()) {
    const auto state = active->state();
    return state == SessionState::connecting || state == SessionState::playing;
  }
  const std::lock_guard lock(mutex_);
  return phase_ == Phase::guest && !cancelled_;
}

auto StreamSession::claim() -> bool {
  const std::lock_guard lock(mutex_);
  if (phase_ != Phase::created || cancelled_) {
    return false;
  }
  phase_ = Phase::preparing;
  return true;
}

auto StreamSession::decline() -> Outcome {
  const std::lock_guard lock(mutex_);
  if (phase_ != Phase::created) {
    return Outcome::unrecorded();
  }
  StreamEndFacts left{};
  left.ending = libchiaking::play::Outcome::Ending::left;
  left.left = true;
  outcome_ = Outcome::ended(std::move(left));
  phase_ = Phase::finished;
  return outcome_;
}

auto StreamSession::result() const -> Outcome {
  const std::lock_guard lock(mutex_);
  if (!rest_refused_ || outcome_.kind() != Outcome::Kind::ended ||
      outcome_.rest() != libchiaking::play::RestOutcome::none) {
    return outcome_;
  }
  auto finished = outcome_.ending();
  finished.rest = libchiaking::play::RestOutcome::refused;
  return Outcome::ended(std::move(finished));
}

auto StreamSession::begin_visit() -> bool {
  const std::lock_guard lock(mutex_);
  phase_ = Phase::guest;
  return !cancelled_;
}

void StreamSession::end_visit() {
  audio_.stop();
  const std::lock_guard lock(mutex_);
  phase_ = Phase::finished;
}

auto StreamSession::set_picture(const PictureSetup& picture) -> bool {
  auto request = PictureRequest::create(picture.height, picture.fps,
                                        picture.bitrate_kbps, picture.codec);
  if (!request) {
    return false;
  }
  if (picture.measure_bandwidth) {
    request = request->measuring_bandwidth();
  }
  if (picture.stable_quality) {
    request = request->favouring(libchiaking::play::CloudQuality::stable);
  }
  const std::lock_guard lock(mutex_);
  if (phase_ != Phase::created || cancelled_) {
    return false;
  }
  picture_ = *request;
  return true;
}

void StreamSession::set_takion(const TakionSetup& takion) {
  const std::lock_guard lock(mutex_);
  takion_ = takion;
}

void StreamSession::set_port_guessing(bool forced, std::uint32_t guesses) {
  const auto options = InternetOptions::create(forced, guesses);
  const std::lock_guard lock(mutex_);
  internet_ = options.value_or(InternetOptions{});
}

void StreamSession::set_accessibility(
    libchiaking::play::AccessibilityRequest accessibility) {
  const std::lock_guard lock(mutex_);
  accessibility_ = accessibility;
}

void StreamSession::update_accessibility(
    libchiaking::play::AccessibilityRequest accessibility) {
  {
    const std::lock_guard lock(mutex_);
    if (accessibility_ == accessibility) {
      return;
    }
    accessibility_ = accessibility;
  }
  const auto active = session();
  if (!active) {
    return;
  }
  const auto requested = active->set_accessibility(accessibility);
  if (!requested &&
      requested.error() != libchiaking::play::InputRefusal::wrong_route) {
    log_.info(std::format("accessibility update refused: {}",
                          refusal_name(requested.error())));
  }
}

void StreamSession::set_console_handover(
    libchiaking::play::ConsoleHandover handover) {
  const std::lock_guard lock(mutex_);
  handover_ = handover;
}

void StreamSession::set_reconnect_after_drop(bool enabled) {
  const std::lock_guard lock(mutex_);
  reconnect_after_drop_ = enabled;
}

void StreamSession::set_media_off(MediaOff media) {
  const std::lock_guard lock(mutex_);
  media_off_ = media;
}

void StreamSession::set_api_capture(bool enabled) {
  api_capture_ = enabled;
  if (const auto core = Opened::shared()) {
    core->platform().api_capture().enable(enabled);
  }
}

void StreamSession::set_text_entry(bool enabled) {
  const std::lock_guard lock(mutex_);
  if (phase_ == Phase::created) {
    text_entry_ = enabled;
  }
}

#if CHIAKI_KAKUSAN
auto StreamSession::arm_kakusan(const KakusanHosting& hosting)
    -> KakusanCommandOutcome {
  return Boundary::fenced(
      ShareDesk::refused(libchiaking::kakusan::Refusal::Kind::internal),
      [&] { return shared_.arm_host(hosting); });
}
#else
auto StreamSession::arm_kakusan(const KakusanHosting&)
    -> KakusanCommandOutcome {
  return KakusanCommandOutcome::declined(
      libchiaking::kakusan::Refusal::Kind::cannot_be_shared);
}
#endif

void StreamSession::route_haptics(HapticDelivery delivery) {
  feedback_.route(delivery);
}

void StreamSession::set_audio_gain(float gain) { audio_.set_gain(gain); }

void StreamSession::set_voice_gain(float gain) { audio_.set_voice_gain(gain); }

void StreamSession::set_audio_buffer(std::chrono::milliseconds buffer) {
  audio_.set_buffer(static_cast<std::uint32_t>(std::clamp<std::int64_t>(
      buffer.count(), 0, std::numeric_limits<std::uint32_t>::max())));
}

void StreamSession::set_audio_output(std::string_view device) {
  Boundary::fenced(false, [&] {
    audio_.set_output(device);
    return true;
  });
}

void StreamSession::set_audio_spatial(bool enabled) {
  audio_.set_spatial(enabled);
}

auto StreamSession::request_audio_channels(std::uint32_t channels) -> bool {
  return audio_.request_channels(channels);
}

void StreamSession::request_controller_speaker(bool enabled) {
  audio_.request_controller_speaker(enabled);
}

void StreamSession::route_controller_speaker(bool to_listener) {
  speaker_to_listener_ = to_listener;
}

void StreamSession::journal_sessions() {
  if (!log_owner_) {
    log_owner_ = core_;
    log_owner_->stream_follows_log();
  }
  log_.journal()->follow(core_->platform().log(),
                         &core_->platform().api_capture());
  core_->play().journal_sessions_in(log_.journal());
}

void StreamSession::set_audio_3d(bool enabled) {
  audio_3d_ = enabled;
  const auto active = session();
  log_.info(std::format(
      "audio 3d {} (session {})", enabled ? "on" : "off",
      active != nullptr ? "active, passed to it" : "not started yet"));
  if (active != nullptr) {
    request_audio_3d(*active, enabled);
  }
}

void StreamSession::request_audio_3d(Session& active, bool enabled) {
  if (const auto requested = active.set_audio_3d(enabled); !requested) {
    log_.info(std::format("audio 3d {} refused: {}", enabled ? "on" : "off",
                          refusal_name(requested.error())));
  }
}

auto StreamSession::system_ui_name(Session::SystemUi state)
    -> std::string_view {
  switch (state) {
    case Session::SystemUi::game:
      return "game";
    case Session::SystemUi::overlaid:
      return "overlaid";
    case Session::SystemUi::background:
      return "background";
  }
  return "game";
}

void StreamSession::set_system_ui(Session::SystemUi state) {
  system_ui_ = state;
  if (const auto active = session()) {
    request_system_ui(*active, state);
  }
}

void StreamSession::request_system_ui(Session& active,
                                      Session::SystemUi state) {
  const auto requested = active.set_system_ui(state);
  if (!requested &&
      requested.error() != libchiaking::play::InputRefusal::wrong_route) {
    log_.info(std::format("system UI state {} refused: {}",
                          system_ui_name(state),
                          refusal_name(requested.error())));
  }
}

auto StreamSession::press_create(Session::CreatePress press) -> bool {
  const auto active = session();
  if (!active) {
    return false;
  }
  const auto pressed = active->press_create(press);
  if (!pressed) {
    log_.info(
        std::format("Create press refused: {}", refusal_name(pressed.error())));
  }
  return pressed.has_value();
}

auto StreamSession::join_invitation(const std::string& invitation_id,
                                    const std::string& session_id) -> bool {
  const auto active = session();
  if (!active) {
    return false;
  }
  const auto joined = active->join_invitation(invitation_id, session_id);
  if (!joined) {
    log_.info(std::format("Game invitation refused: {}",
                          refusal_name(joined.error())));
  }
  return joined.has_value();
}

auto StreamSession::open_saved_data() -> bool {
  const auto active = session();
  if (!active) {
    return false;
  }
  const auto opened = active->open_saved_data();
  if (!opened) {
    log_.info(std::format("Saved data management refused: {}",
                          refusal_name(opened.error())));
  }
  return opened.has_value();
}

auto StreamSession::preferences(StreamTarget target, SoundRequest sound)
    -> std::optional<Preferences> {
  Preferences preferences;
  std::optional<DeveloperTuning> developer;
  {
    const std::lock_guard lock(mutex_);
    preferences.picture = picture_;
    preferences.internet = internet_;
    preferences.accessibility = accessibility_;
    preferences.handover = handover_;
    preferences.reconnect_after_drop = reconnect_after_drop_;
    preferences.controls = libchiaking::play::ControlsRequest{
        libchiaking::play::ControllerChoice::console_default,
        libchiaking::play::FeedbackStyle::standard, text_entry_};
    developer = developer_of(takion_.of(target), media_off_);
  }
  preferences.sound = sound;
  if (!developer) {
    return std::nullopt;
  }
  preferences.developer = *developer;
  return preferences;
}

auto StreamSession::developer_of(const TakionTuning& takion, MediaOff media)
    -> std::optional<DeveloperTuning> {
  DeveloperTuning::Facts tuning;
  if (takion.version != 0) {
    tuning.protocol_version = takion.version;
  }
  tuning.negotiate_protocol_version = takion.negotiate;
  tuning.disable_audio = media.audio;
  tuning.disable_video = media.video;
  return DeveloperTuning::create(tuning);
}

auto StreamSession::refuse(Outcome refused) -> Outcome {
  const std::lock_guard lock(mutex_);
  outcome_ = std::move(refused);
  phase_ = Phase::finished;
  return outcome_;
}

void StreamSession::conclude(const libchiaking::play::Outcome& ended) {
  auto summary = outcome_of(ended);
  const std::lock_guard lock(mutex_);
  outcome_ = std::move(summary);
  phase_ = Phase::finished;
}

auto StreamSession::attend(Started started) -> Outcome {
  if (!started) {
    return refuse(outcome_of(started.error()));
  }
  const auto active = std::move(started.value());
  bool cancelled = false;
  {
    const std::lock_guard lock(mutex_);
    session_ = active;
    cancelled = cancelled_;
  }
  published_session_.store(active.get(), std::memory_order_release);
  const bool audio_3d = audio_3d_;
  log_.info(
      std::format("audio 3d {} at session start", audio_3d ? "on" : "off"));
  if (audio_3d) {
    request_audio_3d(*active, true);
  }
  if (const auto state = system_ui_.load(); state != Session::SystemUi::game) {
    request_system_ui(*active, state);
  }
  if (cancelled) {
    static_cast<void>(active->leave());
  }
#if CHIAKI_KAKUSAN
  shared_.share_when_playing(*active);
#endif
  const auto& ended = active->wait_until_ended();
#if CHIAKI_KAKUSAN
  shared_.stop_sharing();
#endif
  conclude(ended);
  audio_.stop();
  return result();
}

auto StreamSession::run_console(const Bytes& account_id,
                                const Bytes& hardware_id,
                                libchiaking::consoles::Route route) -> Outcome {
  return Boundary::fenced(Outcome::unrecorded(), [&] {
    return start_console(account_id, hardware_id, route);
  });
}

auto StreamSession::start_console(const Bytes& account_id,
                                  const Bytes& hardware_id,
                                  libchiaking::consoles::Route route)
    -> Outcome {
  if (!claim()) {
    return decline();
  }
  core_ = Opened::shared();
  if (!core_) {
    return refuse(refused(StreamRefusal::core_closed));
  }
  auto player = core_->user(account_id);
  if (!player) {
    return refuse(refused(StreamRefusal::unknown_user));
  }
  auto console = core_->console(hardware_id);
  if (!console) {
    return refuse(refused(StreamRefusal::unknown_console));
  }
  if (!decodes_video()) {
    return refuse(refused(StreamRefusal::no_decoder));
  }
  const bool ps5 = console->generation() == Generation::ps5;
  const auto sound =
      audio_.negotiate(audio_.requested().on_console(console->generation()),
                       ps5 ? "PS5" : "PS4");
  const auto chosen = preferences(
      ps5 ? StreamTarget::local_ps5 : StreamTarget::local_ps4, sound);
  if (!chosen) {
    return refuse(refused(StartRefusal::Kind::invalid_preferences));
  }
  journal_sessions();
  core_->platform().api_capture().enable(api_capture_);
  if (route == libchiaking::consoles::Route::internet) {
    log_.info(std::format(
        "core remote port guessing {} with {} guesses",
        chosen->internet.forces_port_guessing() ? "forced" : "automatic",
        chosen->internet.port_guesses()));
  }
  return attend(console->start(std::move(player), *chosen, *this, *this, route,
                               start_stop_.token()));
}

auto StreamSession::datacenter_of(const DatacenterRequest& request)
    -> std::optional<DatacenterPreference> {
  if (request.ask_within) {
    return DatacenterPreference::ask_at_launch(*request.ask_within);
  }
  if (request.name.empty()) {
    return DatacenterPreference{};
  }
  auto name = DatacenterName::parse(request.name);
  if (!name) {
    return std::nullopt;
  }
  return DatacenterPreference::named(std::move(*name));
}

auto StreamSession::run_cloud(const Bytes& account_id, const CloudStart& start)
    -> Outcome {
  return Boundary::fenced(Outcome::unrecorded(),
                          [&] { return start_cloud(account_id, start); });
}

auto StreamSession::start_cloud(const Bytes& account_id,
                                const CloudStart& start) -> Outcome {
  if (!claim()) {
    return decline();
  }
  core_ = Opened::shared();
  if (!core_) {
    return refuse(refused(StreamRefusal::core_closed));
  }
  auto player = core_->user(account_id);
  if (!player) {
    return refuse(refused(StreamRefusal::unknown_user));
  }
  const auto product = libchiaking::catalog::ProductId::parse(start.product_id);
  if (!product) {
    return refuse(refused(StreamRefusal::invalid_title));
  }
  if (!decodes_video()) {
    return refuse(refused(StreamRefusal::no_decoder));
  }
  auto datacenter = datacenter_of(start.datacenter);
  if (!datacenter) {
    return refuse(refused(StartRefusal::Kind::invalid_preferences));
  }
  const bool ps5 = product->platform() == libchiaking::catalog::Platform::ps5;
  const auto service =
      ps5 ? ServiceGeneration::ps5_cloud : ServiceGeneration::old_service;
  const auto sound = audio_.negotiate(audio_.requested().on_cloud(service),
                                      ps5 ? "PS5 cloud" : "PS Plus classics");
  const auto chosen =
      preferences(ps5 ? StreamTarget::ps_cloud : StreamTarget::ps_now, sound);
  if (!chosen) {
    return refuse(refused(StartRefusal::Kind::invalid_preferences));
  }
  journal_sessions();
  core_->platform().api_capture().enable(api_capture_);
  return attend(core_->play().start_on_cloud(
      std::move(player), *product, *chosen, std::move(*datacenter), *this,
      *this, ClearedLaunch::of(start.cleared)));
}

auto StreamSession::run_scripted(const Bytes& account_id,
                                 libchiaking::play::testing::ScriptedLink& link,
                                 libchiaking::play::Where where) -> Outcome {
  if (!claim()) {
    return decline();
  }
  core_ = Opened::shared();
  if (!core_) {
    return refuse(refused(StreamRefusal::core_closed));
  }
  auto player = core_->user(account_id);
  if (!player) {
    return refuse(refused(StreamRefusal::unknown_user));
  }
  if (!decodes_video()) {
    return refuse(refused(StreamRefusal::no_decoder));
  }
  const auto chosen = preferences(StreamTarget::local_ps5, audio_.requested());
  if (!chosen) {
    return refuse(refused(StartRefusal::Kind::invalid_preferences));
  }
  journal_sessions();
  return attend(core_->play().start_scripted(std::move(player), where, link,
                                             *chosen, *this, *this));
}

#if CHIAKI_KAKUSAN
auto StreamSession::join_kakusan(std::string_view invitation,
                                 bool force_port_guessing) -> GuestOutcome {
  return Boundary::fenced(
      GuestOutcome::declined(libchiaking::kakusan::Refusal::Kind::internal),
      [&] { return shared_.run_guest(invitation, force_port_guessing); });
}
#else
auto StreamSession::join_kakusan(std::string_view, bool) -> GuestOutcome {
  return GuestOutcome::declined(libchiaking::kakusan::Refusal::Kind::internal);
}
#endif

void StreamSession::cancel() {
  std::shared_ptr<Session> active;
  {
    const std::lock_guard lock(mutex_);
    cancelled_ = true;
    active = session_;
  }
  static_cast<void>(start_stop_.request_stop());
  if (active) {
    static_cast<void>(active->leave());
  }
#if CHIAKI_KAKUSAN
  if (auto* visiting = visit()) {
    visiting->cancel();
  }
#endif
}

void StreamSession::stop_for_sleep() {
  if (const auto active = session()) {
    active->leave_for_host_sleep(false);
    return;
  }
  cancel();
}

auto StreamSession::stop_with_rest(bool for_sleep) -> bool {
  if (const auto active = session()) {
    if (for_sleep) {
      active->leave_for_host_sleep(true);
      return true;
    }
    return active->leave(Leave::rest_console);
  }
  {
    const std::lock_guard lock(mutex_);
    rest_refused_ = true;
  }
  cancel();
  return false;
}

auto StreamSession::go_home() -> bool {
  const auto active = session();
  return active && active->go_home().has_value();
}

auto StreamSession::submit_login_pin(std::string_view pin) -> bool {
  const auto active = session();
  auto code = AccessCode::parse(pin);
  return active && code &&
         active->login_pin().submit(std::move(*code)).has_value();
}

auto StreamSession::await_login_pin() -> bool {
  const auto active = session();
  if (!active) {
    return true;
  }
  const auto patience = accepting()
                            ? std::chrono::milliseconds{LoginPin::default_await}
                            : std::chrono::milliseconds{};
  return active->login_pin().await(patience) == LoginPin::Verdict::accepted;
}

auto StreamSession::submit_seat_passcode(std::uint8_t pad, std::string_view pin)
    -> bool {
  const auto active = session();
  const auto seat = SeatNumber::create(pad);
  auto code = AccessCode::parse(pin);
  return active && seat && code &&
         active->seats().enter_passcode(*seat, std::move(*code)).has_value();
}

auto StreamSession::seat_refusal_name(SeatRefusal::Kind kind) noexcept
    -> std::string_view {
  switch (kind) {
    case SeatRefusal::Kind::not_sent:
      return "not sent";
    case SeatRefusal::Kind::refused_by_console:
      return "refused by the console";
    case SeatRefusal::Kind::passcode_attempts_used:
      return "passcode attempts used";
    case SeatRefusal::Kind::timed_out:
      return "timed out";
    case SeatRefusal::Kind::account_not_on_console:
      return "account not on the console";
    case SeatRefusal::Kind::no_free_seat:
      return "no free seat";
  }
  return "unknown";
}

auto StreamSession::refusal_name(
    libchiaking::play::InputRefusal refusal) noexcept -> std::string_view {
  using libchiaking::play::InputRefusal;
  switch (refusal) {
    case InputRefusal::invalid:
      return "invalid";
    case InputRefusal::not_running:
      return "not running";
    case InputRefusal::wrong_route:
      return "wrong route";
    case InputRefusal::busy:
      return "busy";
    case InputRefusal::not_owner:
      return "not owner";
    case InputRefusal::not_ready:
      return "not ready";
  }
  return "unknown";
}

auto StreamSession::add_couch_player(std::uint8_t pad,
                                     ControllerKind controller,
                                     const Bytes& account_id) -> bool {
  const auto active = session();
  const auto seat = SeatNumber::create(pad);
  if (!active || !seat) {
    log_.warning(std::format("couch join refused: pad={} session={} seat={}",
                             pad, active != nullptr, seat.has_value()));
    return false;
  }
  const auto account = AccountIds::account_of(account_id);
  if (!account_id.empty() && !account) {
    log_.warning(
        std::format("couch join refused: pad={} account malformed", pad));
    return false;
  }
  if (const auto added = active->seats().add_player(*seat, controller, account);
      !added) {
    log_.warning(std::format("couch join refused: pad={} account={} reason={}",
                             pad, account.has_value(),
                             refusal_name(added.error())));
    return false;
  }
  feedback_.reset(*seat);
  return true;
}

auto StreamSession::remove_couch_player(std::uint8_t pad) -> bool {
  const auto active = session();
  const auto seat = SeatNumber::create(pad);
  if (!active || !seat || !active->seats().remove_player(*seat)) {
    return false;
  }
  feedback_.reset(*seat);
  return true;
}

auto StreamSession::set_keyboard_text(std::string_view text) -> bool {
  if (text.size() > libchiaking::play::ConsoleKeyboard::text_limit) {
    return false;
  }
  const auto active = session();
  return active && active->keyboard().set_text(text).has_value();
}

auto StreamSession::send_keyboard(std::uint8_t modifiers, std::uint8_t leds,
                                  std::span<const std::uint16_t> keys) -> bool {
  const auto state =
      libchiaking::play::KeyboardState::create(modifiers, leds, keys);
  const auto active = session();
  if (!state || !active) {
    return false;
  }
  const auto sent = active->send_keyboard(*state);
  if (!sent) {
    log_.info(std::format("keyboard refused: {}", refusal_name(sent.error())));
    return false;
  }
  ++keyboard_reports_;
  if (keyboard_reports_ == 1 || keyboard_reports_ % 20 == 0) {
    log_.info(std::format("keyboard reports sent: {} ({} keys held)",
                          keyboard_reports_, keys.size()));
  }
  return true;
}

auto StreamSession::close_keyboard(bool accept) -> bool {
  const auto active = session();
  if (!active) {
    return false;
  }
  auto& keyboard = active->keyboard();
  return (accept ? keyboard.accept() : keyboard.reject()).has_value();
}

auto StreamSession::connect_microphone(std::uint32_t request) -> bool {
  const auto active = session();
  return active && active->microphone().connect(request).has_value();
}

auto StreamSession::microphone_state(std::uint32_t request) const
    -> Microphone::ConnectState {
  const auto active = session();
  if (!active) {
    return Microphone::ConnectState::rejected;
  }
  const auto& uplink = active->microphone();
  const auto ticket = uplink.latest();
  if (!ticket || ticket->tag() != request) {
    return uplink.open() ? Microphone::ConnectState::pending
                         : Microphone::ConnectState::rejected;
  }
  return uplink.state(*ticket);
}

auto StreamSession::set_microphone_muted(bool muted) -> bool {
  const auto active = session();
  return active && active->microphone().set_muted(muted).has_value();
}

auto StreamSession::send_microphone(std::span<const std::uint8_t> frame)
    -> bool {
  const auto active = session();
  if (!active || frame.size() != Microphone::frame_size) {
    return false;
  }
  const auto bytes = std::as_bytes(frame).first<Microphone::frame_size>();
  return active->microphone().push(bytes).has_value();
}

auto StreamSession::choose_datacenter(std::string_view name) -> bool {
  const auto active = session();
  auto* launch = active ? active->launch() : nullptr;
  bool picked = false;
  if (launch != nullptr && name == DatacenterName::automatic) {
    picked = launch->choose_lowest_latency().has_value();
  } else if (launch != nullptr) {
    const auto datacenter = DatacenterName::parse(name);
    picked = datacenter && launch->choose_datacenter(*datacenter).has_value();
  }
  log_.write(picked ? LogSeverity::info : LogSeverity::warning,
             std::format("core cloud datacenter: launch pick {} {}", name,
                         picked ? "accepted" : "refused"));
  return picked;
}

auto StreamSession::send_controller(std::uint8_t pad,
                                    const ControllerSample& input) -> bool {
  const auto seat = SeatNumber::create(pad);
  if ((input.buttons & ~ControllerState::button_mask) != 0 || !seat) {
    return false;
  }
  const auto sample = sample_of(input);
  if (const auto active = session()) {
    return active->controllers().send(*seat, sample).has_value();
  }
#if CHIAKI_KAKUSAN
  auto* visiting = visit();
  if (visiting == nullptr || !accepting() || !seat->is_first()) {
    return false;
  }
  return visiting->send(sample).has_value();
#else
  return false;
#endif
}

auto StreamSession::video_decoded(const DecodedFrame& frame)
    -> std::optional<libchiaking::media::PresentationLoss> {
  using Kind = DecodedFrame::Kind;
  auto* active = published_session_.load(std::memory_order_acquire);
#if CHIAKI_KAKUSAN
  auto* visiting = active == nullptr ? visit() : nullptr;
#endif
  switch (frame.kind) {
    case Kind::failed:
      ++output_failures_;
      last_output_error_ = frame.status;
      if (active != nullptr) {
        active->video_output_failed(frame.status);
#if CHIAKI_KAKUSAN
      } else if (visiting != nullptr) {
        visiting->video_output_failed(frame.status);
#endif
      }
      return std::nullopt;
    case Kind::rejected:
      if (active != nullptr) {
        active->video_rejected(frame.index, frame.status);
#if CHIAKI_KAKUSAN
      } else if (visiting != nullptr) {
        visiting->video_rejected(frame.index, frame.status);
#endif
      }
      return std::nullopt;
    case Kind::picture:
      break;
  }
  std::optional<libchiaking::media::PresentationLoss> loss;
  if (active != nullptr) {
    loss = active->video_presented();
#if CHIAKI_KAKUSAN
  } else if (visiting != nullptr) {
    loss = visiting->video_presented();
#endif
  }
  if (loss) {
    ++surfaces_;
  }
  return loss;
}

auto StreamSession::request_keyframe() -> bool {
  const auto active = session();
  return active && active->request_keyframe();
}

auto StreamSession::take_feedback(std::uint8_t pad, FeedbackReport report)
    -> bool {
  const auto seat = SeatNumber::create(pad);
  if (!seat) {
    return false;
  }
  const auto active = session();
  const bool guest_owned =
      active && active->seats().seat(*seat).is_held_by_guest();
  return feedback_.take(*seat, accepting(), guest_owned, report);
}

#if CHIAKI_KAKUSAN
auto StreamSession::invite_guest() -> KakusanCommandOutcome {
  return shared_.host_invite();
}

auto StreamSession::import_reply(std::string_view reply)
    -> KakusanCommandOutcome {
  return shared_.host_import_reply(reply);
}

auto StreamSession::enter_guest_code(const Bytes& guest, std::string_view code)
    -> KakusanCommandOutcome {
  return shared_.host_enter_code(guest, code);
}

auto StreamSession::give_seat(const Bytes& guest, std::uint8_t pad,
                              ControllerKind controller,
                              const Bytes& account_id)
    -> KakusanCommandOutcome {
  return shared_.host_give_seat(guest, pad, controller, account_id);
}

auto StreamSession::remove_guest(const Bytes& guest) -> KakusanCommandOutcome {
  return shared_.host_remove(guest);
}

auto StreamSession::set_local_seats(std::uint8_t local_seats)
    -> KakusanCommandOutcome {
  return shared_.host_set_local_seats(local_seats);
}

auto StreamSession::set_capacity(std::uint8_t capacity)
    -> KakusanCommandOutcome {
  return shared_.host_set_capacity(capacity);
}

auto StreamSession::tune_sharing(const libchiaking::kakusan::Tuning& tuning)
    -> KakusanCommandOutcome {
  return shared_.host_set_tuning(tuning);
}

auto StreamSession::remember_device(const Bytes& identity,
                                    std::string_view nickname, bool replace)
    -> RememberOutcome {
  return shared_.remember(identity, nickname, replace);
}

auto StreamSession::enter_host_code(std::string_view code)
    -> KakusanCommandOutcome {
  return shared_.guest_enter_code(code);
}

auto StreamSession::leave_kakusan() -> KakusanCommandOutcome {
  return shared_.guest_leave();
}
#else
auto StreamSession::invite_guest() -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::import_reply(std::string_view) -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::enter_guest_code(const Bytes&, std::string_view)
    -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::give_seat(const Bytes&, std::uint8_t, ControllerKind,
                              const Bytes&) -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::remove_guest(const Bytes&) -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::set_local_seats(std::uint8_t) -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::set_capacity(std::uint8_t) -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::tune_sharing(const libchiaking::kakusan::Tuning&)
    -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::remember_device(const Bytes&, std::string_view, bool)
    -> RememberOutcome {
  return RememberOutcome::unavailable(KakusanUnavailable::not_built);
}

auto StreamSession::enter_host_code(std::string_view) -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}

auto StreamSession::leave_kakusan() -> KakusanCommandOutcome {
  return KakusanCommandOutcome::refused(KakusanCommandRefusal::not_armed);
}
#endif

auto StreamSession::statistics() const -> StreamStatistics {
  libchiaking::play::Statistics observed;
  if (const auto active = session()) {
    observed = active->statistics();
#if CHIAKI_KAKUSAN
  } else if (const auto* visiting = visit()) {
    observed.video = visiting->video_statistics();
#endif
  }
  auto statistics = statistics_of(observed);
  const std::uint64_t output_failures = output_failures_;
  statistics.decoder_failures += output_failures;
  if (output_failures != 0) {
    statistics.last_decoder_error = last_output_error_;
  }
  statistics.surfaces = surfaces_;
  statistics.audio = audio_.statistics();
  statistics.delivery = {
      .slow_video = slow_video_.load(std::memory_order_relaxed),
      .slow_audio = slow_audio_.load(std::memory_order_relaxed),
      .gaps = delivery_gaps_.load(std::memory_order_relaxed),
      .longest_video_us = longest_video_us_.load(std::memory_order_relaxed),
      .longest_audio_us = longest_audio_us_.load(std::memory_order_relaxed),
      .longest_gap_us = longest_gap_us_.load(std::memory_order_relaxed),
  };
  const std::lock_guard lock(granted_mutex_);
  statistics.granted = granted_;
  return statistics;
}

auto StreamSession::microphone_statistics() const -> Microphone::Statistics {
  const auto active = session();
  return active ? active->microphone().statistics() : Microphone::Statistics{};
}

auto StreamSession::feedback_statistics() const -> FeedbackStatistics {
  return feedback_.statistics();
}

auto StreamSession::feedback_intensities() const -> FeedbackIntensities {
  return feedback_.intensities();
}

auto StreamSession::read_logs(std::size_t limit) -> StreamLogLines {
  StreamLogLines lines;
  const auto most = std::min(limit, log_read_limit);
  while (lines.size() < most) {
    const auto entry = log_.journal()->read();
    if (!entry) {
      break;
    }
    lines.push_back({entry->severity(), entry->line()});
  }
  return lines;
}

auto StreamSession::take_api_capture()
    -> std::optional<libchiaking::SecretString> {
  return log_.journal()->take_capture();
}

void StreamSession::describe(const libchiaking::media::AudioFormat& format) {
  log_.info(std::format("core audio format: channels={} rate={} frame={}",
                        format.channels, format.rate, format.frame_size));
  if (!audio_.configure(format, false)) {
    log_.warning(std::format(
        "core audio format setup failed: channels={} rate={} frame={}",
        format.channels, format.rate, format.frame_size));
  }
}

void StreamSession::on_stream_description(
    const libchiaking::media::StreamDescription& description) {
  describe(description.audio);
  const std::lock_guard lock(granted_mutex_);
  granted_ = description.picture;
}

void StreamSession::raise_to(std::atomic<std::uint64_t>& longest,
                             std::uint64_t value) {
  auto seen = longest.load(std::memory_order_relaxed);
  while (value > seen && !longest.compare_exchange_weak(
                             seen, value, std::memory_order_relaxed)) {
  }
}

auto StreamSession::microseconds_of(
    std::chrono::steady_clock::duration duration) -> std::uint64_t {
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(duration).count());
}

template <class Delivery>
auto StreamSession::timed(bool video, Delivery&& delivery) {
  const auto began = std::chrono::steady_clock::now();
  if (last_delivered_ != std::chrono::steady_clock::time_point{}) {
    const auto idle = began - last_delivered_;
    raise_to(longest_gap_us_, microseconds_of(idle));
    if (idle >= delivery_gap) {
      delivery_gaps_.fetch_add(1, std::memory_order_relaxed);
    }
  }
  auto result = std::forward<Delivery>(delivery)();
  last_delivered_ = std::chrono::steady_clock::now();
  const auto took = last_delivered_ - began;
  raise_to(video ? longest_video_us_ : longest_audio_us_,
           microseconds_of(took));
  if (took >= slow_delivery) {
    (video ? slow_video_ : slow_audio_).fetch_add(1, std::memory_order_relaxed);
  }
  return result;
}

auto StreamSession::on_video(const libchiaking::media::VideoUnit& unit)
    -> VideoResult {
  return timed(true, [&] {
    return listener_.on_video({.bytes = unit.frame().bytes(),
                               .header = unit.profile_header(),
                               .hevc = unit.hevc(),
                               .index = unit.frame().frame_index()});
  });
}

auto StreamSession::media() noexcept -> libchiaking::media::MediaSink& {
  return *this;
}

auto StreamSession::decoder_name() const -> std::string_view {
  return "VideoToolbox";
}

void StreamSession::on_video_gap() {}

auto StreamSession::submit_audio(const AudioUnit& unit) -> AudioResult {
  if (unit.controller_speaker) {
    submit_speaker(*unit.controller_speaker, unit.bytes);
    return {};
  }
  if (unit.voice) {
    return submit_voice(unit);
  }
  if (unit.kind != AudioUnit::Kind::format) {
    return audio_.deliver(unit.bytes);
  }
  if (audio_.configure(unit.format, unit.raw_pcm)) {
    return {};
  }
  log_.warning(std::format(
      "core audio profile switch failed: channels={} rate={} frame={} raw={}",
      unit.format.channels, unit.format.rate, unit.format.frame_size,
      unit.raw_pcm ? 1 : 0));
  return {AudioVerdict::failed, AudioPath::bad_argument};
}

auto StreamSession::submit_voice(const AudioUnit& unit) -> AudioResult {
  if (unit.kind != AudioUnit::Kind::format) {
    return audio_.deliver_voice(unit.bytes);
  }
  if (!audio_.configure_voice(unit.format, unit.raw_pcm)) {
    log_.warning(std::format(
        "core audio voice format failed: channels={} rate={} frame={} raw={}",
        unit.format.channels, unit.format.rate, unit.format.frame_size,
        unit.raw_pcm ? 1 : 0));
  }
  return {};
}

void StreamSession::submit_speaker(std::uint8_t seat,
                                   std::span<const std::byte> packet) {
  const auto pcm = audio_.decode_speaker(seat, packet);
  if (!pcm || pcm->empty()) {
    return;
  }
  if (seat == 0 && speaker_to_listener_) {
    listener_.on_controller_speaker(seat, *pcm);
    return;
  }
  audio_.hold_speaker(seat, *pcm);
}

auto StreamSession::on_audio(const AudioUnit& unit) -> AudioResult {
  return timed(false, [&] { return submit_audio(unit); });
}

void StreamSession::submit_feedback(const ControllerFeedback& feedback) {
  if (feedback_.accept(feedback)) {
    return;
  }
  if (feedback.get<libchiaking::controllers::MotionReset>() != nullptr) {
    log_.info(
        std::format("core motion reset requested by the console: count={}",
                    ++motion_resets_));
    listener_.on_motion_reset();
  } else if (const auto* settings =
                 feedback.get<libchiaking::controllers::MotionSettings>()) {
    log_.info(std::format(
        "core motion settings from the console: tilt correction byte {}, "
        "angular velocity dead band byte {}",
        settings->tilt_correction, settings->angular_velocity_deadband));
    listener_.on_motion_settings(settings->tilt_correction != 0,
                                 settings->angular_velocity_deadband != 0);
  } else if (const auto* confirmed =
                 feedback.get<libchiaking::controllers::SeatConfirmed>()) {
    listener_.on_seat_confirmed(feedback.seat, confirmed->colour);
  } else if (const auto* lightbar =
                 feedback.get<libchiaking::controllers::Lightbar>()) {
    listener_.on_lightbar(lightbar->colour);
  }
}

void StreamSession::on_feedback(const ControllerFeedback& feedback) {
  submit_feedback(feedback);
}

void StreamSession::on_state(SessionState state) {
  if (state == SessionState::connecting && played_) {
    listener_.on_reconnecting(1);
    return;
  }
  if (state != SessionState::playing) {
    return;
  }
  listener_.on_connected(played_.exchange(true));
  if (last_launch_progress_) {
    launch_progress(*last_launch_progress_, true);
  }
}

void StreamSession::on_ended(const libchiaking::play::Outcome& ended) {
  const auto& quit = ended.quit();
  listener_.on_disconnected(quit ? std::optional{quit->reason()}
                                 : std::nullopt);
}

void StreamSession::on_connect_progress(
    const libchiaking::play::ConnectProgress& progress) {
  const auto elapsed_ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(progress.elapsed)
          .count();
  log_.info(std::format("core setup progress: step={} attempt={} after {} ms",
                        static_cast<unsigned>(progress.step), progress.attempt,
                        elapsed_ms));
  listener_.on_connect_progress(progress);
  if (progress.reconnecting) {
    listener_.on_reconnecting(progress.attempt);
    return;
  }
  if (progress.attempt != attempt_) {
    attempt_ = progress.attempt;
    listener_.on_start_attempt(progress.attempt);
  }
}

void StreamSession::launch_progress(const LaunchProgress& progress,
                                    bool playing) {
  listener_.on_launch_progress(progress, playing);
}

void StreamSession::on_launch_progress(const LaunchProgress& progress) {
  last_launch_progress_ = progress;
  log_.info(std::format(
      "core launch progress: phase={} activity={} step={} of {} "
      "queue_position={} attempt={} migration={}",
      static_cast<int>(progress.phase()),
      progress.activity() ? static_cast<int>(*progress.activity()) : -1,
      progress.step() ? static_cast<int>(progress.step()->number) : -1,
      progress.step() ? static_cast<int>(progress.step()->of) : -1,
      progress.queue_position() ? static_cast<int>(*progress.queue_position())
                                : -1,
      progress.attempt() ? static_cast<int>(*progress.attempt()) : -1,
      progress.migration_percent()
          ? static_cast<int>(*progress.migration_percent())
          : -1));
  launch_progress(progress, false);
}

void StreamSession::on_datacenters_offered(
    const libchiaking::play::DatacenterOffer& offer) {
  listener_.on_datacenters_offered(offer);
}

void StreamSession::on_datacenter_chosen(
    const libchiaking::play::DatacenterChoice& choice) {
  log_.info(std::format(
      "core cloud datacenter: chosen {} how={} round_trip_ms={}",
      choice.name().text(), static_cast<int>(choice.how()),
      choice.round_trip() ? static_cast<int>(choice.round_trip()->count())
                          : -1));
  listener_.on_datacenter_chosen(choice);
}

void StreamSession::on_login_pin_needed(bool previous_was_wrong) {
  listener_.on_login_pin_needed(previous_was_wrong);
}

void StreamSession::on_picture_blocked(bool blocked) {
  listener_.on_picture_blocked(blocked);
}

void StreamSession::on_connection_waiting(bool waiting) {
  listener_.on_connection_waiting(waiting);
}

void StreamSession::on_play_time_left(std::chrono::minutes left,
                                      libchiaking::play::PlayTimeLimit limit) {
  listener_.on_play_time_left(left, limit);
}

void StreamSession::on_cloud_notice(
    const libchiaking::play::CloudNotice& notice) {
  listener_.on_cloud_notice(notice);
}

void StreamSession::on_recording_banner(
    const libchiaking::play::RecordingBanner& banner) {
  listener_.on_recording_banner(banner);
}

void StreamSession::on_capture_thumbnail(
    const libchiaking::play::CloudCapture& capture) {
  listener_.on_capture_thumbnail(capture);
}

void StreamSession::on_capture_uploaded(
    const libchiaking::play::CloudCaptureUpload& upload) {
  listener_.on_capture_uploaded(upload);
}

void StreamSession::on_keyboard_opened(std::string_view text) {
  log_.info(std::format("console keyboard opened with {} bytes of text",
                        text.size()));
  listener_.on_keyboard(KeyboardChange::opened, text);
}

void StreamSession::on_keyboard_text(std::string_view text) {
  listener_.on_keyboard(KeyboardChange::text_changed, text);
}

void StreamSession::on_keyboard_closed() {
  log_.info("console keyboard closed");
  listener_.on_keyboard(KeyboardChange::closed, {});
}

void StreamSession::on_seat_passcode_needed(SeatNumber seat, bool retry) {
  listener_.on_seat_passcode_needed(seat, retry);
}

void StreamSession::on_seat_joined(SeatNumber seat,
                                   libchiaking::controllers::SeatLight) {
  listener_.on_seat_joined(seat);
}

void StreamSession::on_seat_left(SeatNumber seat) {
  listener_.on_seat_left(seat);
}

void StreamSession::on_seat_refused(const SeatRefusal& refusal) {
  const auto seat = refusal.seat();
  if (!seat) {
    return;
  }
  log_.warning(std::format("couch seat {} refused: {} console_status={}",
                           seat->index(), seat_refusal_name(refusal.kind()),
                           refusal.console_status()
                               ? static_cast<int>(*refusal.console_status())
                               : -1));
  listener_.on_seat_refused(refusal);
}

}  // namespace chiaki_bridge
