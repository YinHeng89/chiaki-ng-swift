#pragma once

#ifdef __cplusplus
#include <libchiaking/play.hpp>
#include <memory>
#include <span>
#include <vector>

namespace chiaki_store_adapters {

class DatacenterStoreAdapter final : public libchiaking::play::DatacenterStore {
 public:
  explicit DatacenterStoreAdapter(void* gateway);
  ~DatacenterStoreAdapter() override;
  DatacenterStoreAdapter(const DatacenterStoreAdapter&) = delete;
  auto operator=(const DatacenterStoreAdapter&)
      -> DatacenterStoreAdapter& = delete;

  [[nodiscard]] auto load(libchiaking::catalog::ServiceGeneration service)
      -> libchiaking::Expected<
          std::vector<libchiaking::play::DatacenterMeasurement>,
          Error> override;
  [[nodiscard]] auto save(
      libchiaking::catalog::ServiceGeneration service,
      std::span<const libchiaking::play::DatacenterMeasurement> measurements)
      -> libchiaking::Expected<void, Error> override;

 private:
  struct Gateway;

  std::unique_ptr<Gateway> gateway_;
};

}  // namespace chiaki_store_adapters

#endif
