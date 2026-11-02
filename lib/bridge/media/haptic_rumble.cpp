#include <algorithm>
#include <cmath>
#include <cstring>
#include <numbers>

#include "chiaki_bridge/media.hpp"

namespace chiaki_bridge {

auto HapticRumble::measure(std::span<const std::uint8_t> pcm) noexcept
    -> Measure {
  Measure result;
  for (std::size_t offset = 0; offset + frame_size <= pcm.size();
       offset += frame_size) {
    for (std::size_t channel = 0; channel < channels; ++channel) {
      std::int16_t sample = 0;
      std::memcpy(&sample,
                  pcm.subspan(offset + channel * sizeof(std::int16_t)).data(),
                  sizeof sample);
      const auto value = static_cast<double>(sample);
      result.power[channel] += value * value;
      result.magnitude[channel] += std::abs(value);
    }
  }
  return result;
}

auto HapticRumble::released(float level, std::uint64_t now_ms,
                            float release_ms) const noexcept -> float {
  if (level <= 0.0F || now_ms <= updated_ms_) {
    return level;
  }
  const auto elapsed = static_cast<float>(now_ms - updated_ms_);
  return level * std::exp(-elapsed / release_ms);
}

void HapticRumble::push(std::span<const std::uint8_t> pcm, float gain,
                        std::uint64_t now_ms) noexcept {
  if (pcm.size() < frame_size || pcm.size() % frame_size != 0 ||
      !std::isfinite(gain) || gain < 0.0F) {
    return;
  }
  const auto frames = static_cast<double>(pcm.size() / frame_size);
  const auto measured = measure(pcm);
  for (std::size_t channel = 0; channel < channels; ++channel) {
    const auto rms =
        static_cast<float>(std::sqrt(measured.power[channel] / frames));
    auto level = gain * rms * std::numbers::sqrt2_v<float> / full_scale;
    if (level < curve_gate) {
      level = 0.0F;
    }
    envelope_[channel] =
        std::max(level, released(envelope_[channel], now_ms, curve_release_ms));
    auto average =
        static_cast<float>(measured.magnitude[channel] / frames) / full_scale;
    if (average > linear_gate) {
      average *= gain;
    } else {
      average = 0.0F;
    }
    average_[channel] = std::max(
        average, released(average_[channel], now_ms, linear_release_ms));
  }
  updated_ms_ = std::max(updated_ms_, now_ms);
}

auto HapticRumble::curved_motor(float envelope) noexcept -> float {
  if (envelope < hold) {
    return 0.0F;
  }
  return curve_floor + (1.0F - curve_floor) *
                           std::pow(std::min(envelope, 1.0F), curve_exponent);
}

auto HapticRumble::linear_motor(float average) noexcept -> float {
  if (average < hold) {
    return 0.0F;
  }
  return std::clamp(average, linear_minimum, 1.0F);
}

auto HapticRumble::levels_of(const Levels& levels) noexcept -> RumbleLevels {
  return {.left = levels[0], .right = levels[1]};
}

auto HapticRumble::linear(std::uint64_t now_ms, float scale) const noexcept
    -> RumbleLevels {
  if (!std::isfinite(scale) || scale <= 0.0F) {
    return {};
  }
  Levels average{};
  for (std::size_t channel = 0; channel < channels; ++channel) {
    average[channel] =
        released(average_[channel], now_ms, linear_release_ms) * scale;
  }
  Levels output{};
  for (std::size_t channel = 0; channel < channels; ++channel) {
    const auto shared = average[channels - 1 - channel] * crossfeed;
    output[channel] = linear_motor(std::max(average[channel], shared));
  }
  return levels_of(output);
}

auto HapticRumble::curved(std::uint64_t now_ms, float scale) const noexcept
    -> RumbleLevels {
  if (!std::isfinite(scale) || scale <= 0.0F) {
    return {};
  }
  Levels output{};
  for (std::size_t channel = 0; channel < channels; ++channel) {
    output[channel] = curved_motor(
        released(envelope_[channel], now_ms, curve_release_ms) * scale);
  }
  return levels_of(output);
}

void HapticRumble::reset() noexcept { *this = HapticRumble{}; }

}  // namespace chiaki_bridge
