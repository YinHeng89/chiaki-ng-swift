#pragma once

#include <cstdint>
#include <libchiaking/play.hpp>
#include <utility>
#include <variant>

#include "core.hpp"

namespace chiaki_bridge {

/// How finding this device's NAT type ended: found, failed or with the core
/// closed.
class NatTypeOutcome {
 public:
  /// The ways the check can end.
  enum class Kind : std::uint8_t {
    /// The check found the NAT type.
    found,
    /// The check could not find it.
    failed,
    /// The core is not open.
    closed,
  };

  /// A NAT type the check found.
  static auto found(libchiaking::play::NatType value) -> NatTypeOutcome {
    return NatTypeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::found)>,
             std::move(value)}};
  }

  /// A check that could not find the NAT type.
  static auto failed(libchiaking::play::NatTypeFailure::Reason value)
      -> NatTypeOutcome {
    return NatTypeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::failed)>,
             std::move(value)}};
  }

  /// A check made while the core was closed.
  static auto closed() -> NatTypeOutcome {
    return NatTypeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the check ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The NAT type; valid for `found`.
  auto type() const -> libchiaking::play::NatType {
    return std::get<std::to_underlying(Kind::found)>(held_);
  }

  /// Why the check failed; valid for `failed`.
  auto reason() const -> libchiaking::play::NatTypeFailure::Reason {
    return std::get<std::to_underlying(Kind::failed)>(held_);
  }

 private:
  using Case =
      std::variant<libchiaking::play::NatType,
                   libchiaking::play::NatTypeFailure::Reason, std::monostate>;

  explicit NatTypeOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// Checks this device's network through the open core.
class NetworkBridge {
 public:
  /// Finds this device's NAT type.
  static auto nat_type(const Request& request) -> NatTypeOutcome;
};

}  // namespace chiaki_bridge
