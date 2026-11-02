#pragma once

#include <cstdint>
#include <libchiaking/consoles.hpp>
#include <libchiaking/users.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

/// The game session an account plays in.
struct OwnGameSessionFacts {
  /// The session's id.
  std::string session_id;
  /// The session's name.
  std::string name;
  /// How many players are in it.
  std::uint32_t players;
  /// How many players it takes.
  std::uint32_t max_players;
  /// Whether anyone may join without an invitation.
  bool open_to_anyone;
};

/// A link friends can open to join a game session.
struct SessionLinkFacts {
  /// The link.
  std::string url;
  /// The image shown with the link, empty when there is none.
  std::string image_url;
};

/// One of an account's PSN friends.
struct PsnFriendFacts {
  /// The friend's account id, in decimal.
  std::string account_id;
  /// The friend's online id.
  std::string online_id;
  /// The friend's avatar address.
  std::string avatar_url;
  /// Whether the friend is online.
  bool online;
  /// What the friend is playing, empty when nothing.
  std::string playing;
};

/// How looking for the account's own game session ended: found, not found,
/// unanswered or with the core closed.
class OwnGameSessionOutcome {
 public:
  /// The ways the lookup can end.
  enum class Kind : std::uint8_t {
    /// The account plays in a session for the title.
    found,
    /// The account plays in no session for the title.
    missing,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A session the account plays in.
  static auto found(OwnGameSessionFacts value) -> OwnGameSessionOutcome {
    return OwnGameSessionOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::found)>,
             std::move(value)}};
  }

  /// No session for the title.
  static auto missing() -> OwnGameSessionOutcome {
    return OwnGameSessionOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::missing)>}};
  }

  /// A lookup PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> OwnGameSessionOutcome {
    return OwnGameSessionOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>, why}};
  }

  /// A lookup made while the core was closed.
  static auto closed() -> OwnGameSessionOutcome {
    return OwnGameSessionOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the lookup ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The session; valid for `found`.
  auto session() const -> OwnGameSessionFacts {
    return std::get<std::to_underlying(Kind::found)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<OwnGameSessionFacts, std::monostate,
                            libchiaking::users::Unanswered, std::monostate>;

  explicit OwnGameSessionOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How asking for a share link ended: linked, unanswered or with the core
/// closed.
class SessionLinkOutcome {
 public:
  /// The ways the request can end.
  enum class Kind : std::uint8_t {
    /// PSN returned a link.
    linked,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A link PSN returned.
  static auto linked(SessionLinkFacts value) -> SessionLinkOutcome {
    return SessionLinkOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::linked)>,
             std::move(value)}};
  }

  /// A request PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> SessionLinkOutcome {
    return SessionLinkOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>, why}};
  }

  /// A request made while the core was closed.
  static auto closed() -> SessionLinkOutcome {
    return SessionLinkOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the request ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The link; valid for `linked`.
  auto link() const -> SessionLinkFacts {
    return std::get<std::to_underlying(Kind::linked)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<SessionLinkFacts, libchiaking::users::Unanswered,
                            std::monostate>;

  explicit SessionLinkOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How listing an account's friends ended: listed, unanswered or with the
/// core closed.
class PsnFriendsOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// PSN listed the friends.
    listed,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A listing PSN answered.
  static auto listed(std::vector<PsnFriendFacts> value) -> PsnFriendsOutcome {
    return PsnFriendsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::listed)>,
             std::move(value)}};
  }

  /// A listing PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> PsnFriendsOutcome {
    return PsnFriendsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>, why}};
  }

  /// A listing made while the core was closed.
  static auto closed() -> PsnFriendsOutcome {
    return PsnFriendsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The friends, online friends first; valid for `listed`.
  auto friends() const -> std::vector<PsnFriendFacts> {
    return std::get<std::to_underlying(Kind::listed)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<std::vector<PsnFriendFacts>,
                            libchiaking::users::Unanswered, std::monostate>;

  explicit PsnFriendsOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// Finds, shares and invites friends to an account's game sessions through
/// the open core.
class SessionSharingBridge {
 public:
  /// The game session the account plays in for a title on a platform.
  static auto own_game_session(const Request& request, const Bytes& account_id,
                               const std::string& title_id,
                               const std::string& platform)
      -> OwnGameSessionOutcome;
  /// A link friends can open to join a session.
  static auto share(const Request& request, const Bytes& account_id,
                    const std::string& session_id) -> SessionLinkOutcome;
  /// Invites friends to a game session or a party, giving why PSN did not
  /// answer when it did not.
  [[nodiscard]] static auto invite(const Request& request,
                                   const Bytes& account_id, bool party,
                                   const std::string& session_id,
                                   const Texts& account_ids)
      -> std::optional<libchiaking::users::Unanswered>;
  /// The account's friends.
  static auto friends(const Request& request, const Bytes& account_id)
      -> PsnFriendsOutcome;

 private:
  static auto signed_out() -> libchiaking::users::Unanswered;
};

}  // namespace chiaki_bridge
