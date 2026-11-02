#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <libchiaking/kakusan.hpp>
#include <libchiaking/play.hpp>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "catalog.hpp"
#include "core.hpp"
#include "play.hpp"
#include "stream_facts.hpp"

namespace chiaki_bridge {

struct EncodedFrame {
  std::span<const std::byte> bytes;
  std::span<const std::byte> header;
  bool hevc{};
  std::uint16_t index{};
};

struct DecodedFrame {
  enum class Kind : std::uint8_t {
    picture,
    rejected,
    failed,
  };

  Kind kind{Kind::picture};
  std::uint16_t index{};
  int status{};
};

enum class HapticDelivery : std::uint8_t {
  polled,
  blocks,
  frames,
};

enum class KeyboardChange : std::uint8_t {
  opened,
  text_changed,
  closed,
};

struct FeedbackStatistics {
  std::uint64_t rumbles{};
  std::uint64_t callbacks{};
  std::uint64_t bytes{};
  std::uint64_t malformed{};
  std::uint64_t packets_taken{};
  std::uint64_t buffered_bytes{};
};

struct FeedbackIntensities {
  std::uint8_t haptic{1};
  std::uint8_t trigger{1};
};

struct StreamLogLine {
  libchiaking::platform::LogSeverity severity{};
  std::string message;
};

using StreamLogLines = std::vector<StreamLogLine>;

struct PictureSetup {
  std::uint32_t height{};
  std::uint32_t fps{};
  std::uint32_t bitrate_kbps{};
  libchiaking::media::VideoCodec codec{libchiaking::media::VideoCodec::h264};
  bool measure_bandwidth{};
  bool stable_quality{};
};

struct TakionTuning {
  std::uint32_t version{};
  bool negotiate{};
};

struct TakionSetup {
  TakionTuning local_ps4;
  TakionTuning local_ps5;
  TakionTuning ps_now;
  TakionTuning ps_cloud;

  auto of(StreamTarget target) const noexcept -> TakionTuning;
};

struct MediaOff {
  bool audio{};
  bool video{};
};

struct DatacenterRequest {
  std::string name;
  std::optional<std::chrono::milliseconds> ask_within;
};

struct CloudStart {
  std::string product_id;
  DatacenterRequest datacenter;
  const ClearedLaunch* cleared{};
};

struct KakusanHosting {
  std::uint8_t capacity{};
  std::uint8_t local_seats{};
  bool force_port_guessing{};
};

class StreamListener {
 public:
  StreamListener() = default;
  StreamListener(const StreamListener&) = delete;
  auto operator=(const StreamListener&) -> StreamListener& = delete;
  virtual ~StreamListener() = default;

