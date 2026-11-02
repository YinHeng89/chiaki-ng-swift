#include "dualsense.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <span>

namespace chiaki_bridge {

void DualSenseReport::waveform(WaveSamples samples, Wave output) noexcept {
  std::ranges::fill(output, std::uint8_t{0});
  output[0] = 0x31;
  output[2] = 0x91;
  output[3] = 6;
  output[4] = 0x7e;
  std::fill_n(output.begin() + 5, 4, wave_target_ms);
  output[10] = 0x92;
  output[11] = wave_frames * 2;
  std::ranges::transform(samples, output.begin() + 12, [](std::int8_t value) {
    return static_cast<std::uint8_t>(value);
  });
}

void DualSenseReport::triggers(Triggers effects, Effect output) noexcept {
  std::ranges::fill(output, std::uint8_t{0});
  output[0] = 0x0c;
  std::ranges::copy(effects.subspan<trigger_half, trigger_half>(),
                    output.begin() + 10);
  std::ranges::copy(effects.first<trigger_half>(), output.begin() + 21);
}

void DualSenseReport::mic_light(bool lit, Effect output) noexcept {
  std::ranges::fill(output, std::uint8_t{0});
  output[1] = 0x01;
  output[8] = lit ? 0x01 : 0x00;
}

void DualSenseReport::speaker(bool enabled, Effect output) noexcept {
  std::ranges::fill(output, std::uint8_t{0});
  output[0] = speaker_volume_valid | audio_route_valid;
  if (enabled) {
    output[5] = speaker_volume;
    output[7] = speaker_from_right << output_path_shift;
  }
}

auto DualSenseReport::power_reduction(std::uint8_t trigger_intensity,
                                      std::uint8_t haptic_intensity) noexcept
    -> std::uint8_t {
  static constexpr std::array<std::uint8_t, 4> trigger_steps{0xf0, 0x00, 0x60,
                                                             0x90};
  static constexpr std::array<std::uint8_t, 4> rumble_steps{0x0f, 0x00, 0x02,
                                                            0x03};
  return trigger_steps[trigger_intensity & 3U] |
         rumble_steps[haptic_intensity & 3U];
}

void DualSenseReport::rumble(std::uint8_t left, std::uint8_t right,
                             bool enhanced, std::uint8_t reduction,
                             Effect output) noexcept {
  std::ranges::fill(output, std::uint8_t{0});
  output[1] |= 0x40;
  output[36] = reduction;
  if (left == 0 && right == 0) {
    return;
  }
  if (enhanced) {
    output[38] |= 0x04;
    output[3] = left;
    output[2] = right;
  } else {
    output[0] |= 0x01;
    output[3] = left >> 1;
    output[2] = right >> 1;
  }
  output[0] |= 0x02;
}

void WaveStream::reset() noexcept {
  frames_ = 0;
  updated_ms_ = 0;
}

void WaveStream::expire(std::uint64_t now_ms) noexcept {
  if (frames_ != 0 && now_ms - updated_ms_ > stale_ms) {
    frames_ = 0;
  }
}

auto WaveStream::sample_byte(std::span<const std::uint8_t, 2> pcm,
                             float gain) noexcept -> std::int8_t {
  const auto sample = static_cast<std::int16_t>(pcm[0] | (pcm[1] << 8));
  const auto value =
      static_cast<int>(static_cast<float>(sample) * gain / 256.0F);
  return static_cast<std::int8_t>(std::clamp(value, -128, 127));
}

auto WaveStream::frame_energy(std::span<const std::int8_t> samples,
                              std::size_t frame) noexcept -> long {
  return std::abs(samples[frame * channels]) +
         std::abs(samples[frame * channels + 1]);
}

auto WaveStream::quietest_run(std::span<const std::int8_t> samples,
                              std::size_t count, std::size_t length) noexcept
    -> std::size_t {
  long energy = 0;
  for (std::size_t index = 0; index < length; ++index) {
    energy += frame_energy(samples, index);
  }
  long quietest = energy;
  std::size_t start = 0;
  for (std::size_t first = 1; first + length <= count; ++first) {
    energy += frame_energy(samples, first + length - 1) -
              frame_energy(samples, first - 1);
    if (energy < quietest) {
      quietest = energy;
      start = first;
    }
  }
  return start;
}

auto WaveStream::push(std::span<const std::uint8_t> pcm, float gain,
                      std::uint64_t now_ms) noexcept -> bool {
  if (pcm.empty() || pcm.size() % bytes_per_frame != 0 ||
      pcm.size() > capacity * bytes_per_frame || !std::isfinite(gain) ||
      gain < 0 || gain > largest_gain) {
    return false;
  }
  expire(now_ms);
  const std::size_t held = frames_;
  const std::size_t incoming = pcm.size() / bytes_per_frame;
  std::array<std::int8_t, capacity * 2 * channels> samples{};
  std::copy_n(samples_.begin(), held * channels, samples.begin());
  int peak = 0;
  for (std::size_t index = 0; index < incoming * channels; ++index) {
    const auto value = sample_byte(pcm.subspan(index * 2).first<2>(), gain);
    samples[held * channels + index] = value;
    peak = std::max(peak, std::abs(static_cast<int>(value)));
  }
  if (held == 0 && peak <= gate_peak) {
    return true;
  }
  std::size_t total = held + incoming;
  if (total > capacity) {
    const std::size_t excess = total - capacity;
    const std::size_t start = quietest_run(samples, total, excess);
    std::copy(samples.begin() +
                  static_cast<std::ptrdiff_t>((start + excess) * channels),
              samples.begin() + static_cast<std::ptrdiff_t>(total * channels),
              samples.begin() + static_cast<std::ptrdiff_t>(start * channels));
    total = capacity;
  }
  std::copy_n(samples.begin(), total * channels, samples_.begin());
  frames_ = total;
  updated_ms_ = now_ms;
  return true;
}

auto WaveStream::peek(DualSenseReport::Wave output) const noexcept -> bool {
  if (frames_ < DualSenseReport::wave_frames) {
    return false;
  }
  DualSenseReport::waveform(
      DualSenseReport::WaveSamples{samples_.data(),
                                   DualSenseReport::wave_frames * 2},
      output);
  return true;
}

void WaveStream::consume() noexcept {
  if (frames_ < DualSenseReport::wave_frames) {
    return;
  }
  const std::size_t remaining = frames_ - DualSenseReport::wave_frames;
  std::copy_n(samples_.begin() + DualSenseReport::wave_frames * channels,
              remaining * channels, samples_.begin());
  frames_ = remaining;
}

}  // namespace chiaki_bridge
