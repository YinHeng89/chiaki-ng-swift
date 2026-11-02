#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <libchiaking/kakusan.hpp>
#include <memory>
#include <mutex>
#include <optional>
#include <string_view>

#include "chiaki_bridge/stream.hpp"
#include "share_relay.hpp"

namespace chiaki_bridge {

class StreamSession;

class ShareDesk {
 public:
  using Root = libchiaking::kakusan::Kakusan;
  using Outcome = KakusanCommandOutcome;

  ShareDesk(StreamSession& stream, StreamListener& listener,
            FeedbackPath& feedback);
  ShareDesk(const ShareDesk&) = delete;
  auto operator=(const ShareDesk&) -> ShareDesk& = delete;

  static auto root() -> std::shared_ptr<Root>;
  static auto refused(libchiaking::kakusan::Refusal::Kind kind) -> Outcome;
  static auto refused(KakusanCommandRefusal refusal) -> Outcome;
  static auto guest_of(const Bytes& bytes)
      -> std::optional<libchiaking::kakusan::GuestId>;
  static auto seating_of(std::uint8_t pad,
                         libchiaking::controllers::ControllerKind controller,
                         const Bytes& account_id)
      -> std::optional<libchiaking::kakusan::GuestSeating>;
  template <class Value>
  static auto outcome_of(
      const libchiaking::Expected<Value, libchiaking::kakusan::Refusal>& result)
      -> Outcome;

  auto arm_host(const KakusanHosting& hosting) -> Outcome;
  void share_when_playing(libchiaking::play::Session& session);
  void stop_sharing();
  auto run_guest(std::string_view invitation, bool force_port_guessing)
      -> GuestOutcome;

  auto host_invite() -> Outcome;
  auto host_import_reply(std::string_view text) -> Outcome;
  auto host_enter_code(const Bytes& guest, std::string_view code) -> Outcome;
  auto host_give_seat(const Bytes& guest, std::uint8_t pad,
                      libchiaking::controllers::ControllerKind controller,
                      const Bytes& account_id) -> Outcome;
  auto host_remove(const Bytes& guest) -> Outcome;
  auto host_set_local_seats(std::uint8_t local_seats) -> Outcome;
  auto host_set_capacity(std::uint8_t capacity) -> Outcome;
  auto host_set_tuning(const libchiaking::kakusan::Tuning& tuning) -> Outcome;
  auto remember(const Bytes& identity, std::string_view nickname, bool replace)
      -> RememberOutcome;
  auto guest_enter_code(std::string_view code) -> Outcome;
  auto guest_leave() -> Outcome;
  auto visit() const noexcept -> libchiaking::kakusan::GuestVisit*;

 private:
  friend class StandInShare;

  using Roots = std::function<std::shared_ptr<Root>()>;

  static constexpr auto guessing_of(bool forced) noexcept
      -> Root::PortGuessing {
    return forced ? Root::PortGuessing::forced : Root::PortGuessing::automatic;
  }
  static auto not_known(libchiaking::kakusan::RememberRefusal::Kind kind)
      -> RememberOutcome;

  auto sharing() const -> std::shared_ptr<libchiaking::kakusan::SharedSession>;
  auto guest_refused(libchiaking::kakusan::Refusal::Kind refused,
                     std::string_view name) -> GuestOutcome;
  auto guest_unavailable() -> GuestOutcome;
  template <class Call>
  auto with_share(Call&& call) -> Outcome;
  auto change(std::optional<std::uint8_t> capacity,
              std::optional<std::uint8_t> local_seats) -> Outcome;

  StreamSession& stream_;
  ShareRelay relay_;
  Roots roots_{&ShareDesk::root};
  mutable std::mutex mutex_;
  std::shared_ptr<Root> root_;
  std::optional<libchiaking::kakusan::SharingRules> rules_;
  std::shared_ptr<libchiaking::kakusan::SharedSession> sharing_;
  std::unique_ptr<libchiaking::kakusan::GuestVisit> owned_visit_;
  std::atomic<libchiaking::kakusan::GuestVisit*> visit_{};
};

}  // namespace chiaki_bridge
