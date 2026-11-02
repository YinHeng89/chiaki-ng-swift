#pragma once

#ifdef __cplusplus
#include <CoreVideo/CoreVideo.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>

#include "Owned.hpp"

namespace video {

using PixelBuffer = Owned<CVPixelBufferRef>;

class PendingFrames {
 public:
  enum class Offer : std::uint8_t {
    queued,
    generated_refused,
    generated_replaced,
    decoded_replaced,
  };

  auto offer(PixelBuffer surface, bool generated) noexcept -> Offer {
    auto outcome = Offer::queued;
    if (count_ == frames_.size()) {
      std::size_t drop = 0;
      if (frames_[0].generated) {
        drop = 0;
      } else if (frames_[1].generated) {
        drop = 1;
      } else if (generated) {
        return Offer::generated_refused;
      }
      outcome = frames_[drop].generated ? Offer::generated_replaced
                                        : Offer::decoded_replaced;
      frames_[drop] = Frame{};
      if (drop == 0) {
        frames_[0] = std::move(frames_[1]);
        frames_[1] = Frame{};
      }
      --count_;
    }
    frames_[count_] = Frame{std::move(surface), generated};
    ++count_;
    return outcome;
  }

  auto take() noexcept -> std::optional<PixelBuffer> {
    if (count_ == 0) {
      return std::nullopt;
    }
    auto surface = std::move(frames_[0].surface);
    frames_[0] = std::move(frames_[1]);
    frames_[1] = Frame{};
    --count_;
    return surface;
  }

  void clear() noexcept {
    frames_ = {};
    count_ = 0;
  }

  auto empty() const noexcept -> bool { return count_ == 0; }

 private:
  struct Frame {
    PixelBuffer surface;
    bool generated{};
  };

  std::array<Frame, 2> frames_{};
  std::size_t count_{};
};

}  // namespace video

#endif
