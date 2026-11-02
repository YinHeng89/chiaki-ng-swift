#include "audio.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <libchiaking/play.hpp>
#include <mutex>
#include <new>
#include <optional>
#include <span>

using libchiaking::media::AudioPlayout;

struct nx_audio {
  std::mutex lock;
  std::mutex configure_lock;
  const nx_audio_output_ops* ops{};
  void* output{};
  nx_bridge_log* log{};
  std::optional<AudioPlayout> playout;
  AudioPlayout::Statistics retired{};
  std::uint64_t retired_bytes{};
  std::atomic<int> state{NX_AUDIO_CREATED};
  std::atomic<int> device_failures{};
  std::atomic<std::uint32_t> channels{};
  std::atomic<std::uint32_t> sample_rate{};
  float gain{1};
  std::uint32_t buffer_ms{NX_AUDIO_BUFFER_DEFAULT_MS};
  char output_device[NX_AUDIO_DEVICE_NAME_SIZE]{};
  bool spatial{};
};

namespace {

void add(AudioPlayout::Statistics& total,
         const AudioPlayout::Statistics& more) noexcept {
  total.pushed_frames += more.pushed_frames;
  total.overflows += more.overflows;
  total.dropped_frames += more.dropped_frames;
  total.underruns += more.underruns;
  total.silent_frames += more.silent_frames;
  total.trims += more.trims;
  total.trimmed_frames += more.trimmed_frames;
  total.maximum_buffered_frames =
      std::max(total.maximum_buffered_frames, more.maximum_buffered_frames);
}

void retire(nx_audio* audio) {
  if (audio->playout) {
    const auto stats = audio->playout->statistics();
    add(audio->retired, stats);
    audio->retired_bytes +=
        stats.pushed_frames * audio->channels.load() * sizeof(std::int16_t);
    audio->playout.reset();
  }
}

void stop_output(nx_audio* audio) {
  void* output = nullptr;
  {
    const std::lock_guard guard{audio->lock};
    output = std::exchange(audio->output, nullptr);
    audio->state.store(NX_AUDIO_STOPPING);
  }
  if (output) {
    audio->ops->close(output);
  }
  const std::lock_guard guard{audio->lock};
  retire(audio);
  audio->state.store(NX_AUDIO_STOPPED);
}

int configure_output(nx_audio* audio, std::uint32_t channels,
                     std::uint32_t sample_rate) {
  stop_output(audio);
  char device[NX_AUDIO_DEVICE_NAME_SIZE];
  float gain = 1;
  bool spatial = false;
  std::uint32_t buffer_ms = 0;
  {
    const std::lock_guard guard{audio->lock};
    buffer_ms = audio->buffer_ms;
    auto playout = AudioPlayout::create(channels, sample_rate, buffer_ms);
    if (!playout) {
      audio->device_failures.fetch_add(1);
      audio->state.store(NX_AUDIO_FAILED);
      return 1;
    }
    audio->playout.emplace(std::move(*playout));
    audio->channels.store(channels);
    audio->sample_rate.store(sample_rate);
    audio->state.store(NX_AUDIO_CONFIGURED);
    std::memcpy(device, audio->output_device, sizeof(device));
    gain = audio->gain;
    spatial = audio->spatial;
  }
  void* output =
      audio->ops->open(audio, channels, sample_rate,
                       device[0] ? device : nullptr, gain, spatial, audio->log);
  {
    const std::lock_guard guard{audio->lock};
    if (!output) {
      audio->device_failures.fetch_add(1);
      audio->state.store(NX_AUDIO_FAILED);
      return 1;
    }
    audio->output = output;
    audio->state.store(NX_AUDIO_PRIMING);
  }
  nx_bridge_log_write(
      audio->log, NX_LOG_INFO,
      "Audio configured for %u channels at %u Hz with a %u ms buffer", channels,
      sample_rate, buffer_ms);
  return 0;
}

}  // namespace

