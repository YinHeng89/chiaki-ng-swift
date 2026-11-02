#pragma once

#ifdef __cplusplus
#include <algorithm>
#include <bit>
#include <cstddef>
#include <cstdint>

namespace video {

struct LightSample {
  std::uint32_t peak;
  std::uint32_t total;
  std::uint32_t samples;
  std::uint32_t above;
  std::uint32_t marker;
  std::uint32_t nearWhite;
};

class LightLevelWindow {
 public:
  void reset(double now) noexcept {
    *this = LightLevelWindow{};
    started_ = now;
  }

  void note(const LightSample& sample) noexcept {
    if (sample.samples == 0) {
      return;
    }
    const auto samples = static_cast<double>(sample.samples);
    peak_ = std::bit_cast<float>(sample.peak);
    average_ = sample.total / samples;
    above_ = sample.above * 100.0 / samples;
    maxCLL_ = std::max(maxCLL_, peak_);
    maxFALL_ = std::max(maxFALL_, average_);
    sessionAbove_ = std::max(sessionAbove_, above_);
    sessionNearWhite_ =
        std::max(sessionNearWhite_, sample.nearWhite * 100.0 / samples);
    marker_ = std::bit_cast<float>(sample.marker);
    ++measurements_;
  }

  auto measurements() const noexcept -> std::size_t { return measurements_; }
  auto seconds(double now) const noexcept -> double {
    return measurements_ > 0 ? now - started_ : 0;
  }
  auto peak() const noexcept -> double { return peak_; }
  auto average() const noexcept -> double { return average_; }
  auto above() const noexcept -> double { return above_; }
  auto maxCLL() const noexcept -> double { return maxCLL_; }
  auto maxFALL() const noexcept -> double { return maxFALL_; }
  auto sessionAbove() const noexcept -> double { return sessionAbove_; }
  auto sessionNearWhite() const noexcept -> double { return sessionNearWhite_; }
  auto marker() const noexcept -> double { return marker_; }

 private:
  double started_{};
  double peak_{};
  double average_{};
  double above_{};
  double maxCLL_{};
  double maxFALL_{};
  double sessionAbove_{};
  double sessionNearWhite_{};
  double marker_{};
  std::size_t measurements_{};
};

}  // namespace video

#endif
