#include <algorithm>
#include <cstring>
#include <iterator>
#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/kakusan.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::ChiakiNg;
using libchiaking::kakusan::IdentityKey;
using libchiaking::kakusan::Recognition;
using libchiaking::kakusan::RememberedDevice;
using libchiaking::kakusan::RememberedDevices;

template <class Outcome, class Call>
auto KakusanDevices::opened(Outcome closed, Call&& call) -> Outcome {
  return Boundary::fenced(closed, [&]() -> Outcome {
    const auto core = Opened::shared();
    if (!core) {
      return closed;
    }
    return std::forward<Call>(call)(core->chiaki());
  });
}

auto KakusanDevices::key_of(const Bytes& identity)
    -> std::optional<IdentityKey> {
  if (identity.size() != IdentityKey::size) {
    return std::nullopt;
  }
  IdentityKey::Bytes bytes{};
  std::ranges::transform(identity, bytes.begin(),
                         [](std::uint8_t value) { return std::byte{value}; });
  return IdentityKey{bytes};
}

auto KakusanDevices::facts_of(const RememberedDevice& device) -> DeviceFacts {
  return {
      .identity = IdentifierBytes::of(device.key),
      .fingerprint = IdentifierBytes::of(device.fingerprint),
      .nickname = device.nickname,
      .first_verified_ms = Timestamp::milliseconds_of(device.first_verified),
      .last_seen_ms = Timestamp::milliseconds_of(device.last_seen)};
}

auto KakusanDevices::facts_of(const Recognition& recognition)
    -> RecognitionFacts {
  RecognitionFacts facts{.kind = recognition.kind, .device = std::nullopt};
  if (recognition.device) {
    facts.device = facts_of(*recognition.device);
  }
  return facts;
}

auto KakusanDevices::outcome_of(const Remembered& remembered)
    -> RememberOutcome {
  if (remembered) {
    return RememberOutcome::remembered(facts_of(remembered.value()));
  }
  RememberDeclineFacts decline{remembered.error().kind, std::nullopt};
  if (remembered.error().holder) {
    decline.holder = facts_of(*remembered.error().holder);
  }
  return RememberOutcome::declined(std::move(decline));
}

auto KakusanDevices::use_stun_servers_of(ChiakiNg& core, const Texts& servers)
    -> StunServersOutcome {
  const auto used = core.use_stun_servers(servers);
  if (!used) {
    return StunServersOutcome::unavailable(used.error());
  }
  return StunServersOutcome::used();
}

auto KakusanDevices::preview_invitation_of(ChiakiNg& core,
                                           const std::string& text)
    -> PreviewOutcome {
  if (text.empty()) {
    return PreviewOutcome::refused(KakusanRefusal::invalid_text);
  }
  const auto shared = core.kakusan();
  if (!shared) {
    return PreviewOutcome::unavailable(shared.error());
  }
  const auto invitation = shared.value().read(text);
  if (!invitation) {
    return PreviewOutcome::declined(invitation.error().kind());
  }
  const auto& summary = invitation.value().summary();
  return PreviewOutcome::read(
      InvitationFacts{.host_hint = IdentifierBytes::of(summary.host_hint),
                      .capacity = summary.seats.capacity,
                      .expires_at = summary.expires_at,
                      .stream_protocol = summary.stream_protocol,
                      .recognition = facts_of(summary.recognition)});
}

auto KakusanDevices::this_device_of(ChiakiNg& core) -> ThisDeviceOutcome {
  const auto shared = core.kakusan();
  if (!shared) {
    return ThisDeviceOutcome::unavailable(shared.error());
  }
  const auto& device = shared.value().this_device();
  return ThisDeviceOutcome::identified(
      ThisDeviceFacts{IdentifierBytes::of(device.key()),
                      IdentifierBytes::of(device.fingerprint())});
}

