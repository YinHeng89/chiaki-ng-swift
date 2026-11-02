#include <algorithm>

#include "boundary.hpp"
#include "chiaki_bridge/trophies.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::users::Unanswered;
namespace trophies = libchiaking::trophies;

auto TrophiesBridge::facts_of(const trophies::TrophyCounts& counts)
    -> TrophyCountsFacts {
  return TrophyCountsFacts{counts.bronze, counts.silver, counts.gold,
                           counts.platinum};
}

auto TrophiesBridge::milliseconds_of(const std::optional<trophies::Time>& time)
    -> std::int64_t {
  if (!time) {
    return 0;
  }
  return Timestamp::milliseconds_of(*time);
}

auto TrophiesBridge::facts_of(const trophies::TrophyTitle& title)
    -> TrophyTitleFacts {
  TrophyTitleFacts facts{title.id.text(),
                         title.name,
                         title.icon_url,
                         {},
                         facts_of(title.defined),
                         facts_of(title.earned),
                         title.progress,
                         title.hidden,
                         milliseconds_of(title.last_updated)};
  for (const auto platform : title.platforms) {
    facts.platforms.push_back(static_cast<std::uint8_t>(platform));
  }
  return facts;
}

auto TrophiesBridge::facts_of(const trophies::TrophyGroup& group)
    -> TrophyGroupFacts {
  return TrophyGroupFacts{group.id.text(),        group.name,
                          group.icon_url,         facts_of(group.defined),
                          facts_of(group.earned), group.progress};
}

auto TrophiesBridge::facts_of(const trophies::Trophy& trophy) -> TrophyFacts {
  TrophyFacts facts{};
  facts.id = trophy.id.value();
  facts.group = trophy.group.text();
  facts.grade = static_cast<std::uint8_t>(trophy.grade);
  facts.name = trophy.name;
  facts.detail = trophy.detail;
  facts.icon_url = trophy.icon_url;
  facts.hidden = trophy.hidden;
  facts.earned = trophy.earned;
  facts.earned_ms = milliseconds_of(trophy.earned_at);
  facts.rarity = trophy.rarity ? static_cast<std::int8_t>(*trophy.rarity)
                               : static_cast<std::int8_t>(-1);
  facts.has_earned_rate = trophy.earned_rate.has_value();
  facts.earned_rate = trophy.earned_rate.value_or(0);
  facts.progress_target = trophy.progress_target.value_or(0);
  facts.has_progress = trophy.progress.has_value();
  facts.progress_value = trophy.progress ? trophy.progress->value : 0;
  return facts;
}

auto TrophiesBridge::signed_out() -> Unanswered {
  return Unanswered{Unanswered::Reason::signed_out};
}

auto TrophiesBridge::summary(const Request& request, const Bytes& account_id)
    -> TrophySummaryOutcome {
  return Boundary::fenced(
      TrophySummaryOutcome::closed(), [&]() -> TrophySummaryOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return TrophySummaryOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return TrophySummaryOutcome::unanswered(signed_out());
        }
        auto read =
            opened->chiaki().trophies().summary_of(*user, request.token());
        if (!read) {
          return TrophySummaryOutcome::unanswered(read.error());
        }
        return TrophySummaryOutcome::read(TrophySummaryFacts{
            read->level, read->tier, read->progress, facts_of(read->earned)});
      });
}

auto TrophiesBridge::titles(const Request& request, const Bytes& account_id)
    -> TrophyTitlesOutcome {
  return Boundary::fenced(
      TrophyTitlesOutcome::closed(), [&]() -> TrophyTitlesOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return TrophyTitlesOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return TrophyTitlesOutcome::unanswered(signed_out());
        }
        auto read =
            opened->chiaki().trophies().titles_of(*user, request.token());
        if (!read) {
          return TrophyTitlesOutcome::unanswered(read.error());
        }
        std::vector<TrophyTitleFacts> listed;
        for (const auto& title : read.value()) {
          listed.push_back(facts_of(title));
        }
        return TrophyTitlesOutcome::listed(std::move(listed));
      });
}

auto TrophiesBridge::trophies(const Request& request, const Bytes& account_id,
                              const std::string& title_id)
    -> TitleTrophiesOutcome {
  return Boundary::fenced(
      TitleTrophiesOutcome::closed(), [&]() -> TitleTrophiesOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return TitleTrophiesOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return TitleTrophiesOutcome::unanswered(signed_out());
        }
        auto& service = opened->chiaki().trophies();
        auto titles = service.titles_of(*user, request.token());
        if (!titles) {
          return TitleTrophiesOutcome::unanswered(titles.error());
        }
        const auto title = std::ranges::find_if(
            titles.value(), [&](const trophies::TrophyTitle& candidate) {
              return candidate.id == title_id;
            });
        if (title == titles.value().end()) {
          return TitleTrophiesOutcome::missing();
        }
        auto read = service.trophies_of(*user, *title, request.token());
        if (!read) {
          return TitleTrophiesOutcome::unanswered(read.error());
        }
        TitleTrophiesFacts found;
        for (const auto& group : read->groups) {
          found.groups.push_back(facts_of(group));
        }
        for (const auto& trophy : read->trophies) {
          found.trophies.push_back(facts_of(trophy));
        }
        return TitleTrophiesOutcome::read(std::move(found));
      });
}

auto TrophiesBridge::current(const Request& request, const Bytes& account_id,
                             const std::string& np_title_id)
    -> CurrentTrophiesOutcome {
  return Boundary::fenced(
      CurrentTrophiesOutcome::closed(), [&]() -> CurrentTrophiesOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return CurrentTrophiesOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return CurrentTrophiesOutcome::unanswered(signed_out());
        }
        const auto title = libchiaking::NpTitleId::parse(np_title_id);
        if (!title) {
          return CurrentTrophiesOutcome::missing();
        }
        auto read = opened->chiaki().trophies().current_trophies(
            *user, *title, request.token());
        if (!read) {
          return CurrentTrophiesOutcome::unanswered(read.error());
        }
        if (!read->has_value()) {
          return CurrentTrophiesOutcome::missing();
        }
        const auto& playing = read->value();
        CurrentTrophiesFacts found{facts_of(playing.title), {}, {}};
        for (const auto& group : playing.trophies.groups) {
          found.groups.push_back(facts_of(group));
        }
        for (const auto& trophy : playing.trophies.trophies) {
          found.trophies.push_back(facts_of(trophy));
        }
        return CurrentTrophiesOutcome::read(std::move(found));
      });
}

auto TrophiesBridge::start_over(const Bytes& account_id) -> bool {
  return Boundary::fenced(false, [&] {
    const auto opened = Opened::shared();
    if (!opened) {
      return false;
    }
    const auto user = opened->user(account_id);
    if (!user) {
      return false;
    }
    opened->chiaki().trophies().start_over(*user);
    return true;
  });
}

}  // namespace chiaki_bridge
