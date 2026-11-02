#pragma once

#include <libchiaking/play.hpp>
#include <map>
#include <mutex>
#include <span>
#include <vector>

namespace chiaki_bridge_testing {

class MemoryDatacenterStore final : public libchiaking::play::DatacenterStore {
 public:
  [[nodiscard]] auto load(libchiaking::catalog::ServiceGeneration service)
      -> libchiaking::Expected<
          std::vector<libchiaking::play::DatacenterMeasurement>,
          Error> override {
    const std::lock_guard lock{mutex_};
    return measurements_[service];
  }

  [[nodiscard]] auto save(
      libchiaking::catalog::ServiceGeneration service,
      std::span<const libchiaking::play::DatacenterMeasurement> measurements)
      -> libchiaking::Expected<void, Error> override {
    const std::lock_guard lock{mutex_};
    measurements_[service].assign(measurements.begin(), measurements.end());
    return {};
  }

  auto held(libchiaking::catalog::ServiceGeneration service)
      -> std::vector<libchiaking::play::DatacenterMeasurement> {
    const std::lock_guard lock{mutex_};
    return measurements_[service];
  }

 private:
  std::mutex mutex_;
  std::map<libchiaking::catalog::ServiceGeneration,
           std::vector<libchiaking::play::DatacenterMeasurement>>
      measurements_;
};

}  // namespace chiaki_bridge_testing
