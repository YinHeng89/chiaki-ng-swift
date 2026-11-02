#include "boundary.hpp"
#include "chiaki_bridge/sharing.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::users::Unanswered;
namespace consoles = libchiaking::consoles;

auto SessionSharingBridge::signed_out() -> Unanswered {
  return Unanswered{Unanswered::Reason::signed_out};
}

auto SessionSharingBridge::own_game_session(const Request& request,
                                            const Bytes& account_id,
                                            const std::string& title_id,
                                            const std::string& platform)
    -> OwnGameSessionOutcome {
  return Boundary::fenced(
      OwnGameSessionOutcome::closed(), [&]() -> OwnGameSessionOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return OwnGameSessionOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return OwnGameSessionOutcome::unanswered(signed_out());
        }
        const auto title = libchiaking::NpTitleId::parse(title_id);
        if (!title) {
          return OwnGameSessionOutcome::unanswered(
              Unanswered{Unanswered::Reason::malformed});
        }
        const auto on = platform == "PS4" ? consoles::GamePlatform::ps4
                                          : consoles::GamePlatform::ps5;
        auto found = opened->chiaki().consoles().own_game_session(
            *user, *title, on, request.token());
        if (!found) {
          return OwnGameSessionOutcome::unanswered(found.error());
        }
        if (!found.value()) {
          return OwnGameSessionOutcome::missing();
        }
        const auto& session = *found.value();
        return OwnGameSessionOutcome::found(OwnGameSessionFacts{
            session.session_id, session.name, session.players,
            session.max_players, session.open_to_anyone});
      });
}

auto SessionSharingBridge::share(const Request& request,
                                 const Bytes& account_id,
                                 const std::string& session_id)
    -> SessionLinkOutcome {
  return Boundary::fenced(
      SessionLinkOutcome::closed(), [&]() -> SessionLinkOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return SessionLinkOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return SessionLinkOutcome::unanswered(signed_out());
        }
        auto link = opened->chiaki().consoles().share_game_session(
            *user, session_id, request.token());
        if (!link) {
          return SessionLinkOutcome::unanswered(link.error());
        }
        return SessionLinkOutcome::linked(
            SessionLinkFacts{link->url, link->image_url});
      });
}

auto SessionSharingBridge::invite(const Request& request,
                                  const Bytes& account_id, bool party,
                                  const std::string& session_id,
                                  const Texts& account_ids)
    -> std::optional<Unanswered> {
  const std::optional<Unanswered> closed{
      Unanswered{Unanswered::Reason::unavailable}};
  return Boundary::fenced(closed, [&]() -> std::optional<Unanswered> {
    const auto opened = Opened::shared();
    if (!opened) {
      return closed;
    }
    const auto user = opened->user(account_id);
    if (!user) {
      return signed_out();
    }
    const consoles::InvitationTarget target{
        party ? consoles::InvitationTarget::Kind::party
              : consoles::InvitationTarget::Kind::game,
        session_id};
    std::vector<libchiaking::AccountId> accounts;
    accounts.reserve(account_ids.size());
    for (const auto& id : account_ids) {
      if (const auto account = libchiaking::AccountId::parse(id)) {
        accounts.push_back(*account);
      }
    }
    auto sent = opened->chiaki().consoles().invite_friends(
        *user, target, accounts, request.token());
    if (!sent) {
      return sent.error();
    }
    return std::nullopt;
  });
}

auto SessionSharingBridge::friends(const Request& request,
                                   const Bytes& account_id)
    -> PsnFriendsOutcome {
  return Boundary::fenced(
      PsnFriendsOutcome::closed(), [&]() -> PsnFriendsOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return PsnFriendsOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return PsnFriendsOutcome::unanswered(signed_out());
        }
        auto listed =
            opened->chiaki().consoles().friends(*user, request.token());
        if (!listed) {
          return PsnFriendsOutcome::unanswered(listed.error());
        }
        std::vector<PsnFriendFacts> found;
        for (const auto& entry : listed.value()) {
          found.push_back(PsnFriendFacts{entry.account_id.decimal(),
                                         entry.online_id, entry.avatar_url,
                                         entry.online, entry.playing});
        }
        return PsnFriendsOutcome::listed(std::move(found));
      });
}

}  // namespace chiaki_bridge