nx_audio* nx_audio_create_with_output(nx_bridge_log* log,
                                      const nx_audio_output_ops* output) {
  if (!output) {
    return nullptr;
  }
  auto* audio = new (std::nothrow) nx_audio{};
  if (!audio) {
    return nullptr;
  }
  audio->ops = output;
  audio->log = log;
  return audio;
}

size_t nx_audio_pull(nx_audio* audio, int16_t* samples, size_t frame_count) {
  if (!audio || !samples || !frame_count) {
    return 0;
  }
  const std::size_t channels = audio->channels.load();
  if (!channels) {
    return 0;
  }
  const std::span<std::int16_t> destination{samples, frame_count * channels};
  if (audio->state.load() != NX_AUDIO_PLAYING || !audio->playout) {
    std::fill(destination.begin(), destination.end(), std::int16_t{0});
    return 0;
  }
  return audio->playout->pull(destination);
}

void nx_audio_stop(nx_audio* audio) {
  if (!audio) {
    return;
  }
  const std::lock_guard guard{audio->configure_lock};
  stop_output(audio);
}

int nx_audio_configure(nx_audio* audio, uint32_t channels,
                       uint32_t sample_rate) {
  if (!audio || channels < 1 || channels > NX_AUDIO_MAX_CHANNELS ||
      sample_rate < 8000 || sample_rate > 192000) {
    return 3;
  }
  const std::lock_guard guard{audio->configure_lock};
  return configure_output(audio, channels, sample_rate);
}

void nx_audio_push(nx_audio* audio, const int16_t* samples,
                   size_t frame_count) {
  if (!audio || !samples || !frame_count) {
    return;
  }
  const std::lock_guard guard{audio->lock};
  const int state = audio->state.load();
  if ((state != NX_AUDIO_PRIMING && state != NX_AUDIO_PLAYING) ||
      !audio->playout) {
    return;
  }
  const std::size_t channels = audio->channels.load();
  if (frame_count > SIZE_MAX / channels) {
    return;
  }
  audio->playout->push(std::span{samples, frame_count * channels});
  if (state == NX_AUDIO_PRIMING &&
      audio->playout->buffered_frames() >= audio->playout->target_frames()) {
    audio->state.store(NX_AUDIO_PLAYING);
  }
}

void nx_audio_set_gain(nx_audio* audio, float gain) {
  if (!audio) {
    return;
  }
  if (gain < 0 || gain != gain) {
    gain = 0;
  }
  if (gain > 1) {
    gain = 1;
  }
  const std::lock_guard configuring{audio->configure_lock};
  void* output = nullptr;
  {
    const std::lock_guard guard{audio->lock};
    audio->gain = gain;
    output = audio->output;
  }
  if (output) {
    audio->ops->set_gain(output, gain);
  }
}

void nx_audio_set_buffer_ms(nx_audio* audio, uint32_t milliseconds) {
  if (!audio) {
    return;
  }
  const std::lock_guard guard{audio->lock};
  audio->buffer_ms = std::clamp<std::uint32_t>(
      milliseconds, NX_AUDIO_BUFFER_MIN_MS, NX_AUDIO_BUFFER_MAX_MS);
}

void nx_audio_set_output_device(nx_audio* audio, const char* name) {
  if (!audio) {
    return;
  }
  const std::lock_guard guard{audio->lock};
  std::snprintf(audio->output_device, sizeof(audio->output_device), "%s",
                name ? name : "");
}

void nx_audio_set_spatial(nx_audio* audio, bool enabled) {
  if (!audio) {
    return;
  }
  const std::lock_guard configuring{audio->configure_lock};
  bool changed = false;
  {
    const std::lock_guard guard{audio->lock};
    changed = audio->spatial != enabled;
    audio->spatial = enabled;
  }
  const int state = audio->state.load();
  if (changed && (state == NX_AUDIO_PRIMING || state == NX_AUDIO_PLAYING)) {
    configure_output(audio, audio->channels.load(), audio->sample_rate.load());
  }
}

