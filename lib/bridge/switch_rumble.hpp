#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>

namespace chiaki_bridge {

class SwitchRumble {
 public:
  static constexpr std::size_t actuator_size = 4;
  static constexpr std::size_t packet_size = 10;
  static constexpr std::uint8_t largest_step = 100;

  using Actuator = std::span<std::uint8_t, actuator_size>;
  using Packet = std::span<std::uint8_t, packet_size>;

  static auto step(float amplitude) noexcept -> std::uint8_t;
  static void actuator(float amplitude, Actuator output) noexcept;
  static void packet(std::array<float, 2> amplitude, Packet output) noexcept;

 private:
  struct Tone {
    std::uint16_t high;
    std::uint8_t high_amplitude;
    std::uint8_t low;
    std::uint16_t low_amplitude;
  };

  static constexpr std::uint8_t packet_command = 0x10;
  static constexpr std::size_t first_actuator = 2;
  static constexpr std::uint16_t tone_high = 0x0074;
  static constexpr std::uint8_t tone_low = 0x3D;
  static constexpr Tone neutral{.high = 0x0100,
                                .high_amplitude = 0,
                                .low = 0x40,
                                .low_amplitude = 0x0040};

  static constexpr std::array<std::uint16_t, largest_step + 1> amplitude_steps{
      0,     514,   775,   921,   1096,  1303,  1550,  1843,  2192,  2606,
      3100,  3686,  4383,  5213,  6199,  7372,  7698,  8039,  8395,  8767,
      9155,  9560,  9984,  10426, 10887, 11369, 11873, 12398, 12947, 13520,
      14119, 14744, 15067, 15397, 15734, 16079, 16431, 16790, 17158, 17534,
      17918, 18310, 18711, 19121, 19540, 19967, 20405, 20851, 21308, 21775,
      22251, 22739, 23236, 23745, 24265, 24797, 25340, 25894, 26462, 27041,
      27633, 28238, 28856, 29488, 30134, 30794, 31468, 32157, 32861, 33581,
      34316, 35068, 35836, 36620, 37422, 38242, 39079, 39935, 40809, 41703,
      42616, 43549, 44503, 45477, 46473, 47491, 48531, 49593, 50679, 51789,
      52923, 54082, 55266, 56476, 57713, 58977, 60268, 61588, 62936, 64315,
      65535};
  static constexpr float full_amplitude = 65535.0F;
  static constexpr std::uint16_t low_amplitude_base = 0x40;
  static constexpr std::uint16_t low_amplitude_odd = 0x8000;

  static void pack(const Tone& tone, Actuator output) noexcept;
};

}  // namespace chiaki_bridge
