#include "ConsoleStoreAdapter.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <libchiaking/users_types.hpp>
#include <string>
#include <utility>

#include "ChiakiPersistence-Swift.h"

namespace chiaki_store_adapters {

using ChiakiPersistence::CoreFirmware;
using ChiakiPersistence::CoreNameSource;
using libchiaking::SecretArray;
using libchiaking::unexpected;
using libchiaking::consoles::ConsoleName;
using libchiaking::consoles::DeviceUid;
using libchiaking::consoles::Firmware;
using libchiaking::consoles::HardwareId;
using libchiaking::consoles::Host;
using libchiaking::consoles::PairingKeys;
using libchiaking::consoles::SavedConsole;
using libchiaking::consoles::SavedPairing;

struct ConsoleStoreAdapter::Gateway {
  ChiakiPersistence::CoreConsoleGateway store;

  static auto firmware_of(const CoreFirmware& firmware) -> Firmware {
    switch (firmware) {
      case CoreFirmware::ps4_8:
        return Firmware{Firmware::Family::ps4_8};
      case CoreFirmware::ps4_9:
        return Firmware{Firmware::Family::ps4_9};
      case CoreFirmware::ps4_10:
        return Firmware{Firmware::Family::ps4_10};
      case CoreFirmware::ps5:
        return Firmware{Firmware::Family::ps5_1};
    }
    return Firmware{Firmware::Family::ps4_10};
  }

  static auto firmware_of(Firmware firmware) -> CoreFirmware {
    switch (firmware.family()) {
      case Firmware::Family::ps4_8:
        return CoreFirmware::ps4_8();
      case Firmware::Family::ps4_9:
        return CoreFirmware::ps4_9();
      case Firmware::Family::ps4_10:
        return CoreFirmware::ps4_10();
      case Firmware::Family::ps5_1:
        return CoreFirmware::ps5();
    }
    return CoreFirmware::ps4_10();
  }

  static auto source_of(const CoreNameSource& source) -> ConsoleName::Source {
    switch (source) {
      case CoreNameSource::generation:
        return ConsoleName::Source::generation;
      case CoreNameSource::account:
        return ConsoleName::Source::account;
      case CoreNameSource::pairing:
        return ConsoleName::Source::pairing;
      case CoreNameSource::discovered:
        return ConsoleName::Source::discovered;
      case CoreNameSource::renamed:
        return ConsoleName::Source::renamed;
    }
    return ConsoleName::Source::renamed;
  }

  static auto source_of(ConsoleName::Source source) -> CoreNameSource {
    switch (source) {
      case ConsoleName::Source::generation:
        return CoreNameSource::generation();
      case ConsoleName::Source::account:
        return CoreNameSource::account();
      case ConsoleName::Source::pairing:
        return CoreNameSource::pairing();
      case ConsoleName::Source::discovered:
        return CoreNameSource::discovered();
      case ConsoleName::Source::renamed:
        return CoreNameSource::renamed();
    }
    return CoreNameSource::renamed();
  }

  template <std::size_t Size>
  static auto bytes_of(const swift::Array<std::uint8_t>& array)
      -> std::optional<std::array<std::byte, Size>> {
    if (array.getCount() != static_cast<swift::Int>(Size)) {
      return std::nullopt;
    }
    std::array<std::byte, Size> bytes{};
    for (std::size_t index = 0; index < Size; ++index) {
      bytes[index] =
          static_cast<std::byte>(array[static_cast<swift::Int>(index)]);
    }
    return bytes;
  }

  static auto console_of(const ChiakiPersistence::CoreConsoleRecord& record)
      -> std::optional<SavedConsole> {
    const auto bytes = bytes_of<HardwareId::size>(record.getHardwareID());
    if (!bytes) {
      return std::nullopt;
    }
    const auto hardware_id = HardwareId::from_bytes(*bytes);
    if (!hardware_id) {
      return std::nullopt;
    }
    const auto firmware = firmware_of(record.getFirmware());
    auto name = ConsoleName::create(std::string(record.getName()),
                                    source_of(record.getNameSource()));
    SavedConsole saved{
        *hardware_id, firmware,
        name ? std::move(*name) : ConsoleName::of(firmware.generation()),
        std::nullopt};
    const auto address = record.getAddress();
    if (address.isSome()) {
      if (auto host = Host::create(std::string(address.getSome()),
                                   firmware.generation())) {
        saved.last_address = std::move(host.value());
      }
    }
    return saved;
  }

