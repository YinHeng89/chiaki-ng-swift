#ifndef NX_AUDIO_H
#define NX_AUDIO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "bridge_log.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct nx_audio nx_audio;

typedef enum {
  NX_AUDIO_CREATED,
  NX_AUDIO_CONFIGURED,
  NX_AUDIO_PRIMING,
  NX_AUDIO_PLAYING,
  NX_AUDIO_STOPPING,
  NX_AUDIO_STOPPED,
  NX_AUDIO_FAILED
} nx_audio_state;

typedef struct {
  uint64_t pcm_frames;
  uint64_t pcm_bytes;
  uint64_t underruns;
  uint64_t silent_frames;
  uint64_t overflows;
  uint64_t dropped_frames;
  uint64_t trims;
  uint64_t trimmed_frames;
  uint64_t buffered_frames;
  uint64_t maximum_buffered_frames;
  uint32_t channels;
  uint32_t sample_rate;
  nx_audio_state state;
  int device_failures;
} nx_audio_stats;

enum {
  NX_AUDIO_BUFFER_MIN_MS = 20,
  NX_AUDIO_BUFFER_DEFAULT_MS = 40,
  NX_AUDIO_BUFFER_MAX_MS = 100,
  NX_AUDIO_DEVICE_NAME_SIZE = 256
};

typedef struct nx_audio_output_watch nx_audio_output_watch;
bool nx_audio_output_is_headphones(const char* device);
bool nx_audio_output_dualsense_ready(void);
nx_audio_output_watch* nx_audio_output_watch_start(void (*changed)(void*),
                                                   void* context);
void nx_audio_output_watch_stop(nx_audio_output_watch*);
size_t nx_audio_output_devices(char names[][NX_AUDIO_DEVICE_NAME_SIZE],
                               size_t capacity);

enum { NX_AUDIO_MAX_CHANNELS = 12, NX_AUDIO_MAX_PULL_FRAMES = 4096 };

typedef struct nx_audio_output_ops {
  void* (*open)(nx_audio* audio, uint32_t channels, uint32_t sample_rate,
                const char* device, float gain, bool spatial,
                nx_bridge_log* log);
  void (*close)(void* output);
  void (*set_gain)(void* output, float gain);
} nx_audio_output_ops;

nx_audio* nx_audio_create(nx_bridge_log* log);
nx_audio* nx_audio_create_with_output(nx_bridge_log* log,
                                      const nx_audio_output_ops* output);
int nx_audio_configure(nx_audio*, uint32_t channels, uint32_t sample_rate);
void nx_audio_push(nx_audio*, const int16_t* samples, size_t frame_count);
size_t nx_audio_pull(nx_audio*, int16_t* samples, size_t frame_count);
void nx_audio_get_stats(nx_audio*, nx_audio_stats*);
void nx_audio_set_gain(nx_audio*, float gain);
void nx_audio_set_output_device(nx_audio*, const char* name);
void nx_audio_set_buffer_ms(nx_audio*, uint32_t milliseconds);
void nx_audio_set_spatial(nx_audio*, bool enabled);
bool nx_audio_output_looks_like_headphones(uint32_t transport,
                                           uint32_t data_source,
                                           const char* name);
void nx_audio_stop(nx_audio*);
void nx_audio_destroy(nx_audio*);

const nx_audio_output_ops* nx_audio_engine_output(void);

#ifdef __cplusplus
}
#endif

#endif
