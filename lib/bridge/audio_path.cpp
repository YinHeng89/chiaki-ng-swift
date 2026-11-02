#include "audio_path.hpp"

#include <algorithm>
#include <bit>
#include <format>
#include <limits>
#include <string>
#include <utility>

namespace chiaki_bridge {

using libchiaking::media::AudioDecoder;
using libchiaking::media::AudioResult;
using libchiaking::media::AudioVerdict;
using libchiaking::play::SoundRequest;

void AudioPath::Release::operator()(nx_audio* audio) const noexcept {
  nx_audio_destroy(audio);
}

auto AudioPath::supports(StreamTarget target, std::uint32_t channels) noexcept
    -> bool {
  using libchiaking::catalog::ServiceGeneration;
  using libchiaking::consoles::Generation;
  const auto request = SoundRequest::create(channels);
  if (!request) {
    return false;
  }
  switch (target) {
    case StreamTarget::local_ps4:
      return request->on_console(Generation::ps4) == *request;
    case StreamTarget::local_ps5:
      return request->on_console(Generation::ps5) == *request;
    case StreamTarget::ps_now:
      return request->on_cloud(ServiceGeneration::old_service) == *request;
    case StreamTarget::ps_cloud:
      return request->on_cloud(ServiceGeneration::ps5_cloud) == *request;
  }
  return false;
}

auto AudioPath::supports_3d(StreamTarget target) noexcept -> bool {
  using libchiaking::catalog::ServiceGeneration;
  using libchiaking::consoles::Generation;
  switch (target) {
    case StreamTarget::local_ps4:
      return SoundRequest::supports_3d_on_console(Generation::ps4);
    case StreamTarget::local_ps5:
      return SoundRequest::supports_3d_on_console(Generation::ps5);
    case StreamTarget::ps_now:
      return SoundRequest::supports_3d_on_cloud(ServiceGeneration::old_service);
    case StreamTarget::ps_cloud:
      return SoundRequest::supports_3d_on_cloud(ServiceGeneration::ps5_cloud);
  }
  return false;
}

AudioPath::AudioPath(nx_bridge_log& log)
    : log_(log), output_(nx_audio_create(&log)) {}

auto AudioPath::surround_name(std::uint32_t channels) noexcept
    -> std::string_view {
  switch (channels) {
    case 6:
      return "5.1";
    case 8:
      return "7.1";
    case 12:
      return "7.1.4";
    case 2:
      return "stereo";
    default:
      return "default";
  }
}

auto AudioPath::layout_name(AudioDecoder::Layout layout) noexcept
    -> std::string_view {
  switch (layout) {
    case AudioDecoder::Layout::direct:
      return "direct";
    case AudioDecoder::Layout::reported:
      return "reported";
    case AudioDecoder::Layout::assumed:
      return "assumed";
  }
  return "direct";
}

auto AudioPath::request_channels(std::uint32_t channels) noexcept -> bool {
  if (!SoundRequest::create(channels)) {
    return false;
  }
  requested_channels_ = channels;
  return true;
}

void AudioPath::request_controller_speaker(bool enabled) noexcept {
  controller_speaker_ = enabled;
}

auto AudioPath::requested() const noexcept -> SoundRequest {
  return SoundRequest::create(requested_channels_)
      .value_or(SoundRequest{})
      .with_controller_speaker(controller_speaker_);
}

auto AudioPath::negotiate(SoundRequest granted, std::string_view target)
    -> SoundRequest {
  const std::uint32_t asked = requested_channels_;
  surround_requested_ = 0;
  surround_reported_ = 0;
  if (requested().wants_surround() && !granted.wants_surround()) {
    log_.warning(std::format(
        "core audio surround: {} not supported for {}, using stereo",
        surround_name(asked), target));
  } else if (granted.wants_surround()) {
    surround_requested_ = granted.channels();
    log_.info(
        std::format("core audio surround: requested {} ({} channels) for {}",
                    surround_name(asked), asked, target));
  }
  return granted;
}

auto AudioPath::configure(const libchiaking::media::AudioFormat& format,
                          bool raw_pcm) -> bool {
  received_format_.store((static_cast<std::uint64_t>(format.rate) << 32) |
                         format.channels);
  decoder_.reset();
  voice_.clear();
  channels_ = 0;
  active_channels_ = 0;
  activity_mask_ = 0;
  activity_frames_ = 0;
  auto decoder = AudioDecoder::create(format, raw_pcm);
  if (!decoder) {
    ++failures_;
    last_error_ = bad_argument;
    return false;
  }
  decoder_.emplace(std::move(decoder.value()));
  channels_ = format.channels;
  const auto output = decoder_->output_channels();
  log_.info(std::format(
      "core audio decoder: channels={} rate={} {} layout={} output={}",
      format.channels, format.rate,
      raw_pcm ? "raw" : (decoder_->multistream() ? "multistream" : "opus"),
      layout_name(decoder_->layout()), output));
  nx_audio_configure(output_.get(), static_cast<std::uint32_t>(output),
                     format.rate);
  return true;
}

auto AudioPath::rejected(int code) noexcept -> AudioResult {
  ++failures_;
  last_error_ = code;
  return {AudioVerdict::failed, code};
}

auto AudioPath::deliver(std::span<const std::byte> packet) -> AudioResult {
  if (!decoder_) {
    return rejected(bad_argument);
  }
  if (surround_requested_ != 0 && channels_ != surround_requested_ &&
      surround_reported_ != channels_) {
    surround_reported_ = channels_;
    log_.warning(std::format(
        "core audio surround: requested {} channels, host granted {}",
        surround_requested_, channels_));
  }
  if (packet.empty() && !decoder_->raw_pcm()) {
    ++concealed_;
  }
  const auto pcm = decoder_->decode(packet);
  if (!pcm) {
    return rejected(decoder_->statistics().last_error);
  }
  if (!pcm.value().empty()) {
    const auto channels = decoder_->output_channels();
    const auto mixed = with_side_audio(pcm.value(), channels);
    nx_audio_push(output_.get(), mixed.data(), mixed.size() / channels);
    observe_activity(mixed, channels);
  }
  return {};
}

auto AudioPath::configure_voice(const libchiaking::media::AudioFormat& format,
                                bool raw_pcm) -> bool {
  voice_decoder_.reset();
  voice_.clear();
  auto decoder = AudioDecoder::create(format, raw_pcm);
  if (!decoder) {
    return false;
  }
  voice_decoder_.emplace(std::move(decoder.value()));
  log_.info(std::format(
      "core audio voice decoder: channels={} rate={} frame={} output={}",
      format.channels, format.rate, format.frame_size,
      voice_decoder_->output_channels()));
  return true;
}

auto AudioPath::deliver_voice(std::span<const std::byte> packet)
    -> AudioResult {
  if (!voice_decoder_ || !decoder_ ||
      voice_decoder_->sample_rate() != decoder_->sample_rate()) {
    return {};
  }
  const auto pcm = voice_decoder_->decode(packet);
  const auto channels = voice_decoder_->output_channels();
  if (!pcm || channels == 0) {
    return {};
  }
  for (std::size_t index = 0; index < pcm.value().size(); index += channels) {
    voice_.push_back(pcm.value()[index]);
  }
  if (voice_.size() > max_voice_frames) {
    voice_.erase(voice_.begin(), voice_.end() - static_cast<std::ptrdiff_t>(
                                                    trimmed_voice_frames));
  }
  return {};
}

auto AudioPath::decode_speaker(std::uint8_t seat,
                               std::span<const std::byte> packet)
    -> std::optional<std::span<const std::int16_t>> {
  const auto pcm = speaker_.decode(seat, packet);
  if (!pcm && std::has_single_bit(++speaker_failures_)) {
    log_.warning(std::format(
        "controller speaker packet rejected: seat={} bytes={} rejected={}",
        seat, packet.size(), speaker_failures_.load()));
  }
  return pcm;
}

void AudioPath::hold_speaker(std::uint8_t seat,
                             std::span<const std::int16_t> pcm) {
  if (!decoder_ ||
      decoder_->sample_rate() != ControllerSpeakerMix::sample_rate) {
    return;
  }
  speaker_.hold(seat, pcm);
}

auto AudioPath::with_side_audio(std::span<const std::int16_t> pcm,
                                std::size_t channels)
    -> std::span<const std::int16_t> {
  if ((voice_.empty() && speaker_.pending() == 0) || channels == 0) {
    return pcm;
  }
  mixed_.assign(pcm.begin(), pcm.end());
  const auto targets = std::min(channels, voice_target_channels);
  constexpr int lowest = std::numeric_limits<std::int16_t>::min();
  constexpr int highest = std::numeric_limits<std::int16_t>::max();
  const auto gain = voice_gain_.load(std::memory_order_relaxed);
  for (std::size_t frame = 0;
       frame < mixed_.size() / channels && !voice_.empty(); ++frame) {
    const int sample = static_cast<int>(voice_.front() * gain);
    voice_.pop_front();
    for (std::size_t channel = 0; channel < targets; ++channel) {
      auto& out = mixed_[frame * channels + channel];
      out =
          static_cast<std::int16_t>(std::clamp(out + sample, lowest, highest));
    }
  }
  speaker_.mix(mixed_, channels);
  return mixed_;
}

void AudioPath::observe_activity(std::span<const std::int16_t> pcm,
                                 std::size_t channels) noexcept {
  if (channels == 0 || channels > 32) {
    return;
  }
  for (std::size_t index = 0; index < pcm.size(); ++index) {
    if (pcm[index] != 0) {
      activity_mask_ |= 1U << (index % channels);
    }
  }
  activity_frames_ += pcm.size() / channels;
  if (activity_frames_ < activity_window_frames) {
    return;
  }
  active_channels_ = static_cast<std::uint32_t>(std::popcount(activity_mask_));
  activity_mask_ = 0;
  activity_frames_ = 0;
}

void AudioPath::stop() {
  decoder_.reset();
  voice_decoder_.reset();
  voice_.clear();
  speaker_.reset();
  channels_ = 0;
  active_channels_ = 0;
  nx_audio_stop(output_.get());
}

void AudioPath::set_voice_gain(float gain) noexcept {
  voice_gain_.store(std::clamp(gain, 0.0F, 1.0F), std::memory_order_relaxed);
}

void AudioPath::set_gain(float gain) noexcept {
  nx_audio_set_gain(output_.get(), gain);
}

void AudioPath::set_buffer(std::uint32_t milliseconds) noexcept {
  nx_audio_set_buffer_ms(output_.get(), milliseconds);
}

void AudioPath::set_output(std::string_view name) {
  const std::string device{name};
  nx_audio_set_output_device(output_.get(), device.c_str());
}

void AudioPath::set_spatial(bool enabled) noexcept {
  nx_audio_set_spatial(output_.get(), enabled);
}

auto AudioPath::state_of(nx_audio_state state) noexcept -> AudioOutputState {
  switch (state) {
    case NX_AUDIO_CREATED:
      return AudioOutputState::created;
    case NX_AUDIO_CONFIGURED:
      return AudioOutputState::configured;
    case NX_AUDIO_PRIMING:
      return AudioOutputState::priming;
    case NX_AUDIO_PLAYING:
      return AudioOutputState::playing;
    case NX_AUDIO_STOPPING:
      return AudioOutputState::stopping;
    case NX_AUDIO_STOPPED:
      return AudioOutputState::stopped;
    case NX_AUDIO_FAILED:
      break;
  }
  return AudioOutputState::failed;
}

auto AudioPath::statistics() const noexcept -> AudioStatistics {
  nx_audio_stats output{};
  nx_audio_get_stats(output_.get(), &output);
  const auto received = received_format_.load();
  return {
      .pcm_frames = output.pcm_frames,
      .pcm_bytes = output.pcm_bytes,
      .underruns = output.underruns,
      .silent_frames = output.silent_frames,
      .overflows = output.overflows,
      .dropped_frames = output.dropped_frames,
      .trims = output.trims,
      .trimmed_frames = output.trimmed_frames,
      .buffered_frames = output.buffered_frames,
      .maximum_buffered_frames = output.maximum_buffered_frames,
      .channels = output.channels,
      .sample_rate = output.sample_rate,
      .received_channels = static_cast<std::uint32_t>(received),
      .received_sample_rate = static_cast<std::uint32_t>(received >> 32),
      .received_active_channels = active_channels_.load(),
      .state = state_of(output.state),
      .device_failures =
          static_cast<std::uint32_t>(std::max(output.device_failures, 0)),
      .decode_failures = failures_,
      .concealment_frames = concealed_,
      .last_decode_error = last_error_,
  };
}

}  // namespace chiaki_bridge
