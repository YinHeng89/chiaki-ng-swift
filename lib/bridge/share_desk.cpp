#include "share_desk.hpp"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>
#include <type_traits>
#include <utility>

#include "account_ids.hpp"
#include "boundary.hpp"
#include "opened.hpp"
#include "stream_session.hpp"

namespace chiaki_bridge {

namespace kakusan = libchiaking::kakusan;

ShareDesk::ShareDesk(StreamSession& stream, StreamListener& listener,
                     FeedbackPath& feedback)
    : stream_(stream), relay_(listener, feedback) {}

auto ShareDesk::root() -> std::shared_ptr<Root> {
  const auto core = Opened::shared();
  if (!core) {
    return nullptr;
  }
  return core->kakusan();
}

auto ShareDesk::refused(kakusan::Refusal::Kind kind) -> Outcome {
  return Outcome::declined(kind);
}

auto ShareDesk::refused(KakusanCommandRefusal refusal) -> Outcome {
  return Outcome::refused(refusal);
}

auto ShareDesk::guest_of(const Bytes& bytes)
    -> std::optional<kakusan::GuestId> {
  kakusan::GuestId::Bytes id{};
  if (bytes.size() != id.size()) {
    return std::nullopt;
  }
  std::ranges::transform(bytes, id.begin(),
                         [](std::uint8_t byte) { return std::byte{byte}; });
  return kakusan::GuestId{id};
}

template <class Value>
auto ShareDesk::outcome_of(
    const libchiaking::Expected<Value, kakusan::Refusal>& result) -> Outcome {
  if (!result) {
    return refused(result.error().kind());
  }
  if constexpr (std::is_same_v<Value, kakusan::GuestId>) {
    return Outcome::accepted(IdentifierBytes::of(result.value()));
  } else {
    return Outcome::accepted({});
  }
}

auto ShareDesk::sharing() const -> std::shared_ptr<kakusan::SharedSession> {
  const std::lock_guard lock(mutex_);
  return sharing_;
}

auto ShareDesk::visit() const noexcept -> kakusan::GuestVisit* {
  return visit_.load();
}

template <class Call>
auto ShareDesk::with_share(Call&& call) -> Outcome {
  bool armed = false;
  {
    const std::lock_guard lock(mutex_);
    armed = rules_.has_value();
  }
  const auto shared = sharing();
  if (!shared) {
    return armed ? refused(kakusan::Refusal::Kind::not_sharing)
                 : refused(KakusanCommandRefusal::not_armed);
  }
  return Boundary::fenced(refused(kakusan::Refusal::Kind::internal),
                          [&] { return std::forward<Call>(call)(*shared); });
}

auto ShareDesk::arm_host(const KakusanHosting& hosting) -> Outcome {
  const auto rules =
      kakusan::SharingRules::create(hosting.capacity, hosting.local_seats);
  if (!rules) {
    return refused(kakusan::Refusal::Kind::invalid_argument);
  }
  auto shared = roots_();
  if (!shared) {
    return refused(KakusanCommandRefusal::core_closed);
  }
  shared->use_port_guessing(guessing_of(hosting.force_port_guessing));
  const std::lock_guard lock(mutex_);
  if (sharing_ || visit_.load() != nullptr) {
    return refused(kakusan::Refusal::Kind::busy);
  }
  root_ = std::move(shared);
  rules_ = *rules;
  return Outcome::accepted({});
}

void ShareDesk::share_when_playing(libchiaking::play::Session& session) {
  std::shared_ptr<Root> shared;
  std::optional<kakusan::SharingRules> rules;
  {
    const std::lock_guard lock(mutex_);
    shared = root_;
    rules = rules_;
  }
  if (!shared || !rules) {
    return;
  }
  while (session.state() != libchiaking::play::SessionState::playing) {
    if (session.outcome()) {
      return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds{5});
  }
  auto begun = shared->share(session.share(), *rules, relay_);
  if (!begun) {
    stream_.log().warning(std::string{"the session could not be shared: "} +
                          std::string{begun.error().name()});
    relay_.failed(begun.error().kind());
    return;
  }
  const std::lock_guard lock(mutex_);
  sharing_ = std::move(begun.value());
}

void ShareDesk::stop_sharing() {
  std::shared_ptr<kakusan::SharedSession> shared;
  {
    const std::lock_guard lock(mutex_);
    shared = std::move(sharing_);
    sharing_.reset();
  }
  if (shared) {
    shared->stop_sharing();
  }
}

auto ShareDesk::guest_refused(kakusan::Refusal::Kind refused,
                              std::string_view name) -> GuestOutcome {
  stream_.log().warning(
      std::string{"the shared session could not be joined: "} +
      std::string{name});
  relay_.unavailable(refused);
  stream_.end_visit();
  return GuestOutcome::ended(GuestEndFacts{
      kakusan::VisitOutcome::Status::visit_failed, refused, std::nullopt, {}});
}

auto ShareDesk::guest_unavailable() -> GuestOutcome {
  stream_.log().warning("the shared session could not be joined: UNAVAILABLE");
  relay_.unavailable(KakusanCommandRefusal::core_closed);
  stream_.end_visit();
  return GuestOutcome::refused(StreamRefusal::core_closed);
}

auto ShareDesk::run_guest(std::string_view invitation, bool force_port_guessing)
    -> GuestOutcome {
  if (invitation.empty() ||
      invitation.size() > kakusan::Invitation::most_text) {
    return GuestOutcome::declined(kakusan::Refusal::Kind::invalid_argument);
  }
  if (!stream_.unclaimed()) {
    return GuestOutcome::ended(
        GuestEndFacts{kakusan::VisitOutcome::Status::cancelled,
                      std::nullopt,
                      std::nullopt,
                      {}});
  }
  if (!stream_.decodes_video()) {
    stream_.end_visit();
    return GuestOutcome::refused(StreamRefusal::no_decoder);
  }
  const auto shared = roots_();
  if (!shared) {
    return guest_unavailable();
  }
  shared->use_port_guessing(guessing_of(force_port_guessing));
  auto read = shared->read(invitation);
  if (!read) {
    return guest_refused(read.error().kind(), read.error().name());
  }
  auto joined =
      shared->join(std::move(read.value()), {relay_, stream_.media()});
  if (!joined) {
    return guest_refused(joined.error().kind(), joined.error().name());
  }
  {
    const std::lock_guard lock(mutex_);
    root_ = shared;
    owned_visit_ = std::move(joined.value());
  }
  auto& visiting = *owned_visit_;
  visit_ = &visiting;
  if (!stream_.begin_visit()) {
    visiting.cancel();
  }
  const auto ended = visiting.run();
  visit_ = nullptr;
  stream_.end_visit();
  GuestEndFacts end{ended.status(), std::nullopt, std::nullopt,
                    std::string{ended.message()}};
  if (const auto refusal = ended.refusal()) {
    end.refused = refusal->kind();
  }
  if (const auto& fault = ended.media_fault()) {
    end.media_failure = fault->kind;
  }
  return GuestOutcome::ended(std::move(end));
}

auto ShareDesk::host_invite() -> Outcome {
  return with_share([](kakusan::SharedSession& share) {
    return outcome_of(share.invite_player());
  });
}

auto ShareDesk::host_import_reply(std::string_view text) -> Outcome {
  if (text.empty() || text.size() > kakusan::Invitation::most_text) {
    return refused(kakusan::Refusal::Kind::invalid_argument);
  }
  return with_share([&](kakusan::SharedSession& share) {
    return outcome_of(share.accept_reply(text));
  });
}

auto ShareDesk::host_enter_code(const Bytes& guest, std::string_view code)
    -> Outcome {
  const auto digits = kakusan::VerificationCode::parse(code);
  const auto id = guest_of(guest);
  if (!digits || !id) {
    return refused(kakusan::Refusal::Kind::invalid_argument);
  }
  return with_share([&](kakusan::SharedSession& share) {
    return outcome_of(share.verify(*id, *digits));
  });
}

auto ShareDesk::seating_of(std::uint8_t pad,
                           libchiaking::controllers::ControllerKind controller,
                           const Bytes& account_id)
    -> std::optional<kakusan::GuestSeating> {
  kakusan::GuestSeating seating;
  seating.controller = controller;
  if (pad != 0) {
    seating.preferred = libchiaking::controllers::SeatNumber::create(pad);
    if (!seating.preferred) {
      return std::nullopt;
    }
  }
  if (!account_id.empty()) {
    seating.as = AccountIds::account_of(account_id);
    if (!seating.as) {
      return std::nullopt;
    }
  }
  return seating;
}

auto ShareDesk::host_give_seat(
    const Bytes& guest, std::uint8_t pad,
    libchiaking::controllers::ControllerKind controller,
    const Bytes& account_id) -> Outcome {
  const auto seating = seating_of(pad, controller, account_id);
  const auto id = guest_of(guest);
  if (!seating || !id) {
    return refused(kakusan::Refusal::Kind::invalid_argument);
  }
  return with_share([&](kakusan::SharedSession& share) {
    return outcome_of(share.give_seat(*id, *seating));
  });
}

auto ShareDesk::host_remove(const Bytes& guest) -> Outcome {
  const auto id = guest_of(guest);
  if (!id) {
    return refused(kakusan::Refusal::Kind::invalid_argument);
  }
  return with_share([&](kakusan::SharedSession& share) {
    return outcome_of(share.take_back_seat(*id));
  });
}

auto ShareDesk::change(std::optional<std::uint8_t> capacity,
                       std::optional<std::uint8_t> local_seats) -> Outcome {
  std::optional<kakusan::SharingRules> rules;
  {
    const std::lock_guard lock(mutex_);
    if (!rules_) {
      return refused(KakusanCommandRefusal::not_armed);
    }
    rules = kakusan::SharingRules::create(
        capacity.value_or(rules_->capacity()),
        local_seats.value_or(rules_->local_seats()), rules_->allowed_buttons());
  }
  if (!rules) {
    return refused(kakusan::Refusal::Kind::invalid_argument);
  }
  auto outcome = with_share([&](kakusan::SharedSession& share) {
    return outcome_of(share.change(*rules));
  });
  const bool waiting = outcome.kind() == Outcome::Kind::declined &&
                       outcome.decline() == kakusan::Refusal::Kind::not_sharing;
  if (waiting || outcome.kind() == Outcome::Kind::accepted) {
    const std::lock_guard lock(mutex_);
    rules_ = rules;
  }
  return waiting ? Outcome::accepted({}) : outcome;
}

auto ShareDesk::host_set_local_seats(std::uint8_t local_seats) -> Outcome {
  return change(std::nullopt, local_seats);
}

auto ShareDesk::host_set_capacity(std::uint8_t capacity) -> Outcome {
  return change(capacity, std::nullopt);
}

auto ShareDesk::host_set_tuning(const kakusan::Tuning& tuning) -> Outcome {
  return with_share([&](kakusan::SharedSession& share) {
    return outcome_of(share.tune(tuning));
  });
}

auto ShareDesk::not_known(kakusan::RememberRefusal::Kind kind)
    -> RememberOutcome {
  return RememberOutcome::declined(RememberDeclineFacts{kind, std::nullopt});
}

auto ShareDesk::remember(const Bytes& identity, std::string_view nickname,
                         bool replace) -> RememberOutcome {
  using Kind = kakusan::RememberRefusal::Kind;
  const auto key = KakusanDevices::key_of(identity);
  if (!key) {
    return not_known(Kind::unknown_device);
  }
  const auto replacing = replace ? kakusan::Replace::yes : kakusan::Replace::no;
  return Boundary::fenced(not_known(Kind::store_unavailable), [&] {
    if (auto* visiting = visit_.load()) {
      if (visiting->host_key() != *key) {
        return not_known(Kind::unknown_device);
      }
      return KakusanDevices::outcome_of(
          visiting->remember_host(nickname, replacing));
    }
    const auto shared = sharing();
    if (!shared) {
      return not_known(Kind::unknown_device);
    }
    const auto players = shared->players();
    const auto held = std::ranges::find_if(
        players, [&](const kakusan::PlayerSummary& player) {
          return player.device == *key;
        });
    if (held == players.end()) {
      return not_known(Kind::unknown_device);
    }
    return KakusanDevices::outcome_of(
        shared->remember(held->guest, nickname, replacing));
  });
}

auto ShareDesk::guest_enter_code(std::string_view code) -> Outcome {
  const auto digits = kakusan::VerificationCode::parse(code);
  if (!digits) {
    return refused(kakusan::Refusal::Kind::invalid_argument);
  }
  auto* visiting = visit_.load();
  if (visiting == nullptr) {
    return refused(kakusan::Refusal::Kind::not_visiting);
  }
  return Boundary::fenced(refused(kakusan::Refusal::Kind::internal), [&] {
    return outcome_of(visiting->verify(*digits));
  });
}

auto ShareDesk::guest_leave() -> Outcome {
  auto* visiting = visit_.load();
  if (visiting == nullptr) {
    return refused(kakusan::Refusal::Kind::not_visiting);
  }
  return Boundary::fenced(refused(kakusan::Refusal::Kind::internal),
                          [&] { return outcome_of(visiting->leave()); });
}

}  // namespace chiaki_bridge
