#pragma once

#include <cstdint>
#include <libchiaking/kakusan_types.hpp>
#include <libchiaking/play_types.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>

#include "core.hpp"
#include "kakusan.hpp"
#include "media.hpp"

namespace chiaki_bridge {

enum class StreamRefusal : std::uint8_t {
  core_closed,
  unknown_user,
  unknown_console,
  invalid_title,
  no_decoder,
};

struct ClearanceFacts {
  libchiaking::catalog::LaunchRefusal::Kind kind{};
  std::optional<libchiaking::users::Tier> tier_held;
  std::optional<std::int64_t> time_ms;
  std::string notice;
  std::string library_sku;
  bool needs_sign_in{};
};

struct LaunchRefusalFacts {
  libchiaking::play::LaunchRefused::Kind kind{};
  std::optional<ClearanceFacts> clearance;
  std::string upgrade_url;
  std::string display_price;
  std::optional<libchiaking::catalog::StreamRefusal::Kind> service_refusal;
  std::optional<std::int64_t> best_round_trip_ms;
  std::string datacenter;
  std::optional<libchiaking::play::LaunchRefused::NoServer> no_server;
  std::uint16_t http_status{};
};

/// How a stream that started came to its end.
struct StreamEndFacts {
  /// How the stream ended.
  libchiaking::play::Outcome::Ending ending;
  /// Whether the user left the stream.
  bool left{};
  /// Why the stream ended, when the core knows.
  std::optional<libchiaking::play::EndReason::Cause> cause;
  /// The step the stream ended at, when the core knows.
  std::optional<libchiaking::play::EndReason::Step> step;
  /// The console's reason code, or 0.
  std::uint32_t console_reason{};
  /// The HTTP status behind the ending, or 0.
  std::uint16_t http_status{};
  /// The address the user can open about the ending, empty when there is none.
  std::string action_url;
  /// Why the console quit, when it did.
  std::optional<libchiaking::play::ConsoleQuit::Reason> quit;
  /// The media failure that ended the stream, when one did.
  std::optional<libchiaking::media::MediaFailure> media_failure;
  /// What became of the request to put the console to rest.
  libchiaking::play::RestOutcome rest{libchiaking::play::RestOutcome::none};
  /// Why the launch was refused, when it was.
  std::optional<LaunchRefusalFacts> launch_refused;
  /// The stream's diagnostic trace.
  std::string diagnostics;
};

/// Why the core refused to start a stream.
struct StartRefusalFacts {
  /// The reason.
  libchiaking::play::StartRefusal::Kind kind;
  /// Why the console could not be reached, when that is the reason.
  std::optional<libchiaking::consoles::Unreachable> unreachable;
  /// Why the launch was refused, when it was.
  std::optional<LaunchRefusalFacts> launch_refused;
  /// The HTTP status behind the refusal, or 0.
  std::uint16_t http_status{};
};

/// How a stream ended: ended after it started, refused by the core before
/// it started, refused by the bridge, or with no ending recorded.
class StreamOutcome {
 public:
  /// The ways the stream can end.
  enum class Kind : std::uint8_t {
    /// The stream started and ended.
    ended,
    /// The core refused to start the stream.
    start_refused,
    /// The bridge refused before the core ran.
    refused,
    /// No ending was recorded.
    unrecorded,
  };

