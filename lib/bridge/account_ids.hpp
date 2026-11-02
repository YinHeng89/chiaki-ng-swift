#pragma once

#include <cstdint>
#include <libchiaking/users.hpp>
#include <optional>

#include "chiaki_bridge/core.hpp"

namespace chiaki_bridge {

class AccountIds {
 public:
  static void place(libchiaking::AccountId account,
                    std::uint8_t* bytes) noexcept;
  static auto account_of(const std::uint8_t* bytes) noexcept
      -> libchiaking::AccountId;
  static auto account_of(const Bytes& bytes) noexcept
      -> std::optional<libchiaking::AccountId>;
};

}  // namespace chiaki_bridge
