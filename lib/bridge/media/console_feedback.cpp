#include "chiaki_bridge/media.hpp"

namespace chiaki_bridge {

auto ConsoleFeedback::scale_of(std::uint8_t level) noexcept -> float {
  constexpr std::uint8_t mask = 3;
  return scale_of(
      static_cast<libchiaking::controllers::FeedbackIntensity>(level & mask));
}

auto ConsoleFeedback::scale_of(
    libchiaking::controllers::FeedbackIntensity intensity) noexcept -> float {
  using libchiaking::controllers::FeedbackIntensity;
  switch (intensity) {
    case FeedbackIntensity::off:
      return 0.0F;
    case FeedbackIntensity::strong:
      return 1.0F;
    case FeedbackIntensity::medium:
      return 0.5F;
    case FeedbackIntensity::weak:
      return 0.33F;
  }
  return 1.0F;
}

}  // namespace chiaki_bridge