  /// A stream that ended.
  static auto ended(StreamEndFacts value) -> StreamOutcome {
    return StreamOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::ended)>,
             std::move(value)}};
  }

  /// A stream the core refused to start.
  static auto start_refused(StartRefusalFacts value) -> StreamOutcome {
    return StreamOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::start_refused)>,
             std::move(value)}};
  }

  /// A stream the bridge refused.
  static auto refused(StreamRefusal value) -> StreamOutcome {
    return StreamOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// A stream with no ending recorded.
  static auto unrecorded() -> StreamOutcome {
    return StreamOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unrecorded)>}};
  }

  /// How the stream ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// How the stream ended; valid for `ended`.
  auto ending() const -> StreamEndFacts {
    return std::get<std::to_underlying(Kind::ended)>(held_);
  }

  /// Why the core refused to start; valid for `start_refused`.
  auto start_refusal() const -> StartRefusalFacts {
    return std::get<std::to_underlying(Kind::start_refused)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> StreamRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

  /// Why the launch was refused, whether the stream ended or the core refused
  /// to start it.
  auto launch_refused() const -> std::optional<LaunchRefusalFacts> {
    switch (kind()) {
      case Kind::ended:
        return ending().launch_refused;
      case Kind::start_refused:
        return start_refusal().launch_refused;
      case Kind::refused:
      case Kind::unrecorded:
        break;
    }
    return std::nullopt;
  }

  /// What became of the request to put the console to rest, `none` unless
  /// the stream `ended`.
  auto rest() const -> libchiaking::play::RestOutcome {
    return kind() == Kind::ended ? ending().rest
                                 : libchiaking::play::RestOutcome::none;
  }

  /// The stream's diagnostic trace, empty unless the stream `ended`.
  auto diagnostics() const -> std::string {
    return kind() == Kind::ended ? ending().diagnostics : std::string{};
  }

 private:
  using Case = std::variant<StreamEndFacts, StartRefusalFacts, StreamRefusal,
                            std::monostate>;

  explicit StreamOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How a guest's run of a shared stream ended once it started.
struct GuestEndFacts {
  /// How the visit ended.
  libchiaking::kakusan::VisitOutcome::Status status;
  /// Why the session refused the guest, when it did.
  std::optional<libchiaking::kakusan::Refusal::Kind> refused;
  /// The media failure that ended the run, when one did.
  std::optional<libchiaking::media::MediaFailure> media_failure;
  /// The run's diagnostic trace.
  std::string diagnostics;
};

/// How joining a shared stream as a guest ended: ended, declined before it
/// started, or refused by the bridge.
class GuestOutcome {
 public:
  /// The ways the run can end.
  enum class Kind : std::uint8_t {
    /// The run started and ended.
    ended,
    /// The session refused the invitation before the run started.
    declined,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A run that ended.
  static auto ended(GuestEndFacts value) -> GuestOutcome {
    return GuestOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::ended)>,
             std::move(value)}};
  }

  /// A run the session refused before it started.
  static auto declined(libchiaking::kakusan::Refusal::Kind value)
      -> GuestOutcome {
    return GuestOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::declined)>,
             std::move(value)}};
  }

  /// A run the bridge refused.
  static auto refused(StreamRefusal value) -> GuestOutcome {
    return GuestOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the run ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// How the run ended; valid for `ended`.
  auto ending() const -> GuestEndFacts {
    return std::get<std::to_underlying(Kind::ended)>(held_);
  }

  /// Why the session refused; valid for `declined`.
  auto decline() const -> libchiaking::kakusan::Refusal::Kind {
    return std::get<std::to_underlying(Kind::declined)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> StreamRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

  /// The run's diagnostic trace, empty unless the run `ended`.
  auto diagnostics() const -> std::string {
    return kind() == Kind::ended ? ending().diagnostics : std::string{};
  }

 private:
  using Case = std::variant<GuestEndFacts, libchiaking::kakusan::Refusal::Kind,
                            StreamRefusal>;

  explicit GuestOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

enum class KakusanCommandRefusal : std::uint8_t {
  not_armed,
  core_closed,
};

/// How a Kakusan command to a running stream ended: accepted, declined by
/// the session, or refused by the bridge.
class KakusanCommandOutcome {
 public:
  /// The ways the command can end.
  enum class Kind : std::uint8_t {
    /// The session took the command.
    accepted,
    /// The session refused the command.
    declined,
    /// The bridge refused before the session ran.
    refused,
  };

  /// A command the session took, with the guest it names, empty when it
  /// names none.
  static auto accepted(Bytes value) -> KakusanCommandOutcome {
    return KakusanCommandOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::accepted)>,
             std::move(value)}};
  }

  /// A command the session refused.
  static auto declined(libchiaking::kakusan::Refusal::Kind value)
      -> KakusanCommandOutcome {
    return KakusanCommandOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::declined)>,
             std::move(value)}};
  }

  /// A command the bridge refused.
  static auto refused(KakusanCommandRefusal value) -> KakusanCommandOutcome {
    return KakusanCommandOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the command ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The guest the command names, empty when it names none; valid for
  /// `accepted`.
  auto guest() const -> Bytes {
    return std::get<std::to_underlying(Kind::accepted)>(held_);
  }

  /// Why the session refused; valid for `declined`.
  auto decline() const -> libchiaking::kakusan::Refusal::Kind {
    return std::get<std::to_underlying(Kind::declined)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> KakusanCommandRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<Bytes, libchiaking::kakusan::Refusal::Kind,
                            KakusanCommandRefusal>;

  explicit KakusanCommandOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

struct KakusanEvent {
  enum class Kind : std::uint8_t {
    invitation_ready,
    reply_bound,
    reply_ready,
    code_ready,
    state_changed,
    stream_shared,
    sharing_ended,
    player_seated,
    player_unseated,
    seats_changed,
    stream_stopped,
    stream_ready,
    host_identified,
    unavailable,
    sharing_failed,
  };

  Kind kind{};
  Bytes guest;
  std::uint64_t expires_at{};
  Bytes identity;
  Bytes fingerprint;
  std::optional<libchiaking::kakusan::Progress> progress;
  std::optional<libchiaking::kakusan::Refusal::Kind> refused;
  std::optional<KakusanCommandRefusal> refusal;
  std::optional<libchiaking::kakusan::EndReason::Kind> ended;
  bool by_peer{};
  std::optional<libchiaking::kakusan::SeatGrant> grant;
  std::optional<std::uint8_t> pad;
  std::optional<std::uint8_t> reserved_pad;
  std::optional<RecognitionFacts> recognition;
  std::optional<libchiaking::kakusan::SeatSummary> seats;
  std::uint32_t video_fps{};
};

struct RoundTripFacts {
  std::uint64_t smoothed_us{};
  std::uint64_t variation_us{};
  std::uint64_t samples{};
  std::uint64_t p99_us{};
  std::uint64_t recent_max_us{};
};

struct ReceptionFacts {
  std::uint64_t jitter_us{};
  std::uint64_t received{};
  std::uint64_t lost{};
  double loss_ratio{};
};

struct VideoMetricFacts {
  std::uint64_t throughput_bps{};
  double loss_ratio{};
  std::int32_t receive_interval_us{};
  std::int32_t transfer_time_us{};
  std::optional<std::uint32_t> reports_sent;
};

struct ServiceMarkFacts {
  std::optional<std::uint8_t> last_dscp;
  std::optional<std::uint8_t> last_ecn;
  std::uint64_t packets{};
};

struct ServerFacts {
  std::uint32_t available_down_kbps{};
  std::uint32_t used_down_kbps{};
  std::uint32_t used_up_kbps{};
  std::uint32_t round_trip_ms{};
  float loss_percent{};
  float upstream_loss_percent{};
  std::uint32_t audio_channels{};
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint32_t corrupt_frames{};
};

struct LinkFacts {
  std::uint64_t video_units{};
  std::uint64_t rejected_packets{};
  std::uint64_t crypto_rejections{};
  std::uint64_t assembled_video{};
  std::uint64_t dependency_rejections{};
  std::uint64_t assembly_rejections{};
  std::uint64_t fec_repaired_frames{};
  std::uint64_t video_stale{};
  std::uint64_t video_metadata{};
  std::uint64_t video_duplicate{};
  std::uint64_t video_invalid{};
  std::uint64_t reorder_skipped{};
  std::uint64_t reorder_dropped{};
  std::uint64_t dropped_posts{};
  std::uint64_t send_dropped{};
  std::optional<RoundTripFacts> round_trip;
  std::optional<ReceptionFacts> reception;
  std::optional<VideoMetricFacts> video_metrics;
  std::optional<ServiceMarkFacts> service_marks;
  std::optional<ServerFacts> server;
};

enum class AudioOutputState : std::uint8_t {
  created,
  configured,
  priming,
  playing,
  stopping,
  stopped,
  failed,
};

struct AudioStatistics {
  std::uint64_t pcm_frames{};
  std::uint64_t pcm_bytes{};
  std::uint64_t underruns{};
  std::uint64_t silent_frames{};
  std::uint64_t overflows{};
  std::uint64_t dropped_frames{};
  std::uint64_t trims{};
  std::uint64_t trimmed_frames{};
  std::uint64_t buffered_frames{};
  std::uint64_t maximum_buffered_frames{};
  std::uint32_t channels{};
  std::uint32_t sample_rate{};
  std::uint32_t received_channels{};
  std::uint32_t received_sample_rate{};
  std::uint32_t received_active_channels{};
  AudioOutputState state{AudioOutputState::created};
  std::uint32_t device_failures{};
  std::uint64_t decode_failures{};
  std::uint64_t concealment_frames{};
  int last_decode_error{};
};

struct DeliveryStatistics {
  std::uint64_t slow_video{};
  std::uint64_t slow_audio{};
  std::uint64_t gaps{};
  std::uint64_t longest_video_us{};
  std::uint64_t longest_audio_us{};
  std::uint64_t longest_gap_us{};
};

struct StreamStatistics {
  std::uint64_t units{};
  std::uint64_t bytes{};
  std::uint64_t lost{};
  std::uint64_t recovered{};
  std::uint64_t decoder_failures{};
  int last_decoder_error{};
  std::uint64_t surfaces{};
  std::uint64_t keyframe_requests{};
  std::uint64_t loop_errors{};
  std::optional<LinkFacts> link;
  std::optional<std::uint32_t> protocol_version;
  std::optional<libchiaking::media::GrantedPicture> granted;
  AudioStatistics audio;
  DeliveryStatistics delivery;
};

struct TouchSample {
  std::uint8_t id{};
  std::uint16_t x{};
  std::uint16_t y{};
};

struct TriggerStates {
  std::uint8_t left{};
  std::uint8_t right{};
};

struct ControllerSample {
  std::uint32_t buttons{};
  std::uint8_t l2{};
  std::uint8_t r2{};
  std::int16_t left_x{};
  std::int16_t left_y{};
  std::int16_t right_x{};
  std::int16_t right_y{};
  std::optional<TouchSample> first_touch;
  std::optional<TouchSample> second_touch;
  std::optional<ControllerMotion> motion;
  std::optional<TriggerStates> trigger_states;
};

}  // namespace chiaki_bridge
