#pragma once

#ifdef __cplusplus
#include <memory>

namespace libchiaking::consoles {
class ConsoleStore;
}

namespace libchiaking::users {
class CredentialStore;
}

namespace libchiaking::play {
class DatacenterStore;
}

namespace libchiaking::kakusan {
class DeviceStore;
}

namespace chiaki_store_adapters {

class StoreAdapters {
 public:
  static auto console_store(void* gateway)
      -> std::shared_ptr<libchiaking::consoles::ConsoleStore>;
  static auto credential_store(void* gateway)
      -> std::shared_ptr<libchiaking::users::CredentialStore>;
  static auto datacenter_store(void* gateway)
      -> std::shared_ptr<libchiaking::play::DatacenterStore>;
  static auto device_store(void* gateway)
      -> std::shared_ptr<libchiaking::kakusan::DeviceStore>;
};

}  // namespace chiaki_store_adapters

#endif
