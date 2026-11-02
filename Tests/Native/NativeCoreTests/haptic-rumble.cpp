#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <span>

#include "chiaki_bridge/media.hpp"

using chiaki_bridge::HapticRumble;
using chiaki_bridge::RumbleLevels;

static void tone(uint8_t pcm[256], int16_t left, int16_t right) {
  for (int frame = 0; frame < 64; frame++) {
    int16_t sign = frame % 2 ? -1 : 1;
    int16_t samples[2] = {(int16_t)(left * sign), (int16_t)(right * sign)};
    memcpy(pcm + frame * 4, samples, sizeof samples);
  }
}

static int test_silence_stays_off(void) {
  HapticRumble rumble;
  uint8_t pcm[256] = {0};
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 10);
  RumbleLevels output{1.0F, 1.0F};
  output = rumble.linear(10, 1.0f);
  if (output.left != 0.0f || output.right != 0.0f) {
    return 1;
  }
  tone(pcm, 40, 40);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 20);
  output = rumble.linear(20, 1.0f);
  if (output.left != 0.0f || output.right != 0.0f) {
    return 2;
  }
  return 0;
}

static int test_channels_drive_their_own_motor(void) {
  HapticRumble rumble;
  uint8_t pcm[256];
  tone(pcm, 16000, 0);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 100);
  RumbleLevels output{};
  output = rumble.linear(100, 1.0f);
  if (!(output.left > 0.45f && output.left < 0.55f)) {
    return 10;
  }
  if (!(output.right > 0.0f && output.right < output.left)) {
    return 11;
  }
  tone(pcm, 0, 16000);
  rumble.reset();
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 100);
  RumbleLevels mirrored{};
  mirrored = rumble.linear(100, 1.0f);
  if (std::fabs(mirrored.left - output.right) > 0.0001f ||
      std::fabs(mirrored.right - output.left) > 0.0001f) {
    return 12;
  }
  return 0;
}

static int test_gain_scales_and_saturates(void) {
  HapticRumble rumble;
  uint8_t pcm[256];
  tone(pcm, 4000, 4000);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 50);
  RumbleLevels normal{};
  normal = rumble.linear(50, 1.0f);
  rumble.reset();
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 2.4f, 50);
  RumbleLevels strong{};
  strong = rumble.linear(50, 1.0f);
  if (!(strong.left > normal.left)) {
    return 20;
  }
  rumble.reset();
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 0.0f, 50);
  RumbleLevels muted{};
  muted = rumble.linear(50, 1.0f);
  if (muted.left != 0.0f || muted.right != 0.0f) {
    return 21;
  }
  tone(pcm, 32767, 32767);
  rumble.reset();
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 2.4f, 50);
  RumbleLevels full{};
  full = rumble.linear(50, 1.0f);
  if (full.left < 0.999f || full.left > 1.0f || full.right < 0.999f ||
      full.right > 1.0f) {
    return 22;
  }
  return 0;
}

static int test_console_scale_reduces_the_motors(void) {
  HapticRumble rumble;
  uint8_t pcm[256];
  tone(pcm, 12000, 12000);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 10);
  RumbleLevels strong{};
  RumbleLevels weak{};
  RumbleLevels off{};
  strong = rumble.linear(10, 1.0f);
  weak = rumble.linear(10, 0.33f);
  off = rumble.linear(10, 0.0f);
  if (!(weak.left > 0.0f && weak.left < strong.left) || off.left != 0.0f ||
      off.right != 0.0f) {
    return 50;
  }
  return 0;
}

static int test_release_fades_after_the_haptics_stop(void) {
  HapticRumble rumble;
  uint8_t pcm[256];
  tone(pcm, 12000, 12000);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 1000);
  RumbleLevels start{};
  RumbleLevels soon{};
  RumbleLevels later{};
  start = rumble.linear(1000, 1.0f);
  soon = rumble.linear(1030, 1.0f);
  later = rumble.linear(1500, 1.0f);
  if (!(soon.left > 0.0f && soon.left < start.left)) {
    return 30;
  }
  if (later.left != 0.0f || later.right != 0.0f) {
    return 31;
  }
  RumbleLevels tail{};
  tail = rumble.linear(1060, 1.0f);
  if (!(tail.left > 0.0f && tail.left < soon.left)) {
    return 33;
  }
  uint8_t quiet[256] = {0};
  rumble.push(std::span<const std::uint8_t>{quiet, sizeof quiet}, 1.0f, 1020);
  RumbleLevels held{};
  held = rumble.linear(1020, 1.0f);
  if (!(held.left > 0.0f && held.left < start.left)) {
    return 32;
  }
  return 0;
}

static int test_malformed_input_is_ignored(void) {
  HapticRumble rumble;
  uint8_t pcm[256];
  tone(pcm, 20000, 20000);
  rumble.push(std::span<const std::uint8_t>{pcm, 255}, 1.0f, 10);
  rumble.push(std::span<const std::uint8_t>{pcm, 2}, 1.0f, 10);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, NAN, 10);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, -1.0f, 10);
  RumbleLevels output{1.0F, 1.0F};
  output = rumble.linear(10, 1.0f);
  if (output.left != 0.0f || output.right != 0.0f) {
    return 40;
  }
  return 0;
}

static int test_sides_keep_each_channel_to_itself(void) {
  HapticRumble rumble;
  uint8_t pcm[256];
  tone(pcm, 16000, 0);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 100);
  RumbleLevels sides{};
  sides = rumble.curved(100, 1.0f);
  RumbleLevels levels{};
  levels = rumble.linear(100, 1.0f);
  if (sides.left <= 0.0f || sides.right != 0.0f || levels.right <= 0.0f ||
      sides.left <= levels.left) {
    return 80;
  }
  sides = rumble.curved(100, 0.0f);
  if (sides.left != 0.0f) {
    return 81;
  }
  return 0;
}

static int test_level_follows_upstream_linear_strength(void) {
  HapticRumble rumble;
  uint8_t pcm[256];
  tone(pcm, 1000, 1000);
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 10);
  RumbleLevels quiet{};
  quiet = rumble.linear(10, 1.0f);
  if (std::fabs(quiet.left - 1000.0f / 32768.0f) > 0.0001f) {
    return 90;
  }
  tone(pcm, 60, 60);
  rumble.reset();
  rumble.push(std::span<const std::uint8_t>{pcm, sizeof pcm}, 1.0f, 10);
  RumbleLevels faint{};
  faint = rumble.linear(10, 1.0f);
  if (std::fabs(faint.left - 512.0f / 65535.0f) > 0.0001f) {
    return 91;
  }
  faint = rumble.linear(200, 1.0f);
  if (faint.left != 0.0f) {
    return 92;
  }
  return 0;
}

int main(void) {
  int (*tests[])(void) = {
      test_silence_stays_off,
      test_channels_drive_their_own_motor,
      test_gain_scales_and_saturates,
      test_release_fades_after_the_haptics_stop,
      test_malformed_input_is_ignored,
      test_console_scale_reduces_the_motors,
      test_sides_keep_each_channel_to_itself,
      test_level_follows_upstream_linear_strength,
  };
  for (size_t index = 0; index < sizeof tests / sizeof tests[0]; index++) {
    int result = tests[index]();
    if (result) {
      fprintf(stderr, "haptic rumble test failed: %d\n", result);
      return result;
    }
  }
  return 0;
}
