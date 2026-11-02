#include "DatacenterStoreAdapter.hpp"

#include <chrono>
#include <cstdint>
#include <string>
#include <utility>

#include "ChiakiPersistence-Swift.h"

namespace chiaki_store_adapters {

using ChiakiPersistence::CoreCloudService;
using libchiaking::unexpected;
using libchiaking::catalog::ServiceGeneration;
using libchiaking::play::DatacenterMeasurement;
using libchiaking::play::DatacenterName;

struct DatacenterStoreAdapter::Gateway {
  ChiakiPersistence::CoreDatacenterGateway store;

  static auto service_of(ServiceGeneration service) -> CoreCloudService {
    switch (service) {
      case ServiceGeneration::old_service:
        return CoreCloudService::psNow();
      case ServiceGeneration::ps5_cloud:
        return CoreCloudService::psCloud();
    }
    return CoreCloudService::psCloud();
  }

  static auto time_of(std::int64_t milliseconds)
      -> DatacenterMeasurement::Time {
    return DatacenterMeasurement::Time{std::chrono::milliseconds{milliseconds}};
  }

  static auto measurement_of(
      const ChiakiPersistence::CoreDatacenterRecord& record)
      -> std::optional<DatacenterMeasurement> {
    auto name = DatacenterName::parse(std::string(record.getName()));
    if (!name) {
      return std::nullopt;
    }
    DatacenterMeasurement::Probe probe;
    for (const auto sample : record.getSamplesMs()) {
      probe.samples.emplace_back(sample);
    }
    probe.mtu_in = record.getMtuIn();
    probe.mtu_out = record.getMtuOut();
    probe.port = record.getPort();
    probe.public_address = std::string(record.getPublicAddress());
    probe.max_bandwidth = record.getMaxBandwidth();
    probe.bandwidth_kbps = record.getBandwidthKbps();
    probe.bandwidth_measured_at = time_of(record.getBandwidthMeasuredAt());
    probe.bandwidth_round_trip =
        DatacenterMeasurement::RoundTrip{record.getBandwidthRoundTripMs()};
    return DatacenterMeasurement::create(
        std::move(*name),
        DatacenterMeasurement::RoundTrip{record.getRoundTripMs()},
        time_of(record.getMeasuredAt()), std::move(probe));
  }
};

DatacenterStoreAdapter::DatacenterStoreAdapter(void* gateway)
    : gateway_(std::make_unique<Gateway>(
          Gateway{ChiakiPersistence::CoreStoreGateway::adopting(gateway).getDatacenters()})) {}

DatacenterStoreAdapter::~DatacenterStoreAdapter() = default;

auto DatacenterStoreAdapter::load(ServiceGeneration service)
    -> libchiaking::Expected<std::vector<DatacenterMeasurement>, Error> {
  auto loaded = gateway_->store.loadDatacenters(Gateway::service_of(service));
  if (!loaded.isSome()) {
    return unexpected(Error::unavailable);
  }
  std::vector<DatacenterMeasurement> measurements;
  for (const auto& record : loaded.getSome().getMeasurements()) {
    if (auto measurement = Gateway::measurement_of(record)) {
      measurements.push_back(std::move(*measurement));
    }
  }
  return measurements;
}

auto DatacenterStoreAdapter::save(
    ServiceGeneration service,
    std::span<const DatacenterMeasurement> measurements)
    -> libchiaking::Expected<void, Error> {
  auto batch = gateway_->store.newDatacenterBatch();
  for (const auto& measurement : measurements) {
    const auto& probe = measurement.probe();
    std::vector<std::int32_t> samples;
    samples.reserve(probe.samples.size());
    for (const auto sample : probe.samples) {
      samples.push_back(static_cast<std::int32_t>(sample.count()));
    }
    auto draft =
        batch.add(swift::String(measurement.name().text()),
                  static_cast<std::int32_t>(measurement.round_trip().count()),
                  measurement.measured_at().time_since_epoch().count());
    draft.setSamples(samples.empty() ? nullptr : samples.data(),
                     static_cast<swift::Int>(samples.size()));
    draft.setRoute(probe.mtu_in, probe.mtu_out, probe.port,
                   swift::String(probe.public_address), probe.max_bandwidth);
    draft.setBandwidth(
        probe.bandwidth_kbps, probe.bandwidth_measured_at.time_since_epoch().count(),
        static_cast<std::int32_t>(probe.bandwidth_round_trip.count()));
  }
  if (!gateway_->store.saveDatacenters(batch, Gateway::service_of(service))) {
    return unexpected(Error::unavailable);
  }
  return {};
}

}  // namespace chiaki_store_adapters
