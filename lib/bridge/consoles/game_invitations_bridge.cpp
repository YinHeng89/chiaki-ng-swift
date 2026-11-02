#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

auto GameInvitationsBridge::facts_of(
    const libchiaking::consoles::GameInvitation& invitation)
    -> GameInvitationFacts {
  return GameInvitationFacts{
      invitation.session_id,
      invitation.invitation_id,
      Texts{invitation.notification_ids.begin(),
            invitation.notification_ids.end()},
      invitation.inviter,
      invitation.session_name,
      Texts{invitation.title_ids.begin(), invitation.title_ids.end()},
      Timestamp::milliseconds_of(invitation.sent),
      invitation.unread,
      invitation.players,
      invitation.max_players,
      invitation.joining,
      invitation.kind};
}

template <class Join>
auto GameInvitationsBridge::joined_as(const Bytes& account_id, Join&& join)
    -> std::optional<libchiaking::consoles::InvitationJoinFailure> {
  using Failure = libchiaking::consoles::InvitationJoinFailure;
  const std::optional<Failure> closed{Failure{Failure::Reason::unanswered}};
  return Boundary::fenced(closed, [&]() -> std::optional<Failure> {
    const auto opened = Opened::shared();
    if (!opened) {
      return closed;
    }
    const auto user = opened->user(account_id);
    if (!user) {
      return Failure{Failure::Reason::unanswered,
                     libchiaking::users::Unanswered{
                         libchiaking::users::Unanswered::Reason::signed_out}};
    }
    const auto joined = std::forward<Join>(join)(*opened, *user);
    if (!joined) {
      return joined.error();
    }
    return std::nullopt;
  });
}

GameInvitationsBridge::Arrivals::Arrivals(InvitationArrived invitation,
                                          MessageArrived message,
                                          PartyArrived party,
                                          void* context) noexcept
    : invitation_(invitation),
      message_(message),
      party_(party),
      context_(context) {}

void GameInvitationsBridge::Arrivals::on_invitation(
    const libchiaking::consoles::GameInvitation& invitation) {
  if (invitation_ == nullptr) {
    return;
  }
  const auto facts = facts_of(invitation);
  invitation_(&facts, context_);
}

void GameInvitationsBridge::Arrivals::on_message(
    const libchiaking::consoles::MessageAlert& message) {
  if (message_ == nullptr) {
    return;
  }
  const MessageAlertFacts facts{message.sender, message.group_id,
                                message.thread_id};
  message_(&facts, context_);
}

void GameInvitationsBridge::Arrivals::on_party_invitation(
    const libchiaking::consoles::PartyInvitationAlert& party) {
  if (party_ == nullptr) {
    return;
  }
  const PartyAlertFacts facts{party.sender, party.session_id};
  party_(&facts, context_);
}

auto GameInvitationsBridge::dismiss(const Request& request,
                                    const Bytes& account_id,
                                    const Texts& notification_ids)
    -> GameInvitationsOutcome {
  return Boundary::fenced(
      GameInvitationsOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> GameInvitationsOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return GameInvitationsOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return GameInvitationsOutcome::refused(ConsolesRefusal::unknown_user);
        }
        const auto dismissed = opened->consoles().dismiss_invitations(
            *user, notification_ids, request.token());
        if (!dismissed) {
          return GameInvitationsOutcome::unanswered(dismissed.error());
        }
        return GameInvitationsOutcome::answered({});
      });
}

auto GameInvitationsBridge::watch(const Request& request,
                                  const Bytes& account_id,
                                  InvitationArrived invitation,
                                  MessageArrived message, PartyArrived party,
                                  void* context) -> GameInvitationsOutcome {
  return Boundary::fenced(
      GameInvitationsOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> GameInvitationsOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return GameInvitationsOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return GameInvitationsOutcome::refused(ConsolesRefusal::unknown_user);
        }
        Arrivals arrivals{invitation, message, party, context};
        const auto watched =
            opened->consoles().watch_alerts(*user, arrivals, request.token());
        if (!watched) {
          return GameInvitationsOutcome::unanswered(watched.error());
        }
        return GameInvitationsOutcome::answered({});
      });
}

auto GameInvitationsBridge::invitations(const Request& request,
                                        const Bytes& account_id)
    -> GameInvitationsOutcome {
  return Boundary::fenced(
      GameInvitationsOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> GameInvitationsOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return GameInvitationsOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return GameInvitationsOutcome::refused(ConsolesRefusal::unknown_user);
        }
        const auto found =
            opened->consoles().game_invitations(*user, request.token());
        if (!found) {
          return GameInvitationsOutcome::unanswered(found.error());
        }
        GameInvitationList listed;
        for (const auto& invitation : found.value()) {
          listed.push_back(facts_of(invitation));
        }
        return GameInvitationsOutcome::answered(std::move(listed));
      });
}

auto GameInvitationsBridge::join(const Request& request,
                                 const Bytes& account_id,
                                 const std::string& session_id)
    -> std::optional<libchiaking::consoles::InvitationJoinFailure> {
  return joined_as(account_id,
                   [&](Opened& opened, libchiaking::users::PsUser& user) {
                     return opened.consoles().join_in_cloud(
                         user, session_id, nullptr, request.token());
                   });
}

auto GameInvitationsBridge::join_party_on(const Request& request,
                                          const Bytes& account_id,
                                          const Bytes& hardware_id,
                                          const std::string& session_id)
    -> std::optional<libchiaking::consoles::InvitationJoinFailure> {
  using Failure = libchiaking::consoles::InvitationJoinFailure;
  return joined_as(account_id,
                   [&](Opened& opened, libchiaking::users::PsUser& user)
                       -> libchiaking::Expected<void, Failure> {
                     const auto console = opened.console(hardware_id);
                     if (!console) {
                       return libchiaking::unexpected(
                           Failure{Failure::Reason::console_unavailable});
                     }
                     return opened.consoles().join_party_on(
                         *console, user, session_id, nullptr, request.token());
                   });
}

auto GameInvitationsBridge::join_on(const Request& request,
                                    const Bytes& account_id,
                                    const Bytes& hardware_id,
                                    const std::string& session_id)
    -> std::optional<libchiaking::consoles::InvitationJoinFailure> {
  using Failure = libchiaking::consoles::InvitationJoinFailure;
  return joined_as(account_id,
                   [&](Opened& opened, libchiaking::users::PsUser& user)
                       -> libchiaking::Expected<void, Failure> {
                     const auto console = opened.console(hardware_id);
                     if (!console) {
                       return libchiaking::unexpected(
                           Failure{Failure::Reason::console_unavailable});
                     }
                     return opened.consoles().join_on(
                         *console, user, session_id, nullptr, request.token());
                   });
}

}  // namespace chiaki_bridge
