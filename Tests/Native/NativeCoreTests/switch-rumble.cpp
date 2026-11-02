#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "switch_rumble.hpp"

using chiaki_bridge::SwitchRumble;

static int test_amplitude_steps_follow_the_rumble_table(void) {
  if (SwitchRumble::step(0.0f) != 0 || SwitchRumble::step(-1.0f) != 0) {
    return 1;
  }
  if (SwitchRumble::step(1.0f) != 100 || SwitchRumble::step(2.0f) != 100) {
    return 2;
  }
  if (SwitchRumble::step(514.0f / 65535.0f) != 1 ||
      SwitchRumble::step(0.5f) != 68) {
    return 3;
  }
  return 0;
}

static int test_silence_is_the_neutral_packet(void) {
  std::array<std::uint8_t, SwitchRumble::actuator_size> actuator{};
  SwitchRumble::actuator(0.0f, actuator);
  const std::array<std::uint8_t, SwitchRumble::actuator_size> neutral{
      0x00, 0x01, 0x40, 0x40};
  if (actuator != neutral) {
    return 10;
  }
  return 0;
}

static int test_full_strength_matches_sdls_both_band_tone(void) {
  std::array<std::uint8_t, SwitchRumble::actuator_size> actuator{};
  SwitchRumble::actuator(1.0f, actuator);
  const std::array<std::uint8_t, SwitchRumble::actuator_size> full{0x74, 0xC8,
                                                                   0x3D, 0x72};
  if (actuator != full) {
    return 20;
  }
  SwitchRumble::actuator(514.0f / 65535.0f, actuator);
  const std::array<std::uint8_t, SwitchRumble::actuator_size> faint{0x74, 0x02,
                                                                    0xBD, 0x40};
  if (actuator != faint) {
    return 21;
  }
  return 0;
}

static int test_packet_carries_each_side_separately(void) {
  std::array<std::uint8_t, SwitchRumble::packet_size> packet{};
  SwitchRumble::packet({1.0f, 0.0f}, packet);
  if (packet[0] != 0x10 || packet[1] != 0x00) {
    return 30;
  }
  std::array<std::uint8_t, SwitchRumble::actuator_size> left{};
  std::array<std::uint8_t, SwitchRumble::actuator_size> right{};
  SwitchRumble::actuator(1.0f, left);
  SwitchRumble::actuator(0.0f, right);
  if (std::memcmp(packet.data() + 2, left.data(), left.size()) != 0 ||
      std::memcmp(packet.data() + 6, right.data(), right.size()) != 0) {
    return 31;
  }
  return 0;
}

int main(void) {
  int (*tests[])(void) = {
      test_amplitude_steps_follow_the_rumble_table,
      test_silence_is_the_neutral_packet,
      test_full_strength_matches_sdls_both_band_tone,
      test_packet_carries_each_side_separately,
  };
  for (size_t index = 0; index < sizeof tests / sizeof tests[0]; index++) {
    int result = tests[index]();
    if (result) {
      std::fprintf(stderr, "switch rumble test failed: %d\n", result);
      return result;
    }
  }
  return 0;
}
