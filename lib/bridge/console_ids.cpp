#include "console_ids.hpp"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <span>

namespace chiaki_bridge {

using libchiaking::consoles::DeviceUid;
using libchiaking::consoles::HardwareId;

auto ConsoleIds::hardware_of(const std::uint8_t* bytes) noexcept
    -> std::optional<HardwareId> {
  return HardwareId::from_bytes(
      std::as_bytes(std::span<const std::uint8_t, HardwareId::size>{
          bytes, HardwareId::size}));
}

auto ConsoleIds::device_of(const std::uint8_t* bytes) noexcept
    -> std::optional<DeviceUid> {
  return DeviceUid::from_bytes(std::as_bytes(
      std::span<const std::uint8_t, DeviceUid::size>{bytes, DeviceUid::size}));
}

void ConsoleIds::place(HardwareId hardware_id, std::uint8_t* bytes) noexcept {
  std::memcpy(bytes, hardware_id.bytes().data(), HardwareId::size);
}

void ConsoleIds::place(const DeviceUid& device, std::uint8_t* bytes) noexcept {
  std::memcpy(bytes, device.bytes().data(), DeviceUid::size);
}

auto ConsoleIds::hardware_of(const Bytes& bytes) noexcept
    -> std::optional<HardwareId> {
  if (bytes.size() != HardwareId::size) {
    return std::nullopt;
  }
  return hardware_of(bytes.data());
}

auto ConsoleIds::device_of(const Bytes& bytes) noexcept
    -> std::optional<DeviceUid> {
  if (bytes.size() != DeviceUid::size) {
    return std::nullopt;
  }
  return device_of(bytes.data());
}

}  // namespace chiaki_bridge