auto KakusanDevices::remembered_of(ChiakiNg& core) -> RememberedOutcome {
  auto shared = core.kakusan();
  if (!shared) {
    return RememberedOutcome::unavailable(shared.error());
  }
  const auto devices = shared.value().remembered().all();
  DeviceList listed;
  listed.reserve(devices.size());
  std::ranges::transform(
      devices, std::back_inserter(listed),
      [](const RememberedDevice& device) { return facts_of(device); });
  return RememberedOutcome::listed(std::move(listed));
}

auto KakusanDevices::recognise_of(
    ChiakiNg& core, const Bytes& identity,
    std::optional<std::string_view> expected_nickname) -> RecognitionFacts {
  const RecognitionFacts unknown{.kind = Recognition::Kind::unknown,
                                 .device = std::nullopt};
  const auto key = key_of(identity);
  if (!key) {
    return unknown;
  }
  auto shared = core.kakusan();
  if (!shared) {
    return unknown;
  }
  return facts_of(
      shared.value().remembered().recognise(*key, expected_nickname));
}

auto KakusanDevices::rename_of(ChiakiNg& core, const Bytes& identity,
                               const std::string& nickname) -> RememberOutcome {
  const auto key = key_of(identity);
  if (!key) {
    return RememberOutcome::refused(KakusanRefusal::invalid_identity);
  }
  auto shared = core.kakusan();
  if (!shared) {
    return RememberOutcome::unavailable(shared.error());
  }
  return outcome_of(shared.value().remembered().rename(*key, nickname));
}

auto KakusanDevices::forget_of(ChiakiNg& core, const Bytes& identity) -> bool {
  const auto key = key_of(identity);
  if (!key) {
    return false;
  }
  auto shared = core.kakusan();
  return shared && shared.value().remembered().forget(*key).has_value();
}

auto KakusanDevices::use_stun_servers(const Texts& servers)
    -> StunServersOutcome {
  return opened(
      StunServersOutcome::refused(KakusanRefusal::core_closed),
      [&](ChiakiNg& core) { return use_stun_servers_of(core, servers); });
}

auto KakusanDevices::preview_invitation(const std::string& text)
    -> PreviewOutcome {
  return opened(
      PreviewOutcome::refused(KakusanRefusal::core_closed),
      [&](ChiakiNg& core) { return preview_invitation_of(core, text); });
}

auto KakusanDevices::this_device() -> ThisDeviceOutcome {
  return opened(ThisDeviceOutcome::refused(KakusanRefusal::core_closed),
                [](ChiakiNg& core) { return this_device_of(core); });
}

auto KakusanDevices::remembered() -> RememberedOutcome {
  return opened(RememberedOutcome::refused(KakusanRefusal::core_closed),
                [](ChiakiNg& core) { return remembered_of(core); });
}

auto KakusanDevices::recognise(const Bytes& identity) -> RecognitionFacts {
  const RecognitionFacts unknown{.kind = Recognition::Kind::unknown,
                                 .device = std::nullopt};
  return opened(unknown, [&](ChiakiNg& core) {
    return recognise_of(core, identity, std::nullopt);
  });
}

auto KakusanDevices::recognise(const Bytes& identity,
                               const std::string& expected_nickname)
    -> RecognitionFacts {
  const RecognitionFacts unknown{.kind = Recognition::Kind::unknown,
                                 .device = std::nullopt};
  return opened(unknown, [&](ChiakiNg& core) {
    return recognise_of(core, identity, expected_nickname);
  });
}

auto KakusanDevices::rename(const Bytes& identity, const std::string& nickname)
    -> RememberOutcome {
  return opened(
      RememberOutcome::refused(KakusanRefusal::core_closed),
      [&](ChiakiNg& core) { return rename_of(core, identity, nickname); });
}

auto KakusanDevices::forget(const Bytes& identity) -> bool {
  return opened(false,
                [&](ChiakiNg& core) { return forget_of(core, identity); });
}

auto KakusanDevices::normalised_nickname(const std::string& typed)
    -> NicknameFound {
  return Boundary::fenced(NicknameFound{},
                          [&] { return RememberedDevices::normalised(typed); });
}

}  // namespace chiaki_bridge