  virtual auto decodes_video() const -> bool { return true; }
  virtual auto on_video(const EncodedFrame& frame)
      -> libchiaking::media::VideoResult = 0;
  virtual void on_connected(bool reconnected) {}
  virtual void on_disconnected(
      std::optional<libchiaking::play::ConsoleQuit::Reason> quit) {}
  virtual void on_start_attempt(std::uint32_t attempt) {}
  virtual void on_reconnecting(std::uint32_t attempt) {}
  virtual void on_connect_progress(
      const libchiaking::play::ConnectProgress& progress) {}
  virtual void on_launch_progress(
      const libchiaking::play::LaunchProgress& progress, bool playing) {}
  virtual void on_datacenters_offered(
      const libchiaking::play::DatacenterOffer& offer) {}
  virtual void on_datacenter_chosen(
      const libchiaking::play::DatacenterChoice& choice) {}
  virtual void on_picture_blocked(bool blocked) {}
  virtual void on_connection_waiting(bool waiting) {}
  virtual void on_play_time_left(std::chrono::minutes left,
                                 libchiaking::play::PlayTimeLimit limit) {}
  virtual void on_login_pin_needed(bool retry) {}
  virtual void on_seat_passcode_needed(
      libchiaking::controllers::SeatNumber seat, bool retry) {}
  virtual void on_seat_joined(libchiaking::controllers::SeatNumber seat) {}
  virtual void on_seat_confirmed(libchiaking::controllers::SeatNumber seat,
                                 libchiaking::controllers::SeatLight light) {}
  virtual void on_seat_left(libchiaking::controllers::SeatNumber seat) {}
  virtual void on_seat_refused(const libchiaking::play::SeatRefusal& refusal) {}
  virtual void on_lightbar(libchiaking::controllers::SeatLight light) {}
  virtual void on_motion_reset() {}
  virtual void on_motion_settings(bool tilt_correction,
                                  bool angular_velocity_deadband) {}
  virtual void on_rumble(libchiaking::controllers::SeatNumber seat,
                         std::uint8_t low, std::uint8_t high) {}
  virtual void on_haptic_block(
      std::span<const std::uint8_t, libchiaking::controllers::HapticBlock::size>
          pcm,
      std::uint8_t intensity) {}
  virtual void on_controller_speaker(std::uint8_t seat,
                                     std::span<const std::int16_t> pcm) {}
  virtual void on_haptic_frames(std::span<const std::uint8_t> pcm,
                                std::uint8_t intensity) {}
  virtual void on_keyboard(KeyboardChange change, std::string_view text) {}
  virtual void on_cloud_notice(const libchiaking::play::CloudNotice& notice) {}
  virtual void on_recording_banner(
      const libchiaking::play::RecordingBanner& banner) {}
  virtual void on_capture_thumbnail(
      const libchiaking::play::CloudCapture& capture) {}
  virtual void on_capture_uploaded(
      const libchiaking::play::CloudCaptureUpload& upload) {}
  virtual void on_kakusan(const KakusanEvent& event, std::string_view text) {}
};

class Stream {
 public:
  static constexpr std::size_t feedback_report_size = 279;

  using FeedbackReport = std::span<std::uint8_t, feedback_report_size>;

  static auto open(StreamListener& listener) -> std::unique_ptr<Stream>;

  Stream(const Stream&) = delete;
  auto operator=(const Stream&) -> Stream& = delete;
  virtual ~Stream() = default;

  virtual auto set_picture(const PictureSetup& picture) -> bool = 0;
  virtual void set_takion(const TakionSetup& takion) = 0;
  virtual void set_port_guessing(bool forced, std::uint32_t guesses) = 0;
  virtual void set_accessibility(
      libchiaking::play::AccessibilityRequest accessibility) = 0;
  virtual void update_accessibility(
      libchiaking::play::AccessibilityRequest accessibility) = 0;
  virtual void set_console_handover(
      libchiaking::play::ConsoleHandover handover) = 0;
  virtual void set_reconnect_after_drop(bool enabled) = 0;
  virtual void set_media_off(MediaOff media) = 0;
  virtual void set_api_capture(bool enabled) = 0;
  virtual void set_text_entry(bool enabled) = 0;
  [[nodiscard]] virtual auto arm_kakusan(const KakusanHosting& hosting)
      -> KakusanCommandOutcome = 0;

  virtual void route_haptics(HapticDelivery delivery) = 0;
  virtual void set_audio_gain(float gain) = 0;
  virtual void set_voice_gain(float gain) = 0;
  virtual void set_audio_buffer(std::chrono::milliseconds buffer) = 0;
  virtual void set_audio_output(std::string_view device) = 0;
  virtual void set_audio_spatial(bool enabled) = 0;
  virtual void set_audio_3d(bool enabled) = 0;
  virtual auto request_audio_channels(std::uint32_t channels) -> bool = 0;
  virtual void request_controller_speaker(bool enabled) = 0;
  virtual void route_controller_speaker(bool to_listener) = 0;
  virtual void set_system_ui(libchiaking::play::Session::SystemUi state) = 0;

