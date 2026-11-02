#pragma once

#ifdef __cplusplus
#include <libchiaking/kakusan.hpp>
#include <memory>
#include <optional>
#include <vector>

namespace chiaki_store_adapters {

class DeviceStoreAdapter final : public libchiaking::kakusan::DeviceStore {
 public:
  explicit DeviceStoreAdapter(void* gateway);
  ~DeviceStoreAdapter() override;
  DeviceStoreAdapter(const DeviceStoreAdapter&) = delete;
  auto operator=(const DeviceStoreAdapter&) -> DeviceStoreAdapter& = delete;

  [[nodiscard]] auto load_identity() -> libchiaking::Expected<
      std::optional<libchiaking::kakusan::SavedIdentity>, Error> override;
  [[nodiscard]] auto save_identity(
      const libchiaking::kakusan::SavedIdentity& identity)
      -> libchiaking::Expected<void, Error> override;
  [[nodiscard]] auto load_devices()
      -> libchiaking::Expected<std::vector<libchiaking::kakusan::SavedDevice>,
                               Error> override;
  [[nodiscard]] auto save(const libchiaking::kakusan::SavedDevice& device)
      -> libchiaking::Expected<void, Error> override;
  [[nodiscard]] auto remove(const libchiaking::kakusan::IdentityKey& key)
      -> libchiaking::Expected<void, Error> override;

 private:
  struct Gateway;

  std::unique_ptr<Gateway> gateway_;
};

}  // namespace chiaki_store_adapters

#endif
