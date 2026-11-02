#pragma once

#include <cstdint>
#include <libchiaking/consoles.hpp>
#include <optional>

#include "chiaki_bridge/core.hpp"

namespace chiaki_bridge {

class ConsoleIds {
 public:
  static auto hardware_of(const std::uint8_t* bytes) noexcept
      -> std::optional<libchiaking::consoles::HardwareId>;
  static auto device_of(const std::uint8_t* bytes) noexcept
      -> std::optional<libchiaking::consoles::DeviceUid>;
  static void place(libchiaking::consoles::HardwareId hardware_id,
                    std::uint8_t* bytes) noexcept;
  static void place(const libchiaking::consoles::DeviceUid& device,
                    std::uint8_t* bytes) noexcept;
  static auto hardware_of(const Bytes& bytes) noexcept
      -> std::optional<libchiaking::consoles::HardwareId>;
  static auto device_of(const Bytes& bytes) noexcept
      -> std::optional<libchiaking::consoles::DeviceUid>;
};

}  // namespace chiaki_bridge
