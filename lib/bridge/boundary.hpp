#pragma once

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

namespace chiaki_bridge {

class Argument {
 public:
  explicit Argument(const char* text) noexcept
      : view_(text != nullptr ? std::string_view{text} : std::string_view{}) {}

  auto view() const noexcept -> std::string_view { return view_; }

  auto empty() const noexcept -> bool { return view_.empty(); }

  auto within(std::size_t limit) const noexcept -> bool {
    return view_.size() <= limit;
  }

  auto present_within(std::size_t limit) const noexcept -> bool {
    return !view_.empty() && view_.size() <= limit;
  }

 private:
  std::string_view view_;
};

class Timestamp {
 public:
  using Moment = std::chrono::system_clock::time_point;

  static auto moment_of(std::int64_t milliseconds) noexcept -> Moment {
    return Moment{std::chrono::duration_cast<Moment::duration>(
        std::chrono::milliseconds{milliseconds})};
  }

  template <class Duration>
  static auto milliseconds_of(std::chrono::sys_time<Duration> moment) noexcept
      -> std::int64_t {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               moment.time_since_epoch())
        .count();
  }
};

class Boundary {
 public:
  template <class Result, class Call>
  static auto fenced(Result fallback, Call&& call) noexcept -> Result {
    try {
      return std::forward<Call>(call)();
    } catch (...) {
      return fallback;
    }
  }
};

class IdentifierBytes {
 public:
  template <class Identifier>
  static auto of(const Identifier& identifier) -> std::vector<std::uint8_t> {
    const auto octets = identifier.bytes();
    std::vector<std::uint8_t> bytes(octets.size());
    std::ranges::transform(octets, bytes.begin(),
                           std::to_integer<std::uint8_t>);
    return bytes;
  }
};

}  // namespace chiaki_bridge
