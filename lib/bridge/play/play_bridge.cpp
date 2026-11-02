#include <algorithm>

#include "audio.h"
#include "audio_path.hpp"
#include "boundary.hpp"
#include "chiaki_bridge/play.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::catalog::ServiceGeneration;
using libchiaking::consoles::Generation;
using libchiaking::play::DatacenterMeasurement;
using libchiaking::play::DeveloperTuning;
using libchiaking::play::InternetOptions;

auto PlayBridge::facts_of(const DatacenterMeasurement& measurement)
    -> DatacenterFacts {
  const auto& probe = measurement.probe();
  DatacenterFacts facts{};
  facts.name = measurement.name().text();
  facts.round_trip_ms = measurement.round_trip().count();
  facts.measured_at_ms = Timestamp::milliseconds_of(measurement.measured_at());
  facts.samples_ms.reserve(probe.samples.size());
  std::ranges::transform(probe.samples, std::back_inserter(facts.samples_ms),
                         [](auto sample) { return sample.count(); });
  facts.mtu_in = probe.mtu_in;
  facts.mtu_out = probe.mtu_out;
  facts.port = probe.port;
  facts.max_bandwidth = probe.max_bandwidth;
  facts.public_address = probe.public_address;
  facts.bandwidth_kbps = probe.bandwidth_kbps;
  facts.bandwidth_measured_at_ms =
      Timestamp::milliseconds_of(probe.bandwidth_measured_at);
  facts.bandwidth_round_trip_ms = probe.bandwidth_round_trip.count();
  return facts;
}

auto PlayBridge::known_datacenters_of(libchiaking::ChiakiNg& core,
                                      ServiceGeneration service)
    -> DatacenterList {
  DatacenterList listed;
  for (const auto& measurement : core.play().known_datacenters(service).all()) {
    listed.push_back(facts_of(measurement));
  }
  return listed;
}

auto PlayBridge::forget_datacenters_of(libchiaking::ChiakiNg& core,
                                       ServiceGeneration service) -> bool {
  return core.play().forget_datacenters(service).has_value();
}

auto PlayBridge::known_datacenters(ServiceGeneration service)
    -> DatacenterList {
  return Boundary::fenced(DatacenterList{}, [&] {
    const auto opened = Opened::shared();
    return opened ? known_datacenters_of(opened->chiaki(), service)
                  : DatacenterList{};
  });
}

auto PlayBridge::forget_datacenters(ServiceGeneration service) -> bool {
  return Boundary::fenced(false, [&] {
    const auto opened = Opened::shared();
    return opened && forget_datacenters_of(opened->chiaki(), service);
  });
}

auto PlayBridge::built_protocol_version(StreamTarget target) noexcept
    -> std::uint32_t {
  switch (target) {
    case StreamTarget::local_ps4:
      return DeveloperTuning::built_protocol_version(Generation::ps4);
    case StreamTarget::local_ps5:
      return DeveloperTuning::built_protocol_version(Generation::ps5);
    case StreamTarget::ps_now:
      return DeveloperTuning::built_protocol_version(
          ServiceGeneration::old_service);
    case StreamTarget::ps_cloud:
      return DeveloperTuning::built_protocol_version(
          ServiceGeneration::ps5_cloud);
  }
  return 0;
}

auto PlayBridge::supports_audio_channels(StreamTarget target,
                                         std::uint32_t channels) noexcept
    -> bool {
  return AudioPath::supports(target, channels);
}

auto PlayBridge::supports_audio_3d(StreamTarget target) noexcept -> bool {
  return AudioPath::supports_3d(target);
}

auto PlayBridge::port_guessing() noexcept -> PortGuessing {
  return {.fewest = InternetOptions::minimum_port_guesses,
          .usual = InternetOptions::default_port_guesses,
          .most = InternetOptions::maximum_port_guesses};
}

auto PlayBridge::audio_buffering() noexcept -> AudioBuffering {
  return {.shortest_ms = NX_AUDIO_BUFFER_MIN_MS,
          .usual_ms = NX_AUDIO_BUFFER_DEFAULT_MS,
          .longest_ms = NX_AUDIO_BUFFER_MAX_MS};
}

}  // namespace chiaki_bridge