  auto pairing_of(ChiakiPersistence::CoreConsoleLedger& ledger,
                  const ChiakiPersistence::CorePairingRecord& record,
                  swift::Int index) -> std::optional<SavedPairing> {
    const auto account =
        bytes_of<libchiaking::psn_account_id_size>(record.getAccountID());
    const auto console = bytes_of<HardwareId::size>(record.getHardwareID());
    if (!account || !console) {
      return std::nullopt;
    }
    const auto hardware_id = HardwareId::from_bytes(*console);
    if (!hardware_id) {
      return std::nullopt;
    }
    SecretArray<PairingKeys::registration_key_size> registration;
    SecretArray<PairingKeys::remote_play_key_size> remote_play;
    if (!ledger.copyKeys(index, registration.data(), remote_play.data())) {
      return std::nullopt;
    }
    auto keys = PairingKeys::create(registration.span(), remote_play.span(),
                                    record.getKeyType());
    if (!keys) {
      return std::nullopt;
    }
    std::optional<DeviceUid> device;
    const auto stored_device = record.getDeviceUID();
    if (stored_device.isSome()) {
      if (const auto device_bytes =
              bytes_of<DeviceUid::size>(stored_device.getSome())) {
        device = DeviceUid::from_bytes(*device_bytes);
      }
    }
    return SavedPairing{libchiaking::AccountId::from_bytes(*account),
                        *hardware_id, std::move(*keys), device};
  }
};

ConsoleStoreAdapter::ConsoleStoreAdapter(void* gateway)
    : gateway_(std::make_unique<Gateway>(
          Gateway{ChiakiPersistence::CoreStoreGateway::adopting(gateway)
                      .getConsoles()})) {}

ConsoleStoreAdapter::~ConsoleStoreAdapter() = default;

auto ConsoleStoreAdapter::load_saved_consoles()
    -> libchiaking::Expected<Saved, Error> {
  auto loaded = gateway_->store.loadConsoles();
  if (!loaded.isSome()) {
    return unexpected(Error::unavailable);
  }
  auto ledger = loaded.getSome();
  Saved saved;
  for (const auto& record : ledger.getConsoles()) {
    if (auto console = Gateway::console_of(record)) {
      saved.consoles.push_back(std::move(*console));
    }
  }
  swift::Int index = 0;
  for (const auto& record : ledger.getPairings()) {
    if (auto pairing = gateway_->pairing_of(ledger, record, index)) {
      saved.pairings.push_back(std::move(*pairing));
    }
    ++index;
  }
  return saved;
}

auto ConsoleStoreAdapter::save(const SavedConsole& console)
    -> libchiaking::Expected<void, Error> {
  const auto address = console.last_address
                           ? swift::Optional<swift::String>::init(
                                 swift::String(console.last_address->text()))
                           : swift::Optional<swift::String>::none();
  if (!gateway_->store.saveConsole(console.hardware_id.bytes().data(),
                                   Gateway::firmware_of(console.firmware),
                                   swift::String(console.name.text()),
                                   Gateway::source_of(console.name.source()),
                                   address)) {
    return unexpected(Error::unavailable);
  }
  return {};
}

auto ConsoleStoreAdapter::save(const SavedPairing& pairing)
    -> libchiaking::Expected<void, Error> {
  const auto account = pairing.account.bytes();
  auto draft = gateway_->store.beginPairing(account.data(),
                                            pairing.console.bytes().data());
  draft.setKeys(pairing.keys.registration_key().data(),
                pairing.keys.remote_play_key().data(), pairing.keys.key_type());
  if (pairing.device_uid) {
    draft.setDeviceUID(pairing.device_uid->bytes().data());
  }
  if (!gateway_->store.savePairing(draft)) {
    return unexpected(Error::unavailable);
  }
  return {};
}

auto ConsoleStoreAdapter::remove_pairing(libchiaking::AccountId account,
                                         HardwareId console)
    -> libchiaking::Expected<void, Error> {
  const auto bytes = account.bytes();
  if (!gateway_->store.removePairing(bytes.data(), console.bytes().data())) {
    return unexpected(Error::unavailable);
  }
  return {};
}

auto ConsoleStoreAdapter::remove_console(HardwareId console)
    -> libchiaking::Expected<void, Error> {
  if (!gateway_->store.removeConsole(console.bytes().data())) {
    return unexpected(Error::unavailable);
  }
  return {};
}

}  // namespace chiaki_store_adapters
