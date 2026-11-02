#pragma once

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <libchiaking/play_types.hpp>
#include <memory>
#include <optional>
#include <span>
#include <string>

#include "core.hpp"

namespace chiaki_bridge {

struct ControllerMotion {
  float gyro_x;
  float gyro_y;
  float gyro_z;
  float accel_x;
  float accel_y;
  float accel_z;
  float orient_x;
  float orient_y;
  float orient_z;
  float orient_w;
};

class MotionFusion {
 public:
  void accelerometer(float x, float y, float z,
                     std::uint64_t timestamp_us) noexcept;
  void gyroscope(float x, float y, float z,
                 std::uint64_t timestamp_us) noexcept;
  void recentre() noexcept;
  void tune(bool tilt_correction, bool angular_velocity_deadband) noexcept;
  auto read() const noexcept -> std::optional<ControllerMotion>;

 private:
  static auto stamp(std::uint64_t timestamp_us) noexcept
      -> std::chrono::microseconds;

  libchiaking::controllers::MotionTracker tracker_;
};

using MicrophonePcm = std::span<const std::int16_t>;
using MicrophoneFrame = std::span<std::uint8_t>;

class MicrophoneEncoder {
 public:
  static constexpr auto sample_rate() noexcept -> std::uint32_t {
    return libchiaking::media::MicrophoneEncoder::sample_rate;
  }
  static constexpr auto channels() noexcept -> std::size_t {
    return libchiaking::media::MicrophoneEncoder::channels;
  }
  static constexpr auto samples_per_frame() noexcept -> std::size_t {
    return libchiaking::media::MicrophoneEncoder::samples_per_frame;
  }
  static constexpr auto frame_size() noexcept -> std::size_t {
    return libchiaking::media::MicrophoneEncoder::frame_size;
  }

  static auto create() -> std::optional<MicrophoneEncoder>;

  auto encode(MicrophonePcm pcm, MicrophoneFrame frame) -> bool;

 private:
  using Encoder = libchiaking::media::MicrophoneEncoder;

  explicit MicrophoneEncoder(std::shared_ptr<Encoder> encoder) noexcept;

  std::shared_ptr<Encoder> encoder_;
};

using MicrophoneSamples = std::span<std::int16_t>;

class MicrophoneQueue {
 public:
  static auto create(std::uint32_t channels, std::uint32_t sample_rate,
                     std::uint32_t target_ms) -> std::optional<MicrophoneQueue>;

  void push(MicrophonePcm samples) const noexcept;
  auto pull(MicrophoneSamples samples) const noexcept -> std::size_t;
  auto buffered_frames() const noexcept -> std::uint64_t;

 private:
  using Playout = libchiaking::media::AudioPlayout;

  explicit MicrophoneQueue(std::shared_ptr<Playout> playout) noexcept;

  std::shared_ptr<Playout> playout_;
};

class ConsoleFeedback {
 public:
  static auto scale_of(std::uint8_t level) noexcept -> float;
  static auto scale_of(
      libchiaking::controllers::FeedbackIntensity intensity) noexcept -> float;
};

struct RumbleLevels {
  float left;
  float right;
};

class HapticRumble {
 public:
  void push(std::span<const std::uint8_t> pcm, float gain,
            std::uint64_t now_ms) noexcept;
  auto linear(std::uint64_t now_ms, float scale) const noexcept -> RumbleLevels;
  auto curved(std::uint64_t now_ms, float scale) const noexcept -> RumbleLevels;
  void reset() noexcept;

 private:
  static constexpr std::size_t channels = 2;
  static constexpr std::size_t frame_size = channels * sizeof(std::int16_t);
  static constexpr float full_scale = 32768.0F;
  static constexpr float curve_release_ms = 60.0F;
  static constexpr float curve_gate = 0.004F;
  static constexpr float curve_floor = 0.06F;
  static constexpr float curve_exponent = 0.6F;
  static constexpr float hold = 0.001F;
  static constexpr float crossfeed = 0.35F;
  static constexpr float linear_release_ms = 30.0F;
  static constexpr float linear_gate = 50.0F / full_scale;
  static constexpr float linear_minimum = 512.0F / 65535.0F;

  using Levels = std::array<float, channels>;

  struct Measure {
    std::array<double, channels> power{};
    std::array<double, channels> magnitude{};
  };

  static auto measure(std::span<const std::uint8_t> pcm) noexcept -> Measure;
  static auto curved_motor(float envelope) noexcept -> float;
  static auto linear_motor(float average) noexcept -> float;
  static auto levels_of(const Levels& levels) noexcept -> RumbleLevels;

  auto released(float level, std::uint64_t now_ms,
                float release_ms) const noexcept -> float;

  Levels envelope_{};
  Levels average_{};
  std::uint64_t updated_ms_{};
};

class HapticAudio {
 public:
  static constexpr std::size_t block_size = 256;

  using Block = std::span<const std::uint8_t, block_size>;

  static auto open() -> std::optional<HapticAudio>;

  HapticAudio(HapticAudio&&) noexcept;
  auto operator=(HapticAudio&&) noexcept -> HapticAudio&;
  HapticAudio(const HapticAudio&) = delete;
  auto operator=(const HapticAudio&) -> HapticAudio& = delete;
  ~HapticAudio();

  auto push(Block pcm, float gain) -> bool;
  auto push_speaker(std::span<const std::int16_t> pcm, float gain) -> bool;
  auto has_speaker() const noexcept -> bool;

 private:
  class Device;

  explicit HapticAudio(std::unique_ptr<Device> device) noexcept;

  std::unique_ptr<Device> device_;
};

using AudioOutputChanged = void (*)(void* context);

class AudioOutputs {
 public:
  static auto names() -> Texts;
  static auto is_headphones(const std::string& device) -> bool;
  static auto dualsense_ready() -> bool;
};

class AudioOutputWatch {
 public:
  static auto start(AudioOutputChanged changed, void* context)
      -> AudioOutputWatch;

  void stop() noexcept;

 private:
  class Listening;

  explicit AudioOutputWatch(std::shared_ptr<Listening> listening) noexcept;

  std::shared_ptr<Listening> listening_;
};

}  // namespace chiaki_bridge
