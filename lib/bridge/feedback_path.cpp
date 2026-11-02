#include "feedback_path.hpp"

#include <algorithm>
#include <cstring>

#include "runtime.hpp"

namespace chiaki_bridge {

using libchiaking::controllers::ControllerFeedback;
using libchiaking::controllers::FeedbackInbox;
using libchiaking::controllers::FeedbackIntensity;
using libchiaking::controllers::HapticBlock;
using libchiaking::controllers::SeatNumber;
using libchiaking::controllers::TriggerEffects;

FeedbackPath::FeedbackPath(StreamListener& listener)
    : listener_(listener),
      inbox_(Runtime::process().threading(), Runtime::process().clock(),
             FeedbackInbox::Configuration{.gain_ceiling = gain_ceiling}) {}

auto FeedbackPath::level_of(
    libchiaking::controllers::FeedbackIntensity intensity) noexcept
    -> std::uint8_t {
  return static_cast<std::uint8_t>(intensity);
}

void FeedbackPath::route(HapticDelivery delivery) {
  delivery_ = delivery;
  if (delivery == HapticDelivery::frames) {
    inbox_.clear_haptics(SeatNumber::first());
  }
}

auto FeedbackPath::aged_now() const -> FeedbackInbox::Clock::time_point {
  return delivery_.load() == HapticDelivery::blocks
             ? unaged
             : FeedbackInbox::Clock::now();
}

void FeedbackPath::rumble(SeatNumber seat, std::uint8_t low,
                          std::uint8_t high) {
  ++rumbles_;
  listener_.on_rumble(seat, low, high);
}

void FeedbackPath::haptic_frames(const ControllerFeedback& feedback) {
  const auto* audio = feedback.get<libchiaking::controllers::HapticAudio>();
  if (audio == nullptr) {
    return;
  }
  const auto bytes = audio->pcm;
  frame_bytes_ +=
      std::min(bytes.size(), libchiaking::controllers::HapticAudio::max_bytes);
  if (!audio->playable()) {
    ++frame_calls_;
    ++frame_malformed_;
    return;
  }
  if (!feedback.seat.is_first()) {
    return;
  }
  inbox_.clear_haptics(SeatNumber::first());
  const auto intensity = level_of(inbox_.haptic_intensity());
  for (std::size_t offset = 0; offset < bytes.size();
       offset += HapticBlock::size) {
    const auto chunk = bytes.subspan(
        offset, std::min(HapticBlock::size, bytes.size() - offset));
    ++frame_calls_;
    listener_.on_haptic_frames(
        {reinterpret_cast<const std::uint8_t*>(chunk.data()), chunk.size()},
        intensity);
  }
}

void FeedbackPath::haptics(const ControllerFeedback& feedback) {
  const auto delivery = delivery_.load();
  if (delivery == HapticDelivery::frames) {
    haptic_frames(feedback);
    return;
  }
  const auto now = aged_now();
  if (inbox_.accept(feedback, now) != FeedbackInbox::Admission::held ||
      delivery != HapticDelivery::blocks) {
    return;
  }
  while (const auto block =
             inbox_.take_haptic_block(SeatNumber::first(), now)) {
    listener_.on_haptic_block(
        std::span<const std::uint8_t, HapticBlock::size>{
            reinterpret_cast<const std::uint8_t*>(block->pcm().data()),
            HapticBlock::size},
        level_of(block->intensity()));
  }
}

auto FeedbackPath::accept(const ControllerFeedback& feedback) -> bool {
  using Kind = ControllerFeedback::Kind;
  switch (feedback.kind()) {
    case Kind::haptics:
      haptics(feedback);
      return true;
    case Kind::rumble:
      if (inbox_.accept(feedback) == FeedbackInbox::Admission::held) {
        if (const auto values = inbox_.take_rumble(feedback.seat)) {
          rumble(feedback.seat, values->left, values->right);
        }
      }
      return true;
    case Kind::trigger_effects:
    case Kind::haptic_intensity:
    case Kind::trigger_intensity:
      static_cast<void>(inbox_.accept(feedback));
      return true;
    default:
      return false;
  }
}

auto FeedbackPath::take(SeatNumber seat, bool active, bool guest_owned,
                        Report report) -> bool {
  std::ranges::fill(report, std::uint8_t{0});
  if (!active) {
    return false;
  }
  const auto place_triggers = [&](const TriggerEffects& effects) {
    report[0] |= triggers_present;
    std::ranges::copy(effects.packed(), report.begin() + trigger_offset);
  };
  if (!seat.is_first()) {
    if (guest_owned) {
      return false;
    }
    if (const auto triggers = inbox_.take_triggers(seat)) {
      place_triggers(triggers->effects);
      report[0] |= static_cast<std::uint8_t>(level_of(triggers->intensity)
                                             << trigger_intensity_shift);
    }
    return report[0] != 0;
  }
  if (const auto block = inbox_.take_haptic_block(seat, aged_now())) {
    report[0] |= haptics_present;
    std::memcpy(report.data() + haptic_offset, block->pcm().data(),
                HapticBlock::size);
    ++blocks_taken_;
  }
  if (const auto triggers = inbox_.take_triggers(seat)) {
    place_triggers(triggers->effects);
  }
  if (report[0] != 0) {
    report[0] |= static_cast<std::uint8_t>(
        (level_of(inbox_.haptic_intensity()) << haptic_intensity_shift) |
        (level_of(inbox_.trigger_intensity()) << trigger_intensity_shift));
  }
  return report[0] != 0;
}

void FeedbackPath::reset(SeatNumber seat) { inbox_.forget(seat); }

auto FeedbackPath::intensities() const -> FeedbackIntensities {
  return {.haptic = level_of(inbox_.haptic_intensity()),
          .trigger = level_of(inbox_.trigger_intensity())};
}

auto FeedbackPath::statistics() const -> FeedbackStatistics {
  const auto held = inbox_.statistics();
  return {.rumbles = rumbles_,
          .callbacks = frame_calls_ + held.haptic_packets,
          .bytes = frame_bytes_ + held.haptic_bytes,
          .malformed = frame_malformed_ + held.haptic_malformed,
          .packets_taken = blocks_taken_,
          .buffered_bytes = held.haptic_bytes_buffered};
}

}  // namespace chiaki_bridge
