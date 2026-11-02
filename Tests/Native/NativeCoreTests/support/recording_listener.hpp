#pragma once

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <iterator>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

#include "chiaki_bridge/stream.hpp"

namespace chiaki_bridge_testing {

class RecordingListener final : public chiaki_bridge::StreamListener {
 public:
  enum class Heard : std::uint8_t {
    connected,
    disconnected,
    start_attempt,
    reconnecting,
    connect_progress,
    picture_blocked,
    picture_allowed,
    login_pin,
    seat_passcode,
    seat_joined,
    seat_confirmed,
    seat_left,
    lightbar,
    motion_reset,
  };

  struct Event {
    Heard heard{};
    int value{};
    int detail{};

    auto operator==(const Event&) const -> bool = default;
  };

  struct Kakusan {
    chiaki_bridge::KakusanEvent event;
    std::string text;
  };

  using Rumble = std::array<std::uint8_t, 3>;
  using Keyboard = std::pair<chiaki_bridge::KeyboardChange, std::string>;
  using Video = std::pair<std::size_t, std::size_t>;
  using Launch = std::pair<libchiaking::play::LaunchProgress, bool>;

  void refuse_video() {
    const std::lock_guard lock(mutex_);
    decodes_ = false;
  }

  void on_launch(std::function<void()> reaction) {
    const std::lock_guard lock(mutex_);
    launch_reaction_ = std::move(reaction);
  }

  auto decodes_video() const -> bool override {
    const std::lock_guard lock(mutex_);
    return decodes_;
  }

  auto on_video(const chiaki_bridge::EncodedFrame& frame)
      -> libchiaking::media::VideoResult override {
    const std::lock_guard lock(mutex_);
    videos_.emplace_back(frame.bytes.size(), frame.header.size());
    return {};
  }

  void on_connected(bool reconnected) override {
    record(Heard::connected, reconnected ? 1 : 0);
  }

  void on_disconnected(
      std::optional<libchiaking::play::ConsoleQuit::Reason> quit) override {
    record(Heard::disconnected, quit ? static_cast<int>(*quit) : -1);
  }

  void on_start_attempt(std::uint32_t attempt) override {
    record(Heard::start_attempt, static_cast<int>(attempt));
  }

  void on_reconnecting(std::uint32_t attempt) override {
    record(Heard::reconnecting, static_cast<int>(attempt));
  }

  void on_connect_progress(
      const libchiaking::play::ConnectProgress& progress) override {
    {
      const std::lock_guard lock(mutex_);
      connects_.push_back(progress);
    }
    record(Heard::connect_progress, static_cast<int>(progress.step));
  }

  void on_launch_progress(const libchiaking::play::LaunchProgress& progress,
                          bool playing) override {
    std::function<void()> reaction;
    {
      const std::lock_guard lock(mutex_);
      launches_.emplace_back(progress, playing);
      reaction = launch_reaction_;
    }
    if (reaction) {
      reaction();
    }
  }

  void on_picture_blocked(bool blocked) override {
    record(blocked ? Heard::picture_blocked : Heard::picture_allowed);
  }

  void on_login_pin_needed(bool retry) override {
    record(Heard::login_pin, retry ? 1 : 0);
  }

  void on_seat_passcode_needed(libchiaking::controllers::SeatNumber seat,
                               bool retry) override {
    record(Heard::seat_passcode, seat.index(), retry ? 1 : 0);
  }

  void on_seat_joined(libchiaking::controllers::SeatNumber seat) override {
    record(Heard::seat_joined, seat.index());
  }

  void on_seat_confirmed(libchiaking::controllers::SeatNumber seat,
                         libchiaking::controllers::SeatLight light) override {
    record(Heard::seat_confirmed, seat.index(), colour_of(light));
  }

  void on_seat_left(libchiaking::controllers::SeatNumber seat) override {
    record(Heard::seat_left, seat.index());
  }

  void on_seat_refused(const libchiaking::play::SeatRefusal& refusal) override {
    const std::lock_guard lock(mutex_);
    refusals_.push_back(refusal);
  }

  void on_lightbar(libchiaking::controllers::SeatLight light) override {
    record(Heard::lightbar, 0, colour_of(light));
  }

  void on_motion_reset() override { record(Heard::motion_reset); }

