#include "StoreAdapters.hpp"

#include "ConsoleStoreAdapter.hpp"
#include "CredentialStoreAdapter.hpp"
#include "DatacenterStoreAdapter.hpp"
#include "DeviceStoreAdapter.hpp"

namespace chiaki_store_adapters {

auto StoreAdapters::console_store(void* gateway)
    -> std::shared_ptr<libchiaking::consoles::ConsoleStore> {
  return std::make_shared<ConsoleStoreAdapter>(gateway);
}

auto StoreAdapters::credential_store(void* gateway)
    -> std::shared_ptr<libchiaking::users::CredentialStore> {
  return std::make_shared<CredentialStoreAdapter>(gateway);
}

auto StoreAdapters::datacenter_store(void* gateway)
    -> std::shared_ptr<libchiaking::play::DatacenterStore> {
  return std::make_shared<DatacenterStoreAdapter>(gateway);
}

auto StoreAdapters::device_store(void* gateway)
    -> std::shared_ptr<libchiaking::kakusan::DeviceStore> {
  return std::make_shared<DeviceStoreAdapter>(gateway);
}

}  // namespace chiaki_store_adapters
