#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/media.hpp"

namespace chiaki_bridge {

MicrophoneQueue::MicrophoneQueue(std::shared_ptr<Playout> playout) noexcept
    : playout_(std::move(playout)) {}

auto MicrophoneQueue::create(std::uint32_t channels, std::uint32_t sample_rate,
                             std::uint32_t target_ms)
    -> std::optional<MicrophoneQueue> {
  return Boundary::fenced(
      std::optional<MicrophoneQueue>{},
      [&]() -> std::optional<MicrophoneQueue> {
        auto playout = Playout::create(channels, sample_rate, target_ms);
        if (!playout) {
          return std::nullopt;
        }
        return MicrophoneQueue{
            std::make_shared<Playout>(std::move(playout.value()))};
      });
}

void MicrophoneQueue::push(MicrophonePcm samples) const noexcept {
  playout_->push(samples);
}

auto MicrophoneQueue::pull(MicrophoneSamples samples) const noexcept
    -> std::size_t {
  return playout_->pull(samples);
}

auto MicrophoneQueue::buffered_frames() const noexcept -> std::uint64_t {
  return playout_->buffered_frames();
}

}  // namespace chiaki_bridge
