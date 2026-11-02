#pragma once

#include <cstdint>
#include <libchiaking/chiaki_ng.hpp>
#include <libchiaking/kakusan.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

enum class KakusanRefusal : std::uint8_t {
  core_closed,
  invalid_identity,
  invalid_text,
};

using KakusanUnavailable = libchiaking::kakusan::Kakusan::Unavailable;

struct DeviceFacts {
  Bytes identity;
  Bytes fingerprint;
  std::string nickname;
  std::int64_t first_verified_ms;
  std::int64_t last_seen_ms;
};

using DeviceList = std::vector<DeviceFacts>;
using DeviceFound = std::optional<DeviceFacts>;
using NicknameFound = std::optional<std::string>;

/// This installation's Kakusan identity.
struct ThisDeviceFacts {
  /// The identity key.
  Bytes identity;
  /// The key's fingerprint.
  Bytes fingerprint;
};

/// How reading this installation's identity ended: identified, unavailable
/// or refused.
class ThisDeviceOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// The core derived the identity.
    identified,
    /// Kakusan is unavailable in the core.
    unavailable,
    /// The bridge refused before the core ran.
    refused,
  };

  /// An identity the core derived.
  static auto identified(ThisDeviceFacts value) -> ThisDeviceOutcome {
    return ThisDeviceOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::identified)>,
             std::move(value)}};
  }

  /// A read Kakusan was unavailable for.
  static auto unavailable(KakusanUnavailable value) -> ThisDeviceOutcome {
    return ThisDeviceOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unavailable)>,
             std::move(value)}};
  }

  /// A read the bridge refused.
  static auto refused(KakusanRefusal value) -> ThisDeviceOutcome {
    return ThisDeviceOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The identity; valid for `identified`.
  auto device() const -> ThisDeviceFacts {
    return std::get<std::to_underlying(Kind::identified)>(held_);
  }

  /// Why Kakusan is unavailable; valid for `unavailable`.
  auto why_unavailable() const -> KakusanUnavailable {
    return std::get<std::to_underlying(Kind::unavailable)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> KakusanRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<ThisDeviceFacts, KakusanUnavailable, KakusanRefusal>;

  explicit ThisDeviceOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How listing the remembered devices ended: listed, unavailable or refused.
class RememberedOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// The core listed the devices.
    listed,
    /// Kakusan is unavailable in the core.
    unavailable,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Devices the core listed.
  static auto listed(DeviceList value) -> RememberedOutcome {
    return RememberedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::listed)>,
             std::move(value)}};
  }

  /// A listing Kakusan was unavailable for.
  static auto unavailable(KakusanUnavailable value) -> RememberedOutcome {
    return RememberedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unavailable)>,
             std::move(value)}};
  }

  /// A listing the bridge refused.
  static auto refused(KakusanRefusal value) -> RememberedOutcome {
    return RememberedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The devices; valid for `listed`.
  auto devices() const -> DeviceList {
    return std::get<std::to_underlying(Kind::listed)>(held_);
  }

  /// Why Kakusan is unavailable; valid for `unavailable`.
  auto why_unavailable() const -> KakusanUnavailable {
    return std::get<std::to_underlying(Kind::unavailable)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> KakusanRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<DeviceList, KakusanUnavailable, KakusanRefusal>;

  explicit RememberedOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

struct RecognitionFacts {
  libchiaking::kakusan::Recognition::Kind kind;
  DeviceFound device;
};

/// Why the core declined to remember or rename a device.
struct RememberDeclineFacts {
  /// The core's reason.
  libchiaking::kakusan::RememberRefusal::Kind kind;
  /// The device already holding the nickname, when that is the reason.
  DeviceFound holder;
};

/// How remembering or renaming a device ended: remembered, declined by the
/// core, unavailable or refused.
class RememberOutcome {
 public:
  /// The ways the change can end.
  enum class Kind : std::uint8_t {
    /// The core saved the device.
    remembered,
    /// The core declined the change.
    declined,
    /// Kakusan is unavailable in the core.
    unavailable,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A device the core saved.
  static auto remembered(DeviceFacts value) -> RememberOutcome {
    return RememberOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::remembered)>,
             std::move(value)}};
  }

  /// A change the core declined.
  static auto declined(RememberDeclineFacts value) -> RememberOutcome {
    return RememberOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::declined)>,
             std::move(value)}};
  }

  /// A change Kakusan was unavailable for.
  static auto unavailable(KakusanUnavailable value) -> RememberOutcome {
    return RememberOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unavailable)>,
             std::move(value)}};
  }

  /// A change the bridge refused.
  static auto refused(KakusanRefusal value) -> RememberOutcome {
    return RememberOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the change ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The saved device; valid for `remembered`.
  auto device() const -> DeviceFacts {
    return std::get<std::to_underlying(Kind::remembered)>(held_);
  }

  /// Why the core declined; valid for `declined`.
  auto decline() const -> RememberDeclineFacts {
    return std::get<std::to_underlying(Kind::declined)>(held_);
  }

  /// Why Kakusan is unavailable; valid for `unavailable`.
  auto why_unavailable() const -> KakusanUnavailable {
    return std::get<std::to_underlying(Kind::unavailable)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> KakusanRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<DeviceFacts, RememberDeclineFacts,
                            KakusanUnavailable, KakusanRefusal>;

  explicit RememberOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

struct InvitationFacts {
  Bytes host_hint;
  std::uint8_t capacity;
  std::uint64_t expires_at;
  std::uint8_t stream_protocol;
  RecognitionFacts recognition;
};

/// How reading an invitation ended: read, declined by the core,
/// unavailable or refused.
class PreviewOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// The core read the invitation.
    read,
    /// The core refused the invitation.
    declined,
    /// Kakusan is unavailable in the core.
    unavailable,
    /// The bridge refused before the core ran.
    refused,
  };

  /// An invitation the core read.
  static auto read(InvitationFacts value) -> PreviewOutcome {
    return PreviewOutcome{Case{
        std::in_place_index<std::to_underlying(Kind::read)>, std::move(value)}};
  }

  /// An invitation the core refused.
  static auto declined(libchiaking::kakusan::Refusal::Kind value)
      -> PreviewOutcome {
    return PreviewOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::declined)>,
             std::move(value)}};
  }

  /// A read Kakusan was unavailable for.
  static auto unavailable(KakusanUnavailable value) -> PreviewOutcome {
    return PreviewOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unavailable)>,
             std::move(value)}};
  }

  /// A read the bridge refused.
  static auto refused(KakusanRefusal value) -> PreviewOutcome {
    return PreviewOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The invitation; valid for `read`.
  auto invitation() const -> InvitationFacts {
    return std::get<std::to_underlying(Kind::read)>(held_);
  }

  /// Why the core refused; valid for `declined`.
  auto decline() const -> libchiaking::kakusan::Refusal::Kind {
    return std::get<std::to_underlying(Kind::declined)>(held_);
  }

  /// Why Kakusan is unavailable; valid for `unavailable`.
  auto why_unavailable() const -> KakusanUnavailable {
    return std::get<std::to_underlying(Kind::unavailable)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> KakusanRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<InvitationFacts, libchiaking::kakusan::Refusal::Kind,
                   KakusanUnavailable, KakusanRefusal>;

  explicit PreviewOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How replacing the STUN servers ended: used, unavailable or refused.
class StunServersOutcome {
 public:
  /// The ways the change can end.
  enum class Kind : std::uint8_t {
    /// The core uses the servers.
    used,
    /// Kakusan is unavailable in the core.
    unavailable,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Servers the core now uses.
  static auto used() -> StunServersOutcome {
    return StunServersOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::used)>}};
  }

  /// A change Kakusan was unavailable for.
  static auto unavailable(KakusanUnavailable value) -> StunServersOutcome {
    return StunServersOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unavailable)>,
             std::move(value)}};
  }

  /// A change the bridge refused.
  static auto refused(KakusanRefusal value) -> StunServersOutcome {
    return StunServersOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the change ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// Why Kakusan is unavailable; valid for `unavailable`.
  auto why_unavailable() const -> KakusanUnavailable {
    return std::get<std::to_underlying(Kind::unavailable)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> KakusanRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<std::monostate, KakusanUnavailable, KakusanRefusal>;

  explicit StunServersOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class KakusanDevices {
 public:
  using Remembered =
      libchiaking::Expected<libchiaking::kakusan::RememberedDevice,
                            libchiaking::kakusan::RememberRefusal>;

  static auto use_stun_servers(const Texts& servers) -> StunServersOutcome;
  static auto preview_invitation(const std::string& text) -> PreviewOutcome;
  static auto this_device() -> ThisDeviceOutcome;
  static auto remembered() -> RememberedOutcome;
  static auto recognise(const Bytes& identity) -> RecognitionFacts;
  static auto recognise(const Bytes& identity,
                        const std::string& expected_nickname)
      -> RecognitionFacts;
  static auto rename(const Bytes& identity, const std::string& nickname)
      -> RememberOutcome;
  static auto forget(const Bytes& identity) -> bool;
  static auto normalised_nickname(const std::string& typed) -> NicknameFound;

  static auto use_stun_servers_of(libchiaking::ChiakiNg& core,
                                  const Texts& servers) -> StunServersOutcome;
  static auto preview_invitation_of(libchiaking::ChiakiNg& core,
                                    const std::string& text) -> PreviewOutcome;
  static auto this_device_of(libchiaking::ChiakiNg& core) -> ThisDeviceOutcome;
  static auto remembered_of(libchiaking::ChiakiNg& core) -> RememberedOutcome;
  static auto recognise_of(libchiaking::ChiakiNg& core, const Bytes& identity,
                           std::optional<std::string_view> expected_nickname)
      -> RecognitionFacts;
  static auto rename_of(libchiaking::ChiakiNg& core, const Bytes& identity,
                        const std::string& nickname) -> RememberOutcome;
  static auto forget_of(libchiaking::ChiakiNg& core, const Bytes& identity)
      -> bool;

  static auto facts_of(const libchiaking::kakusan::RememberedDevice& device)
      -> DeviceFacts;
  static auto facts_of(const libchiaking::kakusan::Recognition& recognition)
      -> RecognitionFacts;
  static auto outcome_of(const Remembered& remembered) -> RememberOutcome;
  static auto key_of(const Bytes& identity)
      -> std::optional<libchiaking::kakusan::IdentityKey>;

 private:
  template <class Outcome, class Call>
  static auto opened(Outcome closed, Call&& call) -> Outcome;
};

}  // namespace chiaki_bridge