  [[nodiscard]] virtual auto run_console(const Bytes& account_id,
                                         const Bytes& hardware_id,
                                         libchiaking::consoles::Route route)
      -> StreamOutcome = 0;
  [[nodiscard]] virtual auto run_cloud(const Bytes& account_id,
                                       const CloudStart& start)
      -> StreamOutcome = 0;
  [[nodiscard]] virtual auto join_kakusan(std::string_view invitation,
                                          bool force_port_guessing)
      -> GuestOutcome = 0;

  virtual void cancel() = 0;
  virtual void stop_for_sleep() = 0;
  virtual auto stop_with_rest(bool for_sleep) -> bool = 0;

  virtual auto go_home() -> bool = 0;
  virtual auto submit_login_pin(std::string_view pin) -> bool = 0;
  virtual auto await_login_pin() -> bool = 0;
  virtual auto submit_seat_passcode(std::uint8_t pad, std::string_view pin)
      -> bool = 0;
  virtual auto add_couch_player(
      std::uint8_t pad, libchiaking::controllers::ControllerKind controller,
      const Bytes& account_id) -> bool = 0;
  virtual auto remove_couch_player(std::uint8_t pad) -> bool = 0;
  virtual auto set_keyboard_text(std::string_view text) -> bool = 0;
  virtual auto close_keyboard(bool accept) -> bool = 0;
  virtual auto send_keyboard(std::uint8_t modifiers, std::uint8_t leds,
                             std::span<const std::uint16_t> keys) -> bool = 0;
  virtual auto connect_microphone(std::uint32_t request) -> bool = 0;
  virtual auto microphone_state(std::uint32_t request) const
      -> libchiaking::play::Microphone::ConnectState = 0;
  virtual auto set_microphone_muted(bool muted) -> bool = 0;
  virtual auto send_microphone(std::span<const std::uint8_t> frame) -> bool = 0;
  virtual auto choose_datacenter(std::string_view name) -> bool = 0;
  virtual auto send_controller(std::uint8_t pad, const ControllerSample& sample)
      -> bool = 0;
  virtual auto press_create(libchiaking::play::Session::CreatePress press)
      -> bool = 0;
  virtual auto join_invitation(const std::string& invitation_id,
                               const std::string& session_id) -> bool = 0;
  virtual auto open_saved_data() -> bool = 0;

  virtual auto video_decoded(const DecodedFrame& frame)
      -> std::optional<libchiaking::media::PresentationLoss> = 0;
  virtual auto request_keyframe() -> bool = 0;
  virtual auto take_feedback(std::uint8_t pad, FeedbackReport report)
      -> bool = 0;

  [[nodiscard]] virtual auto invite_guest() -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto import_reply(std::string_view reply)
      -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto enter_guest_code(const Bytes& guest,
                                              std::string_view code)
      -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto give_seat(
      const Bytes& guest, std::uint8_t pad,
      libchiaking::controllers::ControllerKind controller,
      const Bytes& account_id) -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto remove_guest(const Bytes& guest)
      -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto set_local_seats(std::uint8_t local_seats)
      -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto set_capacity(std::uint8_t capacity)
      -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto tune_sharing(
      const libchiaking::kakusan::Tuning& tuning) -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto remember_device(const Bytes& identity,
                                             std::string_view nickname,
                                             bool replace)
      -> RememberOutcome = 0;
  [[nodiscard]] virtual auto enter_host_code(std::string_view code)
      -> KakusanCommandOutcome = 0;
  [[nodiscard]] virtual auto leave_kakusan() -> KakusanCommandOutcome = 0;

  virtual auto statistics() const -> StreamStatistics = 0;
  virtual auto microphone_statistics() const
      -> libchiaking::play::Microphone::Statistics = 0;
  virtual auto feedback_statistics() const -> FeedbackStatistics = 0;
  virtual auto feedback_intensities() const -> FeedbackIntensities = 0;
  virtual auto read_logs(std::size_t limit) -> StreamLogLines = 0;
  virtual auto take_api_capture()
      -> std::optional<libchiaking::SecretString> = 0;

 protected:
  Stream() = default;
};

}  // namespace chiaki_bridge
