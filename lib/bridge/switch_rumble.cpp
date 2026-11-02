#include "switch_rumble.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>

namespace chiaki_bridge {

auto SwitchRumble::step(float amplitude) noexcept -> std::uint8_t {
  if (!std::isfinite(amplitude) || amplitude <= 0.0F) {
    return 0;
  }
  const auto value = static_cast<std::uint32_t>(
      std::lround(std::min(amplitude, 1.0F) * full_amplitude));
  const auto found = std::ranges::lower_bound(amplitude_steps, value);
  if (found == amplitude_steps.end()) {
    return largest_step;
  }
  return static_cast<std::uint8_t>(
      std::distance(amplitude_steps.begin(), found));
}

void SwitchRumble::pack(const Tone& tone, Actuator output) noexcept {
  output[0] = static_cast<std::uint8_t>(tone.high & 0xFFU);
  output[1] =
      static_cast<std::uint8_t>(tone.high_amplitude | ((tone.high >> 8U) & 1U));
  output[2] = static_cast<std::uint8_t>(tone.low |
                                        ((tone.low_amplitude >> 8U) & 0x80U));
  output[3] = static_cast<std::uint8_t>(tone.low_amplitude & 0xFFU);
}

void SwitchRumble::actuator(float amplitude, Actuator output) noexcept {
  const auto level = step(amplitude);
  if (level == 0) {
    pack(neutral, output);
    return;
  }
  auto odd = std::uint16_t{0};
  if ((level & 1U) != 0) {
    odd = low_amplitude_odd;
  }
  pack({.high = tone_high,
        .high_amplitude = static_cast<std::uint8_t>(level * 2),
        .low = tone_low,
        .low_amplitude =
            static_cast<std::uint16_t>((level / 2 + low_amplitude_base) | odd)},
       output);
}

void SwitchRumble::packet(std::array<float, 2> amplitude,
                          Packet output) noexcept {
  std::ranges::fill(output, std::uint8_t{0});
  output[0] = packet_command;
  for (std::size_t side = 0; side < amplitude.size(); ++side) {
    actuator(amplitude[side],
             output.subspan(first_actuator + side * actuator_size)
                 .first<actuator_size>());
  }
}

}  // namespace chiaki_bridge
