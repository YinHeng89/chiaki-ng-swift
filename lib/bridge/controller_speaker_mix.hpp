#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <libchiaking/play.hpp>
#include <optional>
#include <span>

namespace chiaki_bridge {

class ControllerSpeakerMix {
 public:
  static constexpr std::size_t seats = 4;
  static constexpr std::uint32_t sample_rate = 48000;
  static constexpr std::uint32_t frame_samples = 480;
  static constexpr std::size_t held_samples = sample_rate / 5;
  static constexpr float gain = 0.8F;

  auto decode(std::uint8_t seat, std::span<const std::byte> packet)
      -> std::optional<std::span<const std::int16_t>>;
  void hold(std::uint8_t seat, std::span<const std::int16_t> pcm);
  void mix(std::span<std::int16_t> pcm, std::size_t channels) noexcept;
  void reset() noexcept;
  auto pending() const noexcept -> std::size_t;

 private:
  auto decoder(std::uint8_t seat) -> libchiaking::media::AudioDecoder*;

  std::array<std::optional<libchiaking::media::AudioDecoder>, seats> decoders_;
  std::array<std::deque<std::int16_t>, seats> held_;
};

}  // namespace chiaki_bridge