  void on_rumble(libchiaking::controllers::SeatNumber seat, std::uint8_t low,
                 std::uint8_t high) override {
    const std::lock_guard lock(mutex_);
    rumbles_.push_back({seat.index(), low, high});
  }

  void on_haptic_block(std::span<const std::uint8_t,
                                 libchiaking::controllers::HapticBlock::size>,
                       std::uint8_t) override {
    const std::lock_guard lock(mutex_);
    ++haptic_blocks_;
  }

  void on_haptic_frames(std::span<const std::uint8_t> pcm,
                        std::uint8_t) override {
    const std::lock_guard lock(mutex_);
    haptic_frames_.push_back(pcm.size());
  }

  void on_keyboard(chiaki_bridge::KeyboardChange change,
                   std::string_view text) override {
    const std::lock_guard lock(mutex_);
    keyboard_.emplace_back(change, std::string{text});
  }

  void on_kakusan(const chiaki_bridge::KakusanEvent& event,
                  std::string_view text) override {
    const std::lock_guard lock(mutex_);
    shared_.push_back({event, std::string{text}});
  }

  auto saw(Heard heard, int value = 0, int detail = 0) const -> bool {
    const std::lock_guard lock(mutex_);
    return std::ranges::find(events_, Event{heard, value, detail}) !=
           events_.end();
  }

  auto count(Heard heard) const -> std::size_t {
    const std::lock_guard lock(mutex_);
    return static_cast<std::size_t>(std::ranges::count_if(
        events_, [heard](const Event& seen) { return seen.heard == heard; }));
  }

  void until(Heard heard) const { until_count(heard, 1); }

  void until_count(Heard heard, std::size_t wanted) const {
    while (count(heard) < wanted) {
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
  }

  void until_saw(Heard heard, int value, int detail = 0) const {
    while (!saw(heard, value, detail)) {
      std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
  }

  auto rumbles() const -> std::vector<Rumble> {
    const std::lock_guard lock(mutex_);
    return rumbles_;
  }

  auto refusals() const -> std::vector<libchiaking::play::SeatRefusal> {
    const std::lock_guard lock(mutex_);
    return refusals_;
  }

  auto keyboard() const -> std::vector<Keyboard> {
    const std::lock_guard lock(mutex_);
    return keyboard_;
  }

  auto videos() const -> std::vector<Video> {
    const std::lock_guard lock(mutex_);
    return videos_;
  }

  auto haptic_blocks() const -> std::size_t {
    const std::lock_guard lock(mutex_);
    return haptic_blocks_;
  }

  auto haptic_frames() const -> std::vector<std::size_t> {
    const std::lock_guard lock(mutex_);
    return haptic_frames_;
  }

  auto connects() const -> std::vector<libchiaking::play::ConnectProgress> {
    const std::lock_guard lock(mutex_);
    return connects_;
  }

  auto launches() const -> std::vector<Launch> {
    const std::lock_guard lock(mutex_);
    return launches_;
  }

  auto shared() const -> std::vector<Kakusan> {
    const std::lock_guard lock(mutex_);
    return shared_;
  }

  auto shared(chiaki_bridge::KakusanEvent::Kind kind) const
      -> std::vector<Kakusan> {
    const std::lock_guard lock(mutex_);
    std::vector<Kakusan> matching;
    std::ranges::copy_if(
        shared_, std::back_inserter(matching),
        [kind](const Kakusan& seen) { return seen.event.kind == kind; });
    return matching;
  }

 private:
  static auto colour_of(libchiaking::controllers::SeatLight light) -> int {
    return (light.red << 16) | (light.green << 8) | light.blue;
  }

  void record(Heard heard, int value = 0, int detail = 0) {
    const std::lock_guard lock(mutex_);
    events_.push_back({heard, value, detail});
  }

  mutable std::mutex mutex_;
  bool decodes_{true};
  std::function<void()> launch_reaction_;
  std::vector<Event> events_;
  std::vector<Rumble> rumbles_;
  std::vector<libchiaking::play::SeatRefusal> refusals_;
  std::vector<Keyboard> keyboard_;
  std::vector<Video> videos_;
  std::size_t haptic_blocks_{};
  std::vector<std::size_t> haptic_frames_;
  std::vector<libchiaking::play::ConnectProgress> connects_;
  std::vector<Launch> launches_;
  std::vector<Kakusan> shared_;
};

}  // namespace chiaki_bridge_testing
