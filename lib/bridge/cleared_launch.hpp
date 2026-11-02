#pragma once

#include <libchiaking/catalog.hpp>
#include <optional>
#include <utility>

#include "chiaki_bridge/catalog.hpp"

namespace chiaki_bridge {

class ClearedLaunch {
 public:
  explicit ClearedLaunch(libchiaking::catalog::ClearedLaunch launch)
      : launch_(std::move(launch)) {}

  auto launch() const noexcept -> const libchiaking::catalog::ClearedLaunch& {
    return launch_;
  }

  static auto of(const ClearedLaunch* cleared)
      -> std::optional<libchiaking::catalog::ClearedLaunch> {
    return cleared != nullptr ? std::optional{cleared->launch()} : std::nullopt;
  }

 private:
  libchiaking::catalog::ClearedLaunch launch_;
};

}  // namespace chiaki_bridge
