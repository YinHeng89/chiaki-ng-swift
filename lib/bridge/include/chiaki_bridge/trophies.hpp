#pragma once

#include <cstdint>
#include <libchiaking/trophies.hpp>
#include <libchiaking/users.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

struct TrophyCountsFacts {
  std::uint32_t bronze;
  std::uint32_t silver;
  std::uint32_t gold;
  std::uint32_t platinum;
};

struct TrophySummaryFacts {
  std::uint32_t level;
  std::uint32_t tier;
  std::uint32_t progress;
  TrophyCountsFacts earned;
};

struct TrophyTitleFacts {
  std::string id;
  std::string name;
  std::string icon_url;
  std::vector<std::uint8_t> platforms;
  TrophyCountsFacts defined;
  TrophyCountsFacts earned;
  std::uint32_t progress;
  bool hidden;
  std::int64_t updated_ms;
};

struct TrophyGroupFacts {
  std::string id;
  std::string name;
  std::string icon_url;
  TrophyCountsFacts defined;
  TrophyCountsFacts earned;
  std::uint32_t progress;
};

struct TrophyFacts {
  std::uint32_t id;
  std::string group;
  std::uint8_t grade;
  std::string name;
  std::string detail;
  std::string icon_url;
  bool hidden;
  bool earned;
  std::int64_t earned_ms;
  std::int8_t rarity;
  double earned_rate;
  bool has_earned_rate;
  std::uint64_t progress_value;
  std::uint64_t progress_target;
  bool has_progress;
};

/// One game's trophy groups and trophies.
struct TitleTrophiesFacts {
  /// The trophy groups.
  std::vector<TrophyGroupFacts> groups;
  /// The trophies.
  std::vector<TrophyFacts> trophies;
};

/// The trophies of the game being played.
struct CurrentTrophiesFacts {
  /// The game's trophy set.
  TrophyTitleFacts title;
  /// The trophy groups.
  std::vector<TrophyGroupFacts> groups;
  /// The trophies.
  std::vector<TrophyFacts> trophies;
};

/// How reading an account's trophy level ended: read, unanswered or with
/// the core closed.
class TrophySummaryOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// PSN returned the summary.
    read,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A summary PSN returned.
  static auto read(TrophySummaryFacts value) -> TrophySummaryOutcome {
    return TrophySummaryOutcome{Case{
        std::in_place_index<std::to_underlying(Kind::read)>, std::move(value)}};
  }

  /// A read PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> TrophySummaryOutcome {
    return TrophySummaryOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(why)}};
  }

  /// A read made while the core was closed.
  static auto closed() -> TrophySummaryOutcome {
    return TrophySummaryOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The summary; valid for `read`.
  auto summary() const -> TrophySummaryFacts {
    return std::get<std::to_underlying(Kind::read)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<TrophySummaryFacts, libchiaking::users::Unanswered,
                            std::monostate>;

  explicit TrophySummaryOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How listing the games an account has trophies in ended: listed,
/// unanswered or with the core closed.
class TrophyTitlesOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// PSN listed the games.
    listed,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A listing PSN answered.
  static auto listed(std::vector<TrophyTitleFacts> value)
      -> TrophyTitlesOutcome {
    return TrophyTitlesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::listed)>,
             std::move(value)}};
  }

  /// A listing PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> TrophyTitlesOutcome {
    return TrophyTitlesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(why)}};
  }

  /// A listing made while the core was closed.
  static auto closed() -> TrophyTitlesOutcome {
    return TrophyTitlesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The games, most recently updated first; valid for `listed`.
  auto titles() const -> std::vector<TrophyTitleFacts> {
    return std::get<std::to_underlying(Kind::listed)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<std::vector<TrophyTitleFacts>,
                            libchiaking::users::Unanswered, std::monostate>;

  explicit TrophyTitlesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How reading one game's trophies ended: read, not found, unanswered or
/// with the core closed.
class TitleTrophiesOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// PSN returned the trophies.
    read,
    /// The game is not in the account's list.
    missing,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// Trophies PSN returned.
  static auto read(TitleTrophiesFacts value) -> TitleTrophiesOutcome {
    return TitleTrophiesOutcome{Case{
        std::in_place_index<std::to_underlying(Kind::read)>, std::move(value)}};
  }

  /// A game no longer in the account's list.
  static auto missing() -> TitleTrophiesOutcome {
    return TitleTrophiesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::missing)>}};
  }

  /// A read PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> TitleTrophiesOutcome {
    return TitleTrophiesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(why)}};
  }

  /// A read made while the core was closed.
  static auto closed() -> TitleTrophiesOutcome {
    return TitleTrophiesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The game's trophies; valid for `read`.
  auto trophies() const -> TitleTrophiesFacts {
    return std::get<std::to_underlying(Kind::read)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<TitleTrophiesFacts, std::monostate,
                            libchiaking::users::Unanswered, std::monostate>;

  explicit TitleTrophiesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How reading the trophies of the game being played ended: read, no
/// trophy set, unanswered or with the core closed.
class CurrentTrophiesOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// PSN returned the trophies.
    read,
    /// PSN knows no trophy set for the release.
    missing,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// Trophies PSN returned.
  static auto read(CurrentTrophiesFacts value) -> CurrentTrophiesOutcome {
    return CurrentTrophiesOutcome{Case{
        std::in_place_index<std::to_underlying(Kind::read)>, std::move(value)}};
  }

  /// A release with no trophy set.
  static auto missing() -> CurrentTrophiesOutcome {
    return CurrentTrophiesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::missing)>}};
  }

  /// A read PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> CurrentTrophiesOutcome {
    return CurrentTrophiesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(why)}};
  }

  /// A read made while the core was closed.
  static auto closed() -> CurrentTrophiesOutcome {
    return CurrentTrophiesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The game's trophy set and trophies; valid for `read`.
  auto current() const -> CurrentTrophiesFacts {
    return std::get<std::to_underlying(Kind::read)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<CurrentTrophiesFacts, std::monostate,
                            libchiaking::users::Unanswered, std::monostate>;

  explicit CurrentTrophiesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class TrophiesBridge {
 public:
  static auto summary(const Request& request, const Bytes& account_id)
      -> TrophySummaryOutcome;
  static auto titles(const Request& request, const Bytes& account_id)
      -> TrophyTitlesOutcome;
  static auto trophies(const Request& request, const Bytes& account_id,
                       const std::string& title_id) -> TitleTrophiesOutcome;
  static auto current(const Request& request, const Bytes& account_id,
                      const std::string& np_title_id) -> CurrentTrophiesOutcome;
  static auto start_over(const Bytes& account_id) -> bool;

 private:
  static auto facts_of(const libchiaking::trophies::TrophyCounts& counts)
      -> TrophyCountsFacts;
  static auto facts_of(const libchiaking::trophies::TrophyTitle& title)
      -> TrophyTitleFacts;
  static auto facts_of(const libchiaking::trophies::TrophyGroup& group)
      -> TrophyGroupFacts;
  static auto facts_of(const libchiaking::trophies::Trophy& trophy)
      -> TrophyFacts;
  static auto milliseconds_of(
      const std::optional<libchiaking::trophies::Time>& time) -> std::int64_t;
  static auto signed_out() -> libchiaking::users::Unanswered;
};

}  // namespace chiaki_bridge
