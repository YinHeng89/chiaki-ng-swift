#include "audio.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int opened;
  int closed;
  int refuse;
  uint32_t channels;
  uint32_t sample_rate;
  float gain;
  bool spatial;
  char device[NX_AUDIO_DEVICE_NAME_SIZE];
} fake_output;

static fake_output fake;

static void* fake_open(nx_audio* audio, uint32_t channels, uint32_t sample_rate,
                       const char* device, float gain, bool spatial,
                       nx_bridge_log* log) {
  (void)audio;
  fake.spatial = spatial;
  (void)log;
  if (fake.refuse) {
    return NULL;
  }
  fake.opened++;
  fake.channels = channels;
  fake.sample_rate = sample_rate;
  fake.gain = gain;
  memset(fake.device, 0, sizeof(fake.device));
  if (device) {
    strncpy(fake.device, device, sizeof(fake.device) - 1);
  }
  return &fake;
}

static void fake_close(void* output) {
  (void)output;
  fake.closed++;
}

static void fake_set_gain(void* output, float gain) {
  (void)output;
  fake.gain = gain;
}

static const nx_audio_output_ops fake_ops = {
    .open = fake_open, .close = fake_close, .set_gain = fake_set_gain};

static bool all_zero(const int16_t* samples, size_t count) {
  for (size_t index = 0; index < count; index++) {
    if (samples[index]) {
      return false;
    }
  }
  return true;
}

static int check(nx_audio* audio, int16_t* samples, int16_t* pulled) {
  nx_audio_stats stats = {0};
  if (nx_audio_configure(audio, 2, 48000) || fake.opened != 1 ||
      fake.channels != 2 || fake.sample_rate != 48000 || fake.gain != 1) {
    return 2;
  }
  for (size_t index = 0; index < 12000; index++) {
    samples[index] = (int16_t)(index % 100 + 1);
  }
  nx_audio_push(audio, samples, 1000);
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_PRIMING || stats.buffered_frames != 960 ||
      stats.channels != 2 || stats.sample_rate != 48000) {
    return 4;
  }
  if (nx_audio_pull(audio, pulled, 480) != 0 || !all_zero(pulled, 960)) {
    return 5;
  }
  nx_audio_get_stats(audio, &stats);
  if (stats.underruns || stats.buffered_frames != 960) {
    return 6;
  }
  nx_audio_push(audio, samples, 6000);
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_PLAYING || stats.pcm_frames != 7000 ||
      stats.pcm_bytes != 28000 || stats.overflows != 1 ||
      stats.dropped_frames != 1200 || stats.maximum_buffered_frames != 5760 ||
      stats.buffered_frames != 5760) {
    return 7;
  }
  if (nx_audio_pull(audio, pulled, 480) != 480 || all_zero(pulled, 960)) {
    return 8;
  }
  if (nx_audio_pull(audio, pulled, 6000) != 5280 ||
      !all_zero(pulled + 5280 * 2, 720 * 2)) {
    return 9;
  }
  nx_audio_get_stats(audio, &stats);
  if (stats.underruns != 1 || stats.silent_frames != 720 ||
      stats.buffered_frames) {
    return 10;
  }
  if (nx_audio_configure(audio, 6, 48000)) {
    return 30;
  }
  nx_audio_get_stats(audio, &stats);
  if (stats.pcm_bytes != 28000 || stats.pcm_frames != 7000 ||
      stats.underruns != 1 || stats.buffered_frames) {
    return 31;
  }
  nx_audio_push(audio, samples, 480);
  nx_audio_get_stats(audio, &stats);
  if (stats.pcm_bytes != 28000 + 480 * 6 * 2 || stats.pcm_frames != 7480) {
    return 32;
  }
  if (nx_audio_configure(audio, 2, 48000)) {
    return 33;
  }
  nx_audio_set_gain(audio, 3);
  if (fake.gain != 1) {
    return 11;
  }
  nx_audio_set_gain(audio, -1);
  if (fake.gain != 0) {
    return 12;
  }
  nx_audio_set_gain(audio, 0.5f);
  nx_audio_stop(audio);
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_STOPPED || stats.buffered_frames ||
      fake.closed != 3) {
    return 13;
  }
  nx_audio_set_output_device(audio, "Studio Display");
  if (nx_audio_configure(audio, 12, 48000) || fake.channels != 12 ||
      strcmp(fake.device, "Studio Display") || fake.gain != 0.5f) {
    return 14;
  }
  if (nx_audio_configure(audio, 13, 48000) != 3) {
    return 15;
  }
  nx_audio_set_output_device(audio, NULL);
  nx_audio_set_buffer_ms(audio, 80);
  if (nx_audio_configure(audio, 2, 48000) || fake.device[0]) {
    return 16;
  }
  nx_audio_push(audio, samples, 3000);
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_PRIMING || stats.buffered_frames != 2880) {
    return 17;
  }
  nx_audio_push(audio, samples, 6000);
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_PLAYING || stats.maximum_buffered_frames < 8880) {
    return 18;
  }
  nx_audio_set_buffer_ms(audio, 1);
  if (nx_audio_configure(audio, 2, 48000)) {
    return 19;
  }
  nx_audio_push(audio, samples, 480);
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_PRIMING) {
    return 20;
  }
  if (stats.maximum_buffered_frames != 8880 || stats.buffered_frames != 480) {
    return 24;
  }
  nx_audio_push(audio, samples, 480);
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_PLAYING) {
    return 21;
  }
  fake.refuse = 1;
  if (nx_audio_configure(audio, 2, 48000) != 1) {
    return 22;
  }
  nx_audio_get_stats(audio, &stats);
  if (stats.state != NX_AUDIO_FAILED || !stats.device_failures) {
    return 23;
  }
  return 0;
}

