#pragma once

#include <cstdint>
#include <libchiaking/chiaki_ng.hpp>
#include <libchiaking/play.hpp>
#include <optional>
#include <string>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

enum class StreamTarget : std::uint8_t {
  local_ps4,
  local_ps5,
  ps_now,
  ps_cloud,
};

using MillisecondSamples = std::vector<std::int64_t>;

struct DatacenterFacts {
  std::string name;
  std::int64_t round_trip_ms;
  std::int64_t measured_at_ms;
  MillisecondSamples samples_ms;
  std::int32_t mtu_in;
  std::int32_t mtu_out;
  std::int32_t port;
  std::int32_t max_bandwidth;
  std::string public_address;
  std::int32_t bandwidth_kbps;
  std::int64_t bandwidth_measured_at_ms;
  std::int64_t bandwidth_round_trip_ms;
};

using DatacenterList = std::vector<DatacenterFacts>;

struct PortGuessing {
  std::uint32_t fewest;
  std::uint32_t usual;
  std::uint32_t most;
};

struct AudioBuffering {
  std::uint32_t shortest_ms;
  std::uint32_t usual_ms;
  std::uint32_t longest_ms;
};

class PlayBridge {
 public:
  static auto known_datacenters(libchiaking::catalog::ServiceGeneration service)
      -> DatacenterList;
  static auto forget_datacenters(
      libchiaking::catalog::ServiceGeneration service) -> bool;
  static auto known_datacenters_of(
      libchiaking::ChiakiNg& core,
      libchiaking::catalog::ServiceGeneration service) -> DatacenterList;
  static auto forget_datacenters_of(
      libchiaking::ChiakiNg& core,
      libchiaking::catalog::ServiceGeneration service) -> bool;
  static auto built_protocol_version(StreamTarget target) noexcept
      -> std::uint32_t;
  static auto supports_audio_channels(StreamTarget target,
                                      std::uint32_t channels) noexcept -> bool;
  static auto supports_audio_3d(StreamTarget target) noexcept -> bool;
  static auto port_guessing() noexcept -> PortGuessing;
  static auto audio_buffering() noexcept -> AudioBuffering;
  static auto facts_of(
      const libchiaking::play::DatacenterMeasurement& measurement)
      -> DatacenterFacts;
};

}  // namespace chiaki_bridge
