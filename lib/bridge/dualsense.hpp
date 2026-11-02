#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>

namespace chiaki_bridge {

/// Builds the DualSense output reports the input thread sends.
class DualSenseReport {
 public:
  /// The size of a haptic waveform report.
  static constexpr std::size_t wave_bytes = 78;
  /// The stereo frames a waveform report carries.
  static constexpr std::size_t wave_frames = 31;
  /// The interval a waveform report asks the pad to play it over.
  static constexpr std::uint8_t wave_target_ms = 16;
  /// The size of an effects report.
  static constexpr std::size_t effect_size = 47;
  /// The size of the console's adaptive trigger effects.
  static constexpr std::size_t trigger_size = 22;

  /// A waveform report.
  using Wave = std::span<std::uint8_t, wave_bytes>;
  /// An effects report.
  using Effect = std::span<std::uint8_t, effect_size>;
  /// The console's adaptive trigger effects.
  using Triggers = std::span<const std::uint8_t, trigger_size>;
  /// The interleaved samples of one waveform report.
  using WaveSamples = std::span<const std::int8_t, wave_frames * 2>;

  /// Writes the waveform report for the samples.
  static void waveform(WaveSamples samples, Wave output) noexcept;
  /// Writes the effects report that sets the adaptive triggers.
  static void triggers(Triggers effects, Effect output) noexcept;
  /// Writes the effects report that turns the microphone light on or off.
  static void mic_light(bool lit, Effect output) noexcept;
  /// Writes the effects report that routes audio to the speaker or not.
  static void speaker(bool enabled, Effect output) noexcept;
  /// The power reduction byte for the console's trigger and haptic
  /// intensities.
  static auto power_reduction(std::uint8_t trigger_intensity,
                              std::uint8_t haptic_intensity) noexcept
      -> std::uint8_t;
  /// Writes the effects report that sets the rumble motors.
  static void rumble(std::uint8_t left, std::uint8_t right, bool enhanced,
                     std::uint8_t reduction, Effect output) noexcept;

 private:
  static constexpr std::size_t trigger_half = trigger_size / 2;
  static constexpr std::uint8_t speaker_volume_valid = 0x20;
  static constexpr std::uint8_t audio_route_valid = 0x80;
  static constexpr std::uint8_t speaker_volume = 0x60;
  static constexpr std::uint8_t output_path_shift = 4;
  static constexpr std::uint8_t speaker_from_right = 3;
};

/// Holds the haptic audio waiting to go to a DualSense, a waveform report at a
/// time.
class WaveStream {
 public:
  /// How long held audio stays playable without new audio.
  static constexpr std::uint64_t stale_ms = 30;

  /// Drops everything held.
  void reset() noexcept;
  /// Drops the held audio when it went stale.
  void expire(std::uint64_t now_ms) noexcept;
  /// Adds 16-bit stereo audio scaled by the gain, giving whether it was taken.
  auto push(std::span<const std::uint8_t> pcm, float gain,
            std::uint64_t now_ms) noexcept -> bool;
  /// Writes the next waveform report, giving whether enough audio was held.
  auto peek(DualSenseReport::Wave output) const noexcept -> bool;
  /// Drops the audio of the report `peek` wrote.
  void consume() noexcept;
  /// How many stereo frames are held.
  auto frames() const noexcept -> std::size_t { return frames_; }

 private:
  static constexpr std::size_t channels = 2;
  static constexpr std::size_t bytes_per_frame = channels * 2;
  static constexpr std::size_t capacity = 96;
  static constexpr int gate_peak = 2;
  static constexpr float largest_gain = 4.0F;

  static auto sample_byte(std::span<const std::uint8_t, 2> pcm,
                          float gain) noexcept -> std::int8_t;
  static auto frame_energy(std::span<const std::int8_t> samples,
                           std::size_t frame) noexcept -> long;
  static auto quietest_run(std::span<const std::int8_t> samples,
                           std::size_t count, std::size_t length) noexcept
      -> std::size_t;

  std::array<std::int8_t, capacity * channels> samples_{};
  std::size_t frames_{};
  std::uint64_t updated_ms_{};
};

}  // namespace chiaki_bridge