static int check_headphone_guess(void) {
  const uint32_t bluetooth = 0x626c7565;
  const uint32_t usb = 0x75736220;
  const uint32_t built_in = 0x626c746e;
  if (!nx_audio_output_looks_like_headphones(bluetooth, 0,
                                             "Oscar’s AirPods Pro") ||
      !nx_audio_output_looks_like_headphones(bluetooth, 0, "WH-1000XM5") ||
      !nx_audio_output_looks_like_headphones(bluetooth, 0, "Unknown Device") ||
      nx_audio_output_looks_like_headphones(bluetooth, 0, "JBL Flip 6") ||
      nx_audio_output_looks_like_headphones(bluetooth, 0,
                                            "Bose SoundLink Flex") ||
      nx_audio_output_looks_like_headphones(bluetooth, 0, "Beats Pill") ||
      !nx_audio_output_looks_like_headphones(usb, 0, "USB Headset") ||
      nx_audio_output_looks_like_headphones(usb, 0, "USB Audio DAC") ||
      !nx_audio_output_looks_like_headphones(built_in, 0x6864706e,
                                             "MacBook Pro Speakers") ||
      nx_audio_output_looks_like_headphones(built_in, 0x6973706b,
                                            "MacBook Pro Speakers") ||
      nx_audio_output_looks_like_headphones(built_in, 0, NULL)) {
    return 50;
  }
  return 0;
}

static int check_spatial(nx_bridge_log* log) {
  nx_audio* audio = nx_audio_create_with_output(log, &fake_ops);
  if (!audio) {
    return 40;
  }
  memset(&fake, 0, sizeof(fake));
  nx_audio_set_spatial(audio, true);
  if (fake.opened != 0) {
    nx_audio_destroy(audio);
    return 41;
  }
  if (nx_audio_configure(audio, 2, 48000) || fake.opened != 1 ||
      !fake.spatial) {
    nx_audio_destroy(audio);
    return 42;
  }
  nx_audio_set_spatial(audio, true);
  if (fake.opened != 1) {
    nx_audio_destroy(audio);
    return 43;
  }
  nx_audio_set_spatial(audio, false);
  if (fake.opened != 2 || fake.closed != 1 || fake.spatial ||
      fake.channels != 2 || fake.sample_rate != 48000) {
    nx_audio_destroy(audio);
    return 44;
  }
  nx_audio_stop(audio);
  nx_audio_set_spatial(audio, true);
  if (fake.opened != 2) {
    nx_audio_destroy(audio);
    return 45;
  }
  nx_audio_destroy(audio);
  return 0;
}

int main(void) {
  nx_bridge_log* log = nx_bridge_log_create();
  nx_audio* audio = nx_audio_create_with_output(log, &fake_ops);
  if (!audio || nx_audio_create_with_output(log, NULL)) {
    return 1;
  }
  int16_t* samples = calloc(12000, sizeof(*samples));
  int16_t* pulled = calloc(12000, sizeof(*pulled));
  if (!samples || !pulled) {
    free(samples);
    free(pulled);
    nx_audio_destroy(audio);
    return 3;
  }
  int result = check(audio, samples, pulled);
  if (!result) {
    result = check_spatial(log);
  }
  if (!result) {
    result = check_headphone_guess();
  }
  free(samples);
  free(pulled);
  nx_audio_destroy(audio);
  nx_bridge_log_destroy(log);
  return result;
}
