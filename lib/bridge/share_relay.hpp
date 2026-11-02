#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <libchiaking/kakusan.hpp>
#include <string_view>

#include "chiaki_bridge/stream.hpp"
#include "feedback_path.hpp"

namespace chiaki_bridge {

class ShareRelay final : public libchiaking::kakusan::SharedSession::Observer,
                         public libchiaking::kakusan::GuestVisit::Observer {
 public:
  using Session = libchiaking::kakusan::SharedSession;
  using Visit = libchiaking::kakusan::GuestVisit;
  using Event = KakusanEvent;

  ShareRelay(StreamListener& listener, FeedbackPath& feedback) noexcept;

  static auto blank(Event::Kind kind) -> Event;
  template <class Change>
  static void describe(Event& event, const Change& changed);

  void on_event(Session::Event event) override;
  void on_event(Visit::Event event) override;
  void unavailable(libchiaking::kakusan::Refusal::Kind refused);
  void unavailable(KakusanCommandRefusal refusal);
  void failed(libchiaking::kakusan::Refusal::Kind refused);

 private:
  void relay(const Session::InvitationReady& ready);
  void relay(const Session::PlayerIdentified& identified);
  void relay(const Session::CodeToReadOut& ready);
  void relay(const Session::PlayerChanged& changed);
  void relay(const Session::PlayerSeated& seated);
  void relay(const Session::PlayerUnseated& unseated);
  void relay(const Session::SeatsChanged& changed);
  void relay(const Session::StreamShared& shared);
  void relay(const Session::SharingFailed& failed);
  void relay(const Session::SharingEnded& ended);
  void relay(const Visit::ReplyReady& ready);
  void relay(const Visit::HostIdentified& identified);
  void relay(const Visit::CodeToReadOut& ready);
  void relay(const Visit::VisitChanged& changed);
  void relay(const Visit::StreamReady& ready);
  void relay(const Visit::StreamStopped& stopped);
  void relay(const Visit::Connected& connected);
  void relay(const Visit::Disconnected& disconnected);
  void deliver(const Event& event);
  void deliver(const Event& event, std::string_view text);
  void deliver(const Event& event,
               const libchiaking::kakusan::VerificationCode& code);

  StreamListener& listener_;
  FeedbackPath& feedback_;
};

}  // namespace chiaki_bridge
