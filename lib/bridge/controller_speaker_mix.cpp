#include "controller_speaker_mix.hpp"

#include <algorithm>
#include <limits>

namespace chiaki_bridge {

using libchiaking::media::AudioDecoder;
using libchiaking::media::AudioFormat;

auto ControllerSpeakerMix::decoder(std::uint8_t seat) -> AudioDecoder* {
  if (seat >= seats) {
    return nullptr;
  }
  auto& slot = decoders_[seat];
  if (!slot) {
    AudioFormat format;
    format.channels = 1;
    format.bits = 16;
    format.rate = sample_rate;
    format.frame_size = frame_samples;
    auto created = AudioDecoder::create(format);
    if (!created) {
      return nullptr;
    }
    slot.emplace(std::move(created.value()));
  }
  return &*slot;
}

auto ControllerSpeakerMix::decode(std::uint8_t seat,
                                  std::span<const std::byte> packet)
    -> std::optional<std::span<const std::int16_t>> {
  auto* lane = decoder(seat);
  if (lane == nullptr) {
    return std::nullopt;
  }
  const auto pcm = lane->decode(packet);
  if (!pcm) {
    return std::nullopt;
  }
  return pcm.value();
}

void ControllerSpeakerMix::hold(std::uint8_t seat,
                                std::span<const std::int16_t> pcm) {
  if (seat >= seats) {
    return;
  }
  auto& held = held_[seat];
  held.insert(held.end(), pcm.begin(), pcm.end());
  if (held.size() > held_samples) {
    held.erase(held.begin(),
               held.end() - static_cast<std::ptrdiff_t>(held_samples));
  }
}

void ControllerSpeakerMix::mix(std::span<std::int16_t> pcm,
                               std::size_t channels) noexcept {
  if (channels == 0 || pending() == 0) {
    return;
  }
  constexpr auto lowest =
      static_cast<float>(std::numeric_limits<std::int16_t>::min());
  constexpr auto highest =
      static_cast<float>(std::numeric_limits<std::int16_t>::max());
  const auto targets = std::min<std::size_t>(channels, 2);
  for (std::size_t frame = 0; frame < pcm.size() / channels; ++frame) {
    float speaker = 0.0F;
    for (auto& held : held_) {
      if (!held.empty()) {
        speaker += static_cast<float>(held.front()) * gain;
        held.pop_front();
      }
    }
    for (std::size_t channel = 0; channel < targets; ++channel) {
      auto& sample = pcm[frame * channels + channel];
      sample = static_cast<std::int16_t>(
          std::clamp(static_cast<float>(sample) + speaker, lowest, highest));
    }
  }
}

void ControllerSpeakerMix::reset() noexcept {
  for (auto& slot : decoders_) {
    slot.reset();
  }
  for (auto& held : held_) {
    held.clear();
  }
}

auto ControllerSpeakerMix::pending() const noexcept -> std::size_t {
  std::size_t most = 0;
  for (const auto& held : held_) {
    most = std::max(most, held.size());
  }
  return most;
}

}  // namespace chiaki_bridge
