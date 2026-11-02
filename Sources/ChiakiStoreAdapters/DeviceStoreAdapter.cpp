#include "DeviceStoreAdapter.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <libchiaking/users_types.hpp>
#include <string>
#include <utility>

#include "ChiakiPersistence-Swift.h"
#include "boundary.hpp"

namespace chiaki_store_adapters {

using libchiaking::unexpected;
using libchiaking::kakusan::Fingerprint;
using libchiaking::kakusan::IdentityKey;
using libchiaking::kakusan::SavedDevice;
using libchiaking::kakusan::SavedIdentity;

struct DeviceStoreAdapter::Gateway {
  ChiakiPersistence::CoreDeviceGateway store;

  template <class Identifier>
  static auto identifier_of(const swift::Array<std::uint8_t>& array)
      -> std::optional<Identifier> {
    typename Identifier::Bytes bytes{};
    if (array.getCount() != static_cast<swift::Int>(bytes.size())) {
      return std::nullopt;
    }
    for (std::size_t index = 0; index < bytes.size(); ++index) {
      bytes[index] =
          static_cast<std::byte>(array[static_cast<swift::Int>(index)]);
    }
    return Identifier{bytes};
  }
};

DeviceStoreAdapter::DeviceStoreAdapter(void* gateway)
    : gateway_(std::make_unique<Gateway>(
          Gateway{ChiakiPersistence::CoreStoreGateway::adopting(gateway)
                      .getDevices()})) {}

DeviceStoreAdapter::~DeviceStoreAdapter() = default;

auto DeviceStoreAdapter::load_identity()
    -> libchiaking::Expected<std::optional<SavedIdentity>, Error> {
  SavedIdentity saved;
  IdentityKey::Bytes key{};
  const auto loaded =
      gateway_->store.loadDeviceIdentity(saved.seed.data(), key.data());
  if (loaded.isUnavailable()) {
    return unexpected(Error::unavailable);
  }
  if (!loaded.isPresent()) {
    return std::nullopt;
  }
  saved.key = IdentityKey{key};
  return std::optional<SavedIdentity>{std::move(saved)};
}

auto DeviceStoreAdapter::save_identity(const SavedIdentity& identity)
    -> libchiaking::Expected<void, Error> {
  if (!gateway_->store.saveDeviceIdentity(
          identity.seed.data(), identity.key.bytes().data(),
          identity.fingerprint.bytes().data())) {
    return unexpected(Error::unavailable);
  }
  return {};
}

auto DeviceStoreAdapter::load_devices()
    -> libchiaking::Expected<std::vector<SavedDevice>, Error> {
  auto loaded = gateway_->store.loadDevices();
  if (!loaded.isSome()) {
    return unexpected(Error::unavailable);
  }
  std::vector<SavedDevice> devices;
  for (const auto& record : loaded.getSome().getDevices()) {
    const auto key = Gateway::identifier_of<IdentityKey>(record.getKey());
    const auto fingerprint =
        Gateway::identifier_of<Fingerprint>(record.getFingerprint());
    if (!key || !fingerprint) {
      continue;
    }
    devices.push_back(SavedDevice{
        *key, std::string(record.getNickname()),
        chiaki_bridge::Timestamp::moment_of(record.getFirstVerifiedAt()),
        chiaki_bridge::Timestamp::moment_of(record.getLastSeenAt()), *fingerprint});
  }
  return devices;
}

auto DeviceStoreAdapter::save(const SavedDevice& device)
    -> libchiaking::Expected<void, Error> {
  if (!gateway_->store.saveDevice(
          device.key.bytes().data(), device.fingerprint.bytes().data(),
          swift::String(device.nickname),
          chiaki_bridge::Timestamp::milliseconds_of(device.first_verified),
          chiaki_bridge::Timestamp::milliseconds_of(device.last_seen))) {
    return unexpected(Error::unavailable);
  }
  return {};
}

auto DeviceStoreAdapter::remove(const IdentityKey& key)
    -> libchiaking::Expected<void, Error> {
  if (!gateway_->store.forgetDevice(key.bytes().data())) {
    return unexpected(Error::unavailable);
  }
  return {};
}

}  // namespace chiaki_store_adapters
