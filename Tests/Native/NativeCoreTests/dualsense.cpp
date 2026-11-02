#include "dualsense.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <span>

using chiaki_bridge::DualSenseReport;
using chiaki_bridge::WaveStream;

using Pcm = std::span<const std::uint8_t>;
using Wave = std::array<std::uint8_t, DualSenseReport::wave_bytes>;
using Effect = std::array<std::uint8_t, DualSenseReport::effect_size>;

static constexpr std::size_t held_frames = 96;

static int test_wave_stream(void) {
  std::array<std::uint8_t, 256> pcm{};
  pcm[0] = 0xff;
  pcm[1] = 0x7f;
  pcm[2] = 0;
  pcm[3] = 0x80;
  Wave packet{};
  WaveStream stream;
  stream.reset();
  if (stream.peek(packet) || !stream.push(Pcm{pcm}, 1, 100) ||
      stream.frames() != 64 || !stream.peek(packet)) {
    return 20;
  }
  if (packet[0] != 0x31 || packet[2] != 0x91 || packet[3] != 6 ||
      packet[4] != 0x7e || packet[5] != DualSenseReport::wave_target_ms ||
      packet[10] != 0x92 || packet[11] != 62 || packet[12] != 127 ||
      packet[13] != 128 || packet[14] || packet[74]) {
    return 21;
  }
  stream.consume();
  stream.consume();
  if (stream.frames() != 2 || stream.peek(packet)) {
    return 22;
  }
  if (!stream.push(Pcm{pcm}, 1, 200) || stream.frames() != 64) {
    return 23;
  }
  for (int index = 0; index < 3; index++) {
    if (!stream.push(Pcm{pcm}, 1, 210)) {
      return 37;
    }
  }
  if (stream.frames() != held_frames ||
      stream.push(Pcm{pcm}.first(255), 1, 210) ||
      stream.push(Pcm{pcm}, NAN, 210) || stream.push(Pcm{}, 1, 210) ||
      stream.push(Pcm{pcm}, -1, 210)) {
    return 38;
  }
  stream.reset();
  if (!stream.push(Pcm{pcm}, 0, 300) || stream.frames() != 0 ||
      stream.peek(packet)) {
    return 39;
  }
  if (!stream.push(Pcm{pcm}, 1, 300) || stream.frames() != 64) {
    return 72;
  }
  stream.expire(300 + WaveStream::stale_ms);
  if (stream.frames() != 64) {
    return 70;
  }
  stream.expire(301 + WaveStream::stale_ms);
  if (stream.frames() != 0 || stream.peek(packet)) {
    return 71;
  }
  std::array<std::uint8_t, 256> loud{};
  const std::array<std::uint8_t, 128> quiet{};
  for (std::size_t index = 0; index < loud.size(); index += 2) {
    loud[index] = 0xff;
    loud[index + 1] = 0x7f;
  }
  if (!stream.push(Pcm{loud}, 1, 400) || !stream.push(Pcm{quiet}, 1, 400) ||
      !stream.push(Pcm{loud}.first(quiet.size()), 1, 400) ||
      stream.frames() != held_frames) {
    return 73;
  }
  while (stream.peek(packet)) {
    for (std::size_t index = 0; index < DualSenseReport::wave_frames * 2;
         index++) {
      if (packet[12 + index] != 127) {
        return 74;
      }
    }
    stream.consume();
  }
  return 0;
}

static int test_effect_reports(void) {
  std::array<std::uint8_t, DualSenseReport::trigger_size> triggers{};
  for (std::size_t index = 0; index < triggers.size(); index++) {
    triggers[index] = static_cast<std::uint8_t>(index);
  }
  Effect effect{};
  DualSenseReport::triggers(triggers, effect);
  if (effect[0] != 12 ||
      std::memcmp(effect.data() + 10, triggers.data() + 11, 11) ||
      std::memcmp(effect.data() + 21, triggers.data(), 11)) {
    return 24;
  }
  if (DualSenseReport::power_reduction(0, 0) != 0xff ||
      DualSenseReport::power_reduction(1, 1) != 0x00 ||
      DualSenseReport::power_reduction(2, 2) != 0x62 ||
      DualSenseReport::power_reduction(3, 3) != 0x93) {
    return 75;
  }
  Effect rumble{};
  DualSenseReport::rumble(200, 90, true, 0x62, rumble);
  if (rumble[0] != 0x02 || rumble[1] != 0x40 || rumble[3] != 200 ||
      rumble[2] != 90 || rumble[36] != 0x62 || rumble[38] != 0x04) {
    return 76;
  }
  DualSenseReport::rumble(200, 90, false, 0x00, rumble);
  if (rumble[0] != 0x03 || rumble[3] != 100 || rumble[2] != 45 || rumble[38] ||
      rumble[36]) {
    return 77;
  }
  DualSenseReport::rumble(0, 0, true, 0x0f, rumble);
  if (rumble[0] || rumble[38] || rumble[2] || rumble[3] || rumble[1] != 0x40 ||
      rumble[36] != 0x0f) {
    return 78;
  }
  DualSenseReport::rumble(0, 0, false, 0x00, rumble);
  if (rumble[0] || rumble[38] || rumble[1] != 0x40) {
    return 79;
  }
  Effect light{};
  DualSenseReport::mic_light(true, light);
  if (light[1] != 0x01 || light[8] != 0x01 || light[0] || light[9] ||
      light[10]) {
    return 27;
  }
  DualSenseReport::mic_light(false, light);
  if (light[1] != 0x01 || light[8] || light[9]) {
    return 28;
  }
  Effect speaker{};
  DualSenseReport::speaker(true, speaker);
  if (speaker[0] != 0xa0 || speaker[5] != 0x60 || speaker[7] != 0x30 ||
      speaker[1] || speaker[8]) {
    return 80;
  }
  DualSenseReport::speaker(false, speaker);
  if (speaker[0] != 0xa0 || speaker[5] || speaker[7]) {
    return 81;
  }
  return 0;
}

int main(void) {
  int (*tests[])(void) = {
      test_wave_stream,
      test_effect_reports,
  };
  for (size_t index = 0; index < sizeof tests / sizeof tests[0]; index++) {
    int result = tests[index]();
    if (result) {
      std::fprintf(stderr, "dualsense report test failed: %d\n", result);
      return result;
    }
  }
  std::puts("PASS: waveform PCM encoding and DualSense effect reports");
  return 0;
}
