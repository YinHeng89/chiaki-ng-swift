#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <libchiaking/play.hpp>
#include <optional>
#include <span>

#include "chiaki_bridge/stream.hpp"

namespace chiaki_bridge {

class FeedbackPath {
 public:
  static constexpr std::size_t report_size = Stream::feedback_report_size;
  static constexpr float gain_ceiling = 2.4F;

  using Report = Stream::FeedbackReport;

  explicit FeedbackPath(StreamListener& listener);

  void route(HapticDelivery delivery);

  auto accept(const libchiaking::controllers::ControllerFeedback& feedback)
      -> bool;
  void rumble(libchiaking::controllers::SeatNumber seat, std::uint8_t low,
              std::uint8_t high);
  auto take(libchiaking::controllers::SeatNumber seat, bool active,
            bool guest_owned, Report report) -> bool;
  void reset(libchiaking::controllers::SeatNumber seat);
  auto statistics() const -> FeedbackStatistics;
  auto intensities() const -> FeedbackIntensities;

 private:
  using Inbox = libchiaking::controllers::FeedbackInbox;

  static constexpr std::size_t haptic_offset = 1;
  static constexpr std::size_t trigger_offset =
      haptic_offset + libchiaking::controllers::HapticBlock::size;
  static constexpr std::uint8_t haptics_present = 1;
  static constexpr std::uint8_t triggers_present = 2;
  static constexpr unsigned haptic_intensity_shift = 2;
  static constexpr unsigned trigger_intensity_shift = 4;
  static constexpr Inbox::Clock::time_point unaged{};

  static auto level_of(
      libchiaking::controllers::FeedbackIntensity intensity) noexcept
      -> std::uint8_t;

  void haptics(const libchiaking::controllers::ControllerFeedback& feedback);
  void haptic_frames(
      const libchiaking::controllers::ControllerFeedback& feedback);
  auto aged_now() const -> Inbox::Clock::time_point;

  StreamListener& listener_;
  Inbox inbox_;
  std::atomic<HapticDelivery> delivery_{HapticDelivery::polled};
  std::atomic<std::uint64_t> rumbles_{};
  std::atomic<std::uint64_t> frame_calls_{};
  std::atomic<std::uint64_t> frame_bytes_{};
  std::atomic<std::uint64_t> frame_malformed_{};
  std::atomic<std::uint64_t> blocks_taken_{};
};

}  // namespace chiaki_bridge
