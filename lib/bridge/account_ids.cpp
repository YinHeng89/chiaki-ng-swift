#include "account_ids.hpp"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <span>

namespace chiaki_bridge {

void AccountIds::place(libchiaking::AccountId account,
                       std::uint8_t* bytes) noexcept {
  const auto octets = account.bytes();
  std::memcpy(bytes, octets.data(), octets.size());
}

auto AccountIds::account_of(const std::uint8_t* bytes) noexcept
    -> libchiaking::AccountId {
  return libchiaking::AccountId::from_bytes(std::as_bytes(
      std::span<const std::uint8_t, libchiaking::psn_account_id_size>{
          bytes, libchiaking::psn_account_id_size}));
}

auto AccountIds::account_of(const Bytes& bytes) noexcept
    -> std::optional<libchiaking::AccountId> {
  if (bytes.size() != libchiaking::psn_account_id_size) {
    return std::nullopt;
  }
  return account_of(bytes.data());
}

}  // namespace chiaki_bridge
