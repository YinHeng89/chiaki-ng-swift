#include <algorithm>
#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/media.hpp"

namespace chiaki_bridge {

MicrophoneEncoder::MicrophoneEncoder(std::shared_ptr<Encoder> encoder) noexcept
    : encoder_(std::move(encoder)) {}

auto MicrophoneEncoder::create() -> std::optional<MicrophoneEncoder> {
  return Boundary::fenced(std::optional<MicrophoneEncoder>{},
                          []() -> std::optional<MicrophoneEncoder> {
                            auto encoder = Encoder::create();
                            if (!encoder) {
                              return std::nullopt;
                            }
                            return MicrophoneEncoder{std::make_shared<Encoder>(
                                std::move(encoder.value()))};
                          });
}

auto MicrophoneEncoder::encode(MicrophonePcm pcm, MicrophoneFrame frame)
    -> bool {
  if (pcm.size() != samples_per_frame() * channels() ||
      frame.size() != frame_size()) {
    return false;
  }
  return Boundary::fenced(false, [&] {
    const auto encoded =
        encoder_->encode(Encoder::Pcm{pcm.data(), Encoder::Pcm::extent});
    if (!encoded) {
      return false;
    }
    std::ranges::transform(encoded.value(), frame.begin(), [](std::byte value) {
      return std::to_integer<std::uint8_t>(value);
    });
    return true;
  });
}

}  // namespace chiaki_bridge
