#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <libchiaking/play.hpp>
#include <memory>
#include <optional>
#include <span>
#include <string_view>
#include <vector>

#include "audio.h"
#include "bridge_log.hpp"
#include "chiaki_bridge/play.hpp"
#include "chiaki_bridge/stream_facts.hpp"
#include "controller_speaker_mix.hpp"

namespace chiaki_bridge {

class AudioPath {
 public:
  static constexpr int bad_argument = -1;

  explicit AudioPath(nx_bridge_log& log);

  static auto supports(StreamTarget target, std::uint32_t channels) noexcept
      -> bool;
  static auto supports_3d(StreamTarget target) noexcept -> bool;

  auto request_channels(std::uint32_t channels) noexcept -> bool;
  void request_controller_speaker(bool enabled) noexcept;
  auto negotiate(libchiaking::play::SoundRequest granted,
                 std::string_view target) -> libchiaking::play::SoundRequest;
  auto requested() const noexcept -> libchiaking::play::SoundRequest;
  auto configure(const libchiaking::media::AudioFormat& format, bool raw_pcm)
      -> bool;
  auto deliver(std::span<const std::byte> packet)
      -> libchiaking::media::AudioResult;
  auto configure_voice(const libchiaking::media::AudioFormat& format,
                       bool raw_pcm) -> bool;
  auto deliver_voice(std::span<const std::byte> packet)
      -> libchiaking::media::AudioResult;
  auto decode_speaker(std::uint8_t seat, std::span<const std::byte> packet)
      -> std::optional<std::span<const std::int16_t>>;
  void hold_speaker(std::uint8_t seat, std::span<const std::int16_t> pcm);
  void stop();

  void set_gain(float gain) noexcept;
  void set_voice_gain(float gain) noexcept;
  void set_buffer(std::uint32_t milliseconds) noexcept;
  void set_output(std::string_view name);
  void set_spatial(bool enabled) noexcept;
  auto statistics() const noexcept -> AudioStatistics;

 private:
  struct Release {
    void operator()(nx_audio* audio) const noexcept;
  };

  static auto surround_name(std::uint32_t channels) noexcept
      -> std::string_view;
  static auto layout_name(
      libchiaking::media::AudioDecoder::Layout layout) noexcept
      -> std::string_view;
  static auto state_of(nx_audio_state state) noexcept -> AudioOutputState;

  auto rejected(int code) noexcept -> libchiaking::media::AudioResult;
  void observe_activity(std::span<const std::int16_t> pcm,
                        std::size_t channels) noexcept;
  auto with_side_audio(std::span<const std::int16_t> pcm, std::size_t channels)
      -> std::span<const std::int16_t>;

  static constexpr std::uint64_t activity_window_frames = 48000;
  static constexpr std::size_t max_voice_frames = 4800;
  static constexpr std::size_t trimmed_voice_frames = 1920;
  static constexpr std::size_t voice_target_channels = 2;

  nx_bridge_log& log_;
  std::unique_ptr<nx_audio, Release> output_;
  std::optional<libchiaking::media::AudioDecoder> decoder_;
  std::optional<libchiaking::media::AudioDecoder> voice_decoder_;
  std::deque<std::int16_t> voice_;
  ControllerSpeakerMix speaker_;
  std::atomic<float> voice_gain_{1};
  std::vector<std::int16_t> mixed_;
  std::atomic<std::uint32_t> requested_channels_{};
  std::atomic<bool> controller_speaker_{};
  std::atomic<std::uint64_t> speaker_failures_{};
  std::atomic<std::uint64_t> received_format_{};
  std::uint32_t surround_requested_{};
  std::uint32_t surround_reported_{};
  std::uint32_t channels_{};
  std::atomic<std::uint64_t> failures_{};
  std::atomic<std::uint64_t> concealed_{};
  std::atomic<int> last_error_{};
  std::atomic<std::uint32_t> active_channels_{};
  std::uint32_t activity_mask_{};
  std::uint64_t activity_frames_{};
};

}  // namespace chiaki_bridge
