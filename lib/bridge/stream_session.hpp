#pragma once

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <libchiaking/play.hpp>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>

#include "audio_path.hpp"
#include "bridge_log.hpp"
#include "chiaki_bridge/stream.hpp"
#include "feedback_path.hpp"
#include "opened.hpp"
#include "share_desk.hpp"

namespace chiaki_bridge {

class StreamSession final : public Stream,
                            private libchiaking::media::MediaSink,
                            private libchiaking::play::SessionEvents {
 public:
  using Outcome = StreamOutcome;

  explicit StreamSession(StreamListener& listener);
  ~StreamSession() override;

  static auto sample_of(const ControllerSample& input) noexcept
      -> libchiaking::controllers::ControllerState;
  static auto outcome_of(const libchiaking::play::Outcome& ended) -> Outcome;
  static auto outcome_of(const libchiaking::play::StartRefusal& refusal)
      -> Outcome;
  static auto refused(StreamRefusal refusal) -> Outcome;
  static auto refused(libchiaking::play::StartRefusal::Kind kind) -> Outcome;
  static auto launch_facts_of(const libchiaking::play::LaunchRefused& refused)
      -> LaunchRefusalFacts;
  static auto link_of(const libchiaking::play::LinkStatistics& link)
      -> std::optional<LinkFacts>;
  static auto statistics_of(const libchiaking::play::Statistics& observed)
      -> StreamStatistics;
  static auto developer_of(const TakionTuning& takion, MediaOff media)
      -> std::optional<libchiaking::play::DeveloperTuning>;
  static auto refusal_name(libchiaking::play::InputRefusal refusal) noexcept
      -> std::string_view;
  static auto seat_refusal_name(
      libchiaking::play::SeatRefusal::Kind kind) noexcept -> std::string_view;

  auto set_picture(const PictureSetup& picture) -> bool override;
  void set_takion(const TakionSetup& takion) override;
  void set_port_guessing(bool forced, std::uint32_t guesses) override;
  void set_accessibility(
      libchiaking::play::AccessibilityRequest accessibility) override;
  void update_accessibility(
      libchiaking::play::AccessibilityRequest accessibility) override;
  void set_console_handover(
      libchiaking::play::ConsoleHandover handover) override;
  void set_reconnect_after_drop(bool enabled) override;
  void set_media_off(MediaOff media) override;
  void set_api_capture(bool enabled) override;
  void set_text_entry(bool enabled) override;
  auto arm_kakusan(const KakusanHosting& hosting)
      -> KakusanCommandOutcome override;

  void route_haptics(HapticDelivery delivery) override;
  void set_audio_gain(float gain) override;
  void set_voice_gain(float gain) override;
  void set_audio_buffer(std::chrono::milliseconds buffer) override;
  void set_audio_output(std::string_view device) override;
  void set_audio_spatial(bool enabled) override;
  void set_audio_3d(bool enabled) override;
  auto request_audio_channels(std::uint32_t channels) -> bool override;
  void request_controller_speaker(bool enabled) override;
  void route_controller_speaker(bool to_listener) override;
  void set_system_ui(libchiaking::play::Session::SystemUi state) override;

  auto run_console(const Bytes& account_id, const Bytes& hardware_id,
                   libchiaking::consoles::Route route) -> Outcome override;
  auto run_cloud(const Bytes& account_id, const CloudStart& start)
      -> Outcome override;
  auto join_kakusan(std::string_view invitation, bool force_port_guessing)
      -> GuestOutcome override;
  auto run_scripted(
      const Bytes& account_id, libchiaking::play::testing::ScriptedLink& link,
      libchiaking::play::Where where = libchiaking::play::Where::home)
      -> Outcome;

  void cancel() override;
  void stop_for_sleep() override;
  auto stop_with_rest(bool for_sleep) -> bool override;

  auto go_home() -> bool override;
  auto submit_login_pin(std::string_view pin) -> bool override;
  auto await_login_pin() -> bool override;
  auto submit_seat_passcode(std::uint8_t pad, std::string_view pin)
      -> bool override;
  auto add_couch_player(std::uint8_t pad,
                        libchiaking::controllers::ControllerKind controller,
                        const Bytes& account_id) -> bool override;
  auto remove_couch_player(std::uint8_t pad) -> bool override;
  auto set_keyboard_text(std::string_view text) -> bool override;
  auto close_keyboard(bool accept) -> bool override;
  auto send_keyboard(std::uint8_t modifiers, std::uint8_t leds,
                     std::span<const std::uint16_t> keys) -> bool override;
  auto connect_microphone(std::uint32_t request) -> bool override;
  auto microphone_state(std::uint32_t request) const
      -> libchiaking::play::Microphone::ConnectState override;
  auto set_microphone_muted(bool muted) -> bool override;
  auto send_microphone(std::span<const std::uint8_t> frame) -> bool override;
  auto choose_datacenter(std::string_view name) -> bool override;
  auto send_controller(std::uint8_t pad, const ControllerSample& sample)
      -> bool override;
  auto press_create(libchiaking::play::Session::CreatePress press)
      -> bool override;
  auto join_invitation(const std::string& invitation_id,
                       const std::string& session_id) -> bool override;
  auto open_saved_data() -> bool override;

  auto video_decoded(const DecodedFrame& frame)
      -> std::optional<libchiaking::media::PresentationLoss> override;
  auto request_keyframe() -> bool override;
  auto take_feedback(std::uint8_t pad, FeedbackReport report) -> bool override;

  auto invite_guest() -> KakusanCommandOutcome override;
  auto import_reply(std::string_view reply) -> KakusanCommandOutcome override;
  auto enter_guest_code(const Bytes& guest, std::string_view code)
      -> KakusanCommandOutcome override;
  auto give_seat(const Bytes& guest, std::uint8_t pad,
                 libchiaking::controllers::ControllerKind controller,
                 const Bytes& account_id) -> KakusanCommandOutcome override;
  auto remove_guest(const Bytes& guest) -> KakusanCommandOutcome override;
  auto set_local_seats(std::uint8_t local_seats)
      -> KakusanCommandOutcome override;
  auto set_capacity(std::uint8_t capacity) -> KakusanCommandOutcome override;
  auto tune_sharing(const libchiaking::kakusan::Tuning& tuning)
      -> KakusanCommandOutcome override;
  auto remember_device(const Bytes& identity, std::string_view nickname,
                       bool replace) -> RememberOutcome override;
  auto enter_host_code(std::string_view code) -> KakusanCommandOutcome override;
  auto leave_kakusan() -> KakusanCommandOutcome override;

  auto statistics() const -> StreamStatistics override;
  auto microphone_statistics() const
      -> libchiaking::play::Microphone::Statistics override;
  auto feedback_statistics() const -> FeedbackStatistics override;
  auto feedback_intensities() const -> FeedbackIntensities override;
  auto read_logs(std::size_t limit) -> StreamLogLines override;
  auto take_api_capture() -> std::optional<libchiaking::SecretString> override;

  auto log() noexcept -> nx_bridge_log& { return log_; }
#if CHIAKI_KAKUSAN
  auto share_desk() noexcept -> ShareDesk& { return shared_; }
#endif
  auto unclaimed() const -> bool;
  auto decodes_video() const -> bool;
  auto begin_visit() -> bool;
  void end_visit();
  auto media() noexcept -> libchiaking::media::MediaSink&;
  auto session() const -> std::shared_ptr<libchiaking::play::Session>;
  void describe(const libchiaking::media::AudioFormat& format);
  auto submit_voice(const libchiaking::media::AudioUnit& unit)
      -> libchiaking::media::AudioResult;
  void submit_speaker(std::uint8_t seat, std::span<const std::byte> packet);
  auto submit_audio(const libchiaking::media::AudioUnit& unit)
      -> libchiaking::media::AudioResult;
  void submit_feedback(
      const libchiaking::controllers::ControllerFeedback& feedback);

 private:
  enum class Phase : std::uint8_t { created, preparing, guest, finished };

  using Started =
      libchiaking::Expected<std::shared_ptr<libchiaking::play::Session>,
                            libchiaking::play::StartRefusal>;

  static constexpr std::size_t log_read_limit = 257;

  void on_stream_description(
      const libchiaking::media::StreamDescription& description) override;
  auto on_video(const libchiaking::media::VideoUnit& unit)
      -> libchiaking::media::VideoResult override;
  void on_video_gap() override;
  auto on_audio(const libchiaking::media::AudioUnit& unit)
      -> libchiaking::media::AudioResult override;
  static constexpr auto slow_delivery = std::chrono::milliseconds{8};
  static constexpr auto delivery_gap = std::chrono::milliseconds{50};

  static void raise_to(std::atomic<std::uint64_t>& longest,
                       std::uint64_t value);
  static auto microseconds_of(std::chrono::steady_clock::duration duration)
      -> std::uint64_t;
  template <class Delivery>
  auto timed(bool video, Delivery&& delivery);
  void on_feedback(
      const libchiaking::controllers::ControllerFeedback& feedback) override;
  auto decoder_name() const -> std::string_view override;

  void on_state(libchiaking::play::SessionState state) override;
  void on_ended(const libchiaking::play::Outcome& ended) override;
  void on_connect_progress(
      const libchiaking::play::ConnectProgress& progress) override;
  void on_launch_progress(
      const libchiaking::play::LaunchProgress& progress) override;
  void on_datacenters_offered(
      const libchiaking::play::DatacenterOffer& offer) override;
  void on_datacenter_chosen(
      const libchiaking::play::DatacenterChoice& choice) override;
  void on_login_pin_needed(bool previous_was_wrong) override;
  void on_picture_blocked(bool blocked) override;
  void on_connection_waiting(bool waiting) override;
  void on_play_time_left(std::chrono::minutes left,
                         libchiaking::play::PlayTimeLimit limit) override;
  void on_cloud_notice(const libchiaking::play::CloudNotice& notice) override;
  void on_recording_banner(
      const libchiaking::play::RecordingBanner& banner) override;
  void on_capture_thumbnail(
      const libchiaking::play::CloudCapture& capture) override;
  void on_capture_uploaded(
      const libchiaking::play::CloudCaptureUpload& upload) override;
  void on_keyboard_opened(std::string_view text) override;
  void on_keyboard_text(std::string_view text) override;
  void on_keyboard_closed() override;
  void on_seat_passcode_needed(libchiaking::controllers::SeatNumber seat,
                               bool retry) override;
  void on_seat_joined(libchiaking::controllers::SeatNumber seat,
                      libchiaking::controllers::SeatLight light) override;
  void on_seat_left(libchiaking::controllers::SeatNumber seat) override;
  void on_seat_refused(const libchiaking::play::SeatRefusal& refusal) override;

#if CHIAKI_KAKUSAN
  auto visit() const noexcept -> libchiaking::kakusan::GuestVisit*;
#endif
  auto accepting() const -> bool;
  auto claim() -> bool;
  auto decline() -> Outcome;
  auto result() const -> Outcome;
  auto refuse(Outcome refused) -> Outcome;
  auto attend(Started started) -> Outcome;
  void conclude(const libchiaking::play::Outcome& ended);
  auto preferences(StreamTarget target, libchiaking::play::SoundRequest sound)
      -> std::optional<libchiaking::play::Preferences>;
  void journal_sessions();
  void request_audio_3d(libchiaking::play::Session& active, bool enabled);
  void request_system_ui(libchiaking::play::Session& active,
                         libchiaking::play::Session::SystemUi state);
  static auto system_ui_name(libchiaking::play::Session::SystemUi state)
      -> std::string_view;
  void launch_progress(const libchiaking::play::LaunchProgress& progress,
                       bool playing);
  auto start_console(const Bytes& account_id, const Bytes& hardware_id,
                     libchiaking::consoles::Route route) -> Outcome;
  auto start_cloud(const Bytes& account_id, const CloudStart& start) -> Outcome;
  auto datacenter_of(const DatacenterRequest& request)
      -> std::optional<libchiaking::play::DatacenterPreference>;

  StreamListener& listener_;
  nx_bridge_log log_;
  AudioPath audio_;
  FeedbackPath feedback_;
  std::atomic<bool> speaker_to_listener_{};
#if CHIAKI_KAKUSAN
  ShareDesk shared_{*this, listener_, feedback_};
#endif

  mutable std::mutex mutex_;
  Phase phase_{Phase::created};
  bool cancelled_{};
  bool rest_refused_{};
  bool text_entry_{};
  std::uint64_t keyboard_reports_{};
  Outcome outcome_{Outcome::unrecorded()};
  std::string failure_diagnostics_;

  std::optional<libchiaking::play::LaunchProgress> last_launch_progress_;
  libchiaking::play::PictureRequest picture_;
  libchiaking::play::InternetOptions internet_;
  libchiaking::play::AccessibilityRequest accessibility_;
  libchiaking::play::ConsoleHandover handover_{
      libchiaking::play::ConsoleHandover::fresh};
  bool reconnect_after_drop_{true};
  TakionSetup takion_;
  MediaOff media_off_;
  std::atomic<bool> api_capture_{};
  std::atomic<bool> audio_3d_{};
  std::atomic<libchiaking::play::Session::SystemUi> system_ui_{
      libchiaking::play::Session::SystemUi::game};
  std::uint32_t attempt_{1};
  std::atomic<bool> played_{};
  libchiaking::platform::StopSource start_stop_;
  std::uint64_t motion_resets_{};

  std::atomic<std::uint64_t> output_failures_{};
  std::atomic<int> last_output_error_{};
  std::atomic<std::uint64_t> surfaces_{};
  std::atomic<std::uint64_t> slow_video_{};
  std::atomic<std::uint64_t> slow_audio_{};
  std::atomic<std::uint64_t> delivery_gaps_{};
  std::atomic<std::uint64_t> longest_video_us_{};
  std::atomic<std::uint64_t> longest_audio_us_{};
  std::atomic<std::uint64_t> longest_gap_us_{};
  std::chrono::steady_clock::time_point last_delivered_{};
  mutable std::mutex granted_mutex_;
  std::optional<libchiaking::media::GrantedPicture> granted_;

  std::shared_ptr<Opened> core_;
  std::shared_ptr<Opened> log_owner_;
  std::shared_ptr<libchiaking::play::Session> session_;
  std::atomic<libchiaking::play::Session*> published_session_{};
};

}  // namespace chiaki_bridge
