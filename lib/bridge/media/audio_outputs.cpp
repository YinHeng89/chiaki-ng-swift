#include <algorithm>
#include <array>
#include <string_view>
#include <utility>

#include "audio.h"
#include "chiaki_bridge/media.hpp"

namespace chiaki_bridge {

auto AudioOutputs::names() -> Texts {
  constexpr std::size_t most_devices = 32;
  std::array<std::array<char, NX_AUDIO_DEVICE_NAME_SIZE>, most_devices> rows{};
  const auto count = nx_audio_output_devices(
      reinterpret_cast<char (*)[NX_AUDIO_DEVICE_NAME_SIZE]>(rows.data()),
      rows.size());
  Texts listed;
  for (const auto& row : std::span{rows}.first(count)) {
    const std::string name{row.data(), std::ranges::find(row, '\0')};
    if (std::ranges::find(listed, name) == listed.end()) {
      listed.push_back(name);
    }
  }
  return listed;
}

auto AudioOutputs::is_headphones(const std::string& device) -> bool {
  return nx_audio_output_is_headphones(device.c_str());
}

auto AudioOutputs::dualsense_ready() -> bool {
  return nx_audio_output_dualsense_ready();
}

class AudioOutputWatch::Listening {
 public:
  Listening(AudioOutputChanged changed, void* context)
      : watch_(nx_audio_output_watch_start(changed, context)) {}

  Listening(const Listening&) = delete;
  auto operator=(const Listening&) -> Listening& = delete;

  ~Listening() { stop(); }

  void stop() noexcept {
    nx_audio_output_watch_stop(std::exchange(watch_, nullptr));
  }

 private:
  nx_audio_output_watch* watch_;
};

AudioOutputWatch::AudioOutputWatch(
    std::shared_ptr<Listening> listening) noexcept
    : listening_(std::move(listening)) {}

auto AudioOutputWatch::start(AudioOutputChanged changed, void* context)
    -> AudioOutputWatch {
  return AudioOutputWatch{std::make_shared<Listening>(changed, context)};
}

void AudioOutputWatch::stop() noexcept {
  if (listening_) {
    listening_->stop();
  }
}

}  // namespace chiaki_bridge
