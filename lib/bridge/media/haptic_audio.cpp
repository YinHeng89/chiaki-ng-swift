#include <SDL3/SDL.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <span>
#include <utility>

#include "chiaki_bridge/media.hpp"
#include "sdl_ready.hpp"

namespace chiaki_bridge {

class HapticAudio::Device {
 public:
  static auto open() -> std::unique_ptr<Device> {
    SdlReady::mark();
    if (!SDL_InitSubSystem(SDL_INIT_AUDIO)) {
      return nullptr;
    }
    auto device = std::unique_ptr<Device>{new Device{}};
    int count = 0;
    SDL_AudioDeviceID* devices = SDL_GetAudioPlaybackDevices(&count);
    const std::span<SDL_AudioDeviceID> listed{
        devices, devices != nullptr ? static_cast<std::size_t>(count) : 0U};
    for (const auto candidate : listed) {
      if (dualsense_output(SDL_GetAudioDeviceName(candidate)) &&
          device->bind(candidate)) {
        break;
      }
    }
    SDL_free(devices);
    if (device->stream_ == nullptr) {
      return nullptr;
    }
    return device;
  }

  Device(const Device&) = delete;
  auto operator=(const Device&) -> Device& = delete;

  ~Device() {
    SDL_DestroyAudioStream(speaker_);
    SDL_DestroyAudioStream(stream_);
    if (device_ != 0) {
      SDL_CloseAudioDevice(device_);
    }
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
  }

  auto push(Block pcm, float gain) -> bool {
    if (SDL_GetAudioStreamQueued(stream_) > most_queued) {
      SDL_ClearAudioStream(stream_);
    }
    std::array<std::int16_t, frames * output_channels> output{};
    for (std::size_t frame = 0; frame < frames; ++frame) {
      std::int16_t left = 0;
      std::int16_t right = 0;
      std::memcpy(&left, pcm.subspan(frame * 4, 2).data(), sizeof left);
      std::memcpy(&right, pcm.subspan(frame * 4 + 2, 2).data(), sizeof right);
      output[frame * output_channels + 2] = scaled(left, gain);
      output[frame * output_channels + 3] = scaled(right, gain);
    }
    return SDL_PutAudioStreamData(stream_, output.data(),
                                  static_cast<int>(sizeof output));
  }

  auto push_speaker(std::span<const std::int16_t> pcm, float gain) -> bool {
    if (speaker_ == nullptr || pcm.empty() || pcm.size() > speaker_frames) {
      return false;
    }
    if (SDL_GetAudioStreamQueued(speaker_) > speaker_most_queued) {
      SDL_ClearAudioStream(speaker_);
    }
    std::array<std::int16_t, speaker_frames * output_channels> output{};
    for (std::size_t frame = 0; frame < pcm.size(); ++frame) {
      output[frame * output_channels + speaker_channel] =
          scaled(pcm[frame], gain);
    }
    return SDL_PutAudioStreamData(
        speaker_, output.data(),
        static_cast<int>(pcm.size() * output_channels * sizeof output[0]));
  }

  auto has_speaker() const noexcept -> bool { return speaker_ != nullptr; }

 private:
  static constexpr std::size_t frames = 64;
  static constexpr int rate = 3000;
  static constexpr int output_channels = 4;
  static constexpr int most_queued = rate * output_channels * 2 * 60 / 1000;
  static constexpr int speaker_rate = 48000;
  static constexpr std::size_t speaker_channel = 1;
  static constexpr std::size_t speaker_frames = 960;
  static constexpr int speaker_most_queued =
      speaker_rate * output_channels * 2 / 10;

  Device() = default;

  static auto dualsense_output(const char* name) -> bool {
    if (name == nullptr) {
      return false;
    }
    const std::string_view text{name};
    return text.contains("DualSense") || text.contains("Wireless Controller");
  }

  static auto scaled(std::int16_t sample, float gain) -> std::int16_t {
    const float value = static_cast<float>(sample) * gain;
    return static_cast<std::int16_t>(std::clamp(
        value, static_cast<float>(std::numeric_limits<std::int16_t>::min()),
        static_cast<float>(std::numeric_limits<std::int16_t>::max())));
  }

  auto bind(SDL_AudioDeviceID candidate) -> bool {
    const SDL_AudioSpec wanted{SDL_AUDIO_S16, output_channels, 48000};
    const SDL_AudioDeviceID opened = SDL_OpenAudioDevice(candidate, &wanted);
    if (opened == 0) {
      return false;
    }
    SDL_AudioSpec actual{};
    if (!SDL_GetAudioDeviceFormat(opened, &actual, nullptr) ||
        actual.channels < output_channels) {
      SDL_CloseAudioDevice(opened);
      return false;
    }
    const SDL_AudioSpec source{SDL_AUDIO_S16, output_channels, rate};
    SDL_AudioStream* stream = SDL_CreateAudioStream(&source, &actual);
    if (stream == nullptr || !SDL_BindAudioStream(opened, stream)) {
      SDL_DestroyAudioStream(stream);
      SDL_CloseAudioDevice(opened);
      return false;
    }
    const SDL_AudioSpec speaker_source{SDL_AUDIO_S16, output_channels,
                                       speaker_rate};
    SDL_AudioStream* speaker = SDL_CreateAudioStream(&speaker_source, &actual);
    if (speaker != nullptr && !SDL_BindAudioStream(opened, speaker)) {
      SDL_DestroyAudioStream(speaker);
      speaker = nullptr;
    }
    SDL_ResumeAudioDevice(opened);
    device_ = opened;
    stream_ = stream;
    speaker_ = speaker;
    return true;
  }

  SDL_AudioDeviceID device_{};
  SDL_AudioStream* stream_{};
  SDL_AudioStream* speaker_{};
};

HapticAudio::HapticAudio(std::unique_ptr<Device> device) noexcept
    : device_(std::move(device)) {}

HapticAudio::HapticAudio(HapticAudio&&) noexcept = default;

auto HapticAudio::operator=(HapticAudio&&) noexcept -> HapticAudio& = default;

HapticAudio::~HapticAudio() = default;

auto HapticAudio::open() -> std::optional<HapticAudio> {
  auto device = Device::open();
  if (!device) {
    return std::nullopt;
  }
  return HapticAudio{std::move(device)};
}

auto HapticAudio::push(Block pcm, float gain) -> bool {
  return device_ && device_->push(pcm, gain);
}

auto HapticAudio::push_speaker(std::span<const std::int16_t> pcm, float gain)
    -> bool {
  return device_ && device_->push_speaker(pcm, gain);
}

auto HapticAudio::has_speaker() const noexcept -> bool {
  return device_ && device_->has_speaker();
}

}  // namespace chiaki_bridge
