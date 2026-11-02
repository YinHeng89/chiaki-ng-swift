#include "share_relay.hpp"

#include <algorithm>
#include <cstddef>
#include <variant>

#include "boundary.hpp"

namespace chiaki_bridge {

namespace kakusan = libchiaking::kakusan;

ShareRelay::ShareRelay(StreamListener& listener,
                       FeedbackPath& feedback) noexcept
    : listener_(listener), feedback_(feedback) {}

auto ShareRelay::blank(Event::Kind kind) -> Event {
  Event event;
  event.kind = kind;
  return event;
}

template <class Change>
void ShareRelay::describe(Event& event, const Change& changed) {
  event.progress = changed.progress;
  if (changed.refusal) {
    event.refused = changed.refusal->kind();
  }
  if (changed.ended) {
    event.ended = changed.ended->kind();
  }
  event.by_peer = changed.by_them;
  event.grant = changed.grant;
}

void ShareRelay::deliver(const Event& event) {
  listener_.on_kakusan(event, {});
}

void ShareRelay::deliver(const Event& event, std::string_view text) {
  if (text.size() > kakusan::Invitation::most_text) {
    deliver(event);
    return;
  }
  listener_.on_kakusan(event, text);
}

void ShareRelay::deliver(const Event& event,
                         const kakusan::VerificationCode& code) {
  listener_.on_kakusan(event, code.digits());
}

void ShareRelay::relay(const Session::InvitationReady& ready) {
  auto event = blank(Event::Kind::invitation_ready);
  event.guest = IdentifierBytes::of(ready.guest);
  event.expires_at = ready.invitation.summary().expires_at;
  deliver(event, ready.invitation.text());
}

void ShareRelay::relay(const Session::PlayerIdentified& identified) {
  auto event = blank(Event::Kind::reply_bound);
  event.guest = IdentifierBytes::of(identified.guest);
  event.identity = IdentifierBytes::of(identified.device);
  event.fingerprint = IdentifierBytes::of(identified.fingerprint);
  event.recognition = KakusanDevices::facts_of(identified.recognition);
  deliver(event);
}

void ShareRelay::relay(const Session::CodeToReadOut& ready) {
  auto event = blank(Event::Kind::code_ready);
  event.guest = IdentifierBytes::of(ready.guest);
  deliver(event, ready.code);
}

void ShareRelay::relay(const Session::PlayerChanged& changed) {
  auto event = blank(Event::Kind::state_changed);
  event.guest = IdentifierBytes::of(changed.player.guest);
  describe(event, changed.player);
  if (changed.player.console_seat) {
    event.pad = changed.player.console_seat->index();
  }
  if (changed.player.reserved_seat) {
    event.reserved_pad = changed.player.reserved_seat->index();
  }
  deliver(event);
}

void ShareRelay::relay(const Session::PlayerSeated& seated) {
  feedback_.reset(seated.seat);
  auto event = blank(Event::Kind::player_seated);
  event.guest = IdentifierBytes::of(seated.guest);
  event.pad = seated.seat.index();
  deliver(event);
}

void ShareRelay::relay(const Session::PlayerUnseated& unseated) {
  feedback_.reset(unseated.seat);
  auto event = blank(Event::Kind::player_unseated);
  event.guest = IdentifierBytes::of(unseated.guest);
  event.pad = unseated.seat.index();
  deliver(event);
}

void ShareRelay::relay(const Session::SeatsChanged& changed) {
  auto event = blank(Event::Kind::seats_changed);
  event.seats = changed.seats;
  deliver(event);
}

void ShareRelay::relay(const Session::StreamShared& shared) {
  auto event = blank(Event::Kind::stream_shared);
  event.video_fps = shared.frames_per_second;
  deliver(event);
}

void ShareRelay::relay(const Session::SharingFailed& failure) {
  failed(failure.refusal.kind());
}

void ShareRelay::relay(const Session::SharingEnded&) {
  deliver(blank(Event::Kind::sharing_ended));
}

void ShareRelay::relay(const Visit::ReplyReady& ready) {
  deliver(blank(Event::Kind::reply_ready), ready.reply.text());
}

void ShareRelay::relay(const Visit::HostIdentified& identified) {
  auto event = blank(Event::Kind::host_identified);
  event.identity = IdentifierBytes::of(identified.key);
  event.fingerprint = IdentifierBytes::of(identified.fingerprint);
  event.recognition = KakusanDevices::facts_of(identified.recognition);
  event.seats = identified.seats;
  deliver(event);
}

void ShareRelay::relay(const Visit::CodeToReadOut& ready) {
  deliver(blank(Event::Kind::code_ready), ready.code);
}

void ShareRelay::relay(const Visit::VisitChanged& changed) {
  auto event = blank(Event::Kind::state_changed);
  describe(event, changed);
  deliver(event);
}

void ShareRelay::relay(const Visit::StreamReady& ready) {
  auto event = blank(Event::Kind::stream_ready);
  event.video_fps = ready.frames_per_second;
  deliver(event);
}

void ShareRelay::relay(const Visit::StreamStopped&) {
  deliver(blank(Event::Kind::stream_stopped));
}

void ShareRelay::relay(const Visit::Connected&) {
  listener_.on_connected(false);
}

void ShareRelay::relay(const Visit::Disconnected&) {
  listener_.on_disconnected(std::nullopt);
}

void ShareRelay::unavailable(kakusan::Refusal::Kind refused) {
  auto event = blank(Event::Kind::unavailable);
  event.refused = refused;
  deliver(event);
}

void ShareRelay::unavailable(KakusanCommandRefusal refusal) {
  auto event = blank(Event::Kind::unavailable);
  event.refusal = refusal;
  deliver(event);
}

void ShareRelay::failed(kakusan::Refusal::Kind refused) {
  auto event = blank(Event::Kind::sharing_failed);
  event.refused = refused;
  deliver(event);
}

void ShareRelay::on_event(Session::Event received) {
  std::visit([this](const auto& value) { relay(value); }, received);
}

void ShareRelay::on_event(Visit::Event received) {
  std::visit([this](const auto& value) { relay(value); }, received);
}

}  // namespace chiaki_bridge