void nx_audio_get_stats(nx_audio* audio, nx_audio_stats* stats) {
  if (!stats) {
    return;
  }
  *stats = nx_audio_stats{};
  if (!audio) {
    return;
  }
  AudioPlayout::Statistics total{};
  std::uint64_t buffered = 0;
  std::uint64_t bytes = 0;
  std::uint32_t channels = 0;
  std::uint32_t sample_rate = 0;
  int state = NX_AUDIO_CREATED;
  {
    const std::lock_guard guard{audio->lock};
    channels = audio->channels.load();
    sample_rate = audio->sample_rate.load();
    state = audio->state.load();
    total = audio->retired;
    bytes = audio->retired_bytes;
    if (audio->playout) {
      const auto current = audio->playout->statistics();
      add(total, current);
      buffered = current.buffered_frames;
      bytes += current.pushed_frames * channels * sizeof(std::int16_t);
    }
  }
  stats->pcm_frames = total.pushed_frames;
  stats->pcm_bytes = bytes;
  stats->underruns = total.underruns;
  stats->silent_frames = total.silent_frames;
  stats->overflows = total.overflows;
  stats->dropped_frames = total.dropped_frames;
  stats->trims = total.trims;
  stats->trimmed_frames = total.trimmed_frames;
  stats->buffered_frames = buffered;
  stats->maximum_buffered_frames = total.maximum_buffered_frames;
  stats->channels = channels;
  stats->sample_rate = sample_rate;
  stats->state = static_cast<nx_audio_state>(state);
  stats->device_failures = audio->device_failures.load();
}

void nx_audio_destroy(nx_audio* audio) {
  if (!audio) {
    return;
  }
  nx_audio_stop(audio);
  delete audio;
}

namespace {

bool contains_word(const char* text, const char* const* words, size_t count) {
  if (!text) {
    return false;
  }
  char lowered[NX_AUDIO_DEVICE_NAME_SIZE];
  size_t length = 0;
  for (; text[length] && length + 1 < sizeof(lowered); length++) {
    char value = text[length];
    lowered[length] = value >= 'A' && value <= 'Z'
                          ? static_cast<char>(value - 'A' + 'a')
                          : value;
  }
  lowered[length] = 0;
  for (size_t index = 0; index < count; index++) {
    if (std::strstr(lowered, words[index])) {
      return true;
    }
  }
  return false;
}

}  // namespace

bool nx_audio_output_looks_like_headphones(uint32_t transport,
                                           uint32_t data_source,
                                           const char* name) {
  static const char* const headphones[] = {
      "airpods", "beats", "buds",  "headphone",   "headset", "earphone",
      "earbud",  "wh-",   "wf-",   "momentum",    "jabra",   "powerbeats",
      "qc35",    "qc45",  "qc ul", "quietcomfort"};
  static const char* const speakers[] = {
      "speaker", "soundbar", "sound bar", "soundlink", "boombox", "boom",
      "flip",    "charge",   "pill",      "homepod",   "sonos"};
  const uint32_t bluetooth = 0x626c7565;
  const uint32_t bluetooth_le = 0x626c6561;
  const uint32_t usb = 0x75736220;
  const uint32_t headphone_source = 0x6864706e;
  size_t headphone_count = sizeof(headphones) / sizeof(headphones[0]);
  size_t speaker_count = sizeof(speakers) / sizeof(speakers[0]);
  bool wireless = transport == bluetooth || transport == bluetooth_le;
  if (data_source == headphone_source) {
    return true;
  }
  if (!wireless && transport != usb) {
    return false;
  }
  if (contains_word(name, speakers, speaker_count)) {
    return false;
  }
  return wireless || contains_word(name, headphones, headphone_count);
}
