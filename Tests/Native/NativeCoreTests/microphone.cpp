#include <opus.h>

#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <numbers>
#include <span>
#include <vector>

#include "chiaki_bridge/media.hpp"
#include "chiaki_bridge/stream.hpp"
#include "support/recording_listener.hpp"

using chiaki_bridge::MicrophoneEncoder;

static void fill_tone(std::vector<std::int16_t>& pcm, std::size_t frame,
                      double frequency) {
  const auto samples = MicrophoneEncoder::samples_per_frame();
  const auto channels = MicrophoneEncoder::channels();
  for (std::size_t index = 0; index < samples; index++) {
    const double time = static_cast<double>(frame * samples + index) /
                        MicrophoneEncoder::sample_rate();
    const auto sample = static_cast<std::int16_t>(
        std::sin(2 * std::numbers::pi * frequency * time) * 12000);
    pcm[index * channels] = sample;
    pcm[index * channels + 1] = sample;
  }
}

static void test_encoder() {
  auto encoder = MicrophoneEncoder::create();
  assert(encoder);
  int error = OPUS_OK;
  OpusDecoder* decoder = opus_decoder_create(
      static_cast<opus_int32>(MicrophoneEncoder::sample_rate()),
      static_cast<int>(MicrophoneEncoder::channels()), &error);
  assert(decoder && error == OPUS_OK);
  const auto samples = MicrophoneEncoder::samples_per_frame();
  std::vector<std::int16_t> pcm(samples * MicrophoneEncoder::channels());
  std::vector<std::int16_t> decoded(pcm.size());
  std::vector<std::uint8_t> frame(MicrophoneEncoder::frame_size());
  for (std::size_t index = 0; index < 200; index++) {
    if (index < 50) {
      std::ranges::fill(pcm, std::int16_t{0});
    } else {
      fill_tone(pcm, index, index < 120 ? 440.0 : 3100.0);
    }
    assert(encoder->encode(pcm, frame));
    const int decodedSamples = opus_decode(
        decoder, frame.data(), static_cast<opus_int32>(frame.size()),
        decoded.data(), static_cast<int>(samples), 0);
    assert(decodedSamples == static_cast<int>(samples));
  }
  assert(!encoder->encode(std::span{pcm}.first(pcm.size() - 1), frame));
  assert(!encoder->encode(pcm, std::span{frame}.first(frame.size() - 1)));
  opus_decoder_destroy(decoder);
}

static void test_idle_stream_rejects() {
  using libchiaking::play::Microphone;
  chiaki_bridge_testing::RecordingListener heard;
  const auto stream = chiaki_bridge::Stream::open(heard);
  assert(stream);
  std::vector<std::uint8_t> frame(Microphone::frame_size);
  assert(!stream->connect_microphone(1));
  assert(stream->microphone_state(1) == Microphone::ConnectState::rejected);
  assert(!stream->set_microphone_muted(true));
  assert(!stream->set_microphone_muted(false));
  assert(!stream->send_microphone(frame));
  assert(!stream->send_microphone(std::span{frame}.first(frame.size() - 1)));
  const auto stats = stream->microphone_statistics();
  assert(stats.frames_queued == 0 && stats.frames_sent == 0 &&
         stats.frames_dropped == 0);
}

auto main() -> int {
  test_encoder();
  test_idle_stream_rejects();
  std::puts("microphone bridge ok");
  return 0;
}
