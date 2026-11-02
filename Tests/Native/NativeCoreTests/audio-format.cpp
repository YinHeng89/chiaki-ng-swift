#include <cassert>
#include <cstddef>
#include <cstdint>
#include <vector>

#include "audio_path.hpp"

int main() {
  nx_bridge_log log;
  chiaki_bridge::AudioPath path{log};
  for (const std::uint32_t channels : {0, 2, 6, 8, 12}) {
    assert(chiaki_bridge::AudioPath::supports(
        chiaki_bridge::StreamTarget::local_ps5, channels));
    assert(chiaki_bridge::AudioPath::supports(
        chiaki_bridge::StreamTarget::ps_cloud, channels));
    assert(chiaki_bridge::AudioPath::supports(
               chiaki_bridge::StreamTarget::local_ps4, channels) ==
           (channels <= 2));
    assert(chiaki_bridge::AudioPath::supports(
               chiaki_bridge::StreamTarget::ps_now, channels) ==
           (channels <= 2));
    assert(path.request_channels(channels));
    const auto selected = path.requested();
    assert(selected.channels() == channels);
    assert(
        path.negotiate(selected.on_cloud(
                           libchiaking::catalog::ServiceGeneration::ps5_cloud),
                       "PS5 cloud") == selected);
  }
  assert(!path.request_channels(7));
  assert(path.requested().channels() == 12);
  auto stats = path.statistics();
  assert(stats.received_channels == 0 && stats.received_sample_rate == 0);
  for (const std::uint8_t channels : {2, 6, 8, 12}) {
    libchiaking::media::AudioFormat format{};
    format.channels = channels;
    format.bits = 16;
    format.rate = 48000;
    format.frame_size = 120;
    assert(path.configure(format, true));
    stats = path.statistics();
    assert(stats.received_channels == channels &&
           stats.received_sample_rate == 48000);
    assert(stats.channels == channels);
  }
  {
    chiaki_bridge::AudioPath active{log};
    libchiaking::media::AudioFormat surround{};
    surround.channels = 6;
    surround.bits = 16;
    surround.rate = 48000;
    surround.frame_size = 480;
    assert(active.configure(surround, true));
    std::vector<std::byte> packet(480 * 6 * 2);
    for (std::size_t frame = 0; frame < 480; ++frame) {
      packet[frame * 12] = std::byte{1};
      packet[frame * 12 + 2] = std::byte{1};
    }
    for (int block = 0; block < 99; ++block) {
      static_cast<void>(active.deliver(packet));
    }
    stats = active.statistics();
    assert(stats.received_active_channels == 0);
    static_cast<void>(active.deliver(packet));
    stats = active.statistics();
    assert(stats.received_active_channels == 2);
  }
  libchiaking::media::AudioFormat invalid{};
  invalid.channels = 7;
  invalid.rate = 12345;
  assert(!path.configure(invalid, false));
  stats = path.statistics();
  assert(stats.received_channels == 7 && stats.received_sample_rate == 12345);
  assert(stats.decode_failures == 1);
  path.stop();
  chiaki_bridge::AudioPath next{log};
  stats = next.statistics();
  assert(stats.received_channels == 0 && stats.received_sample_rate == 0);
  return 0;
}
