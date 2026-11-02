#include <algorithm>
#include <chrono>
#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/consoles.hpp"
#include "console_ids.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::consoles::InstalledTitle;
using libchiaking::consoles::StartState;

ConsoleTitlesBridge::StartStates::StartStates(StartStateWatcher watcher,
                                              void* context) noexcept
    : watcher_(watcher), context_(context) {}

void ConsoleTitlesBridge::StartStates::on_state(StartState state) {
  if (watcher_ != nullptr) {
    watcher_(state, context_);
  }
}

auto ConsoleTitlesBridge::facts_of(const InstalledTitle& title)
    -> InstalledTitleFacts {
  InstalledTitleFacts facts{};
  facts.title_id = title.title_id();
  facts.start_id = title.start_id();
  facts.name = title.name();
  facts.cover_url = title.cover_url();
  facts.platform = title.platform();
  if (const auto& used = title.last_used()) {
    facts.last_used_ms = Timestamp::milliseconds_of(used->at);
    facts.last_use_known = used->known;
  }
  facts.recently_played = title.recently_played();
  facts.concept_id = title.concept_id();
  return facts;
}

auto ConsoleTitlesBridge::shelf_of(libchiaking::consoles::HardwareId console,
                                   std::span<const InstalledTitle> titles)
    -> ConsoleShelf {
  ConsoleShelf shelf{};
  shelf.hardware_id = IdentifierBytes::of(console);
  for (const auto& title : titles) {
    shelf.titles.push_back(facts_of(title));
  }
  return shelf;
}

auto ConsoleTitlesBridge::recently_played(const Request& request,
                                          const Bytes& account_id)
    -> RecentlyPlayedOutcome {
  return Boundary::fenced(
      RecentlyPlayedOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> RecentlyPlayedOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return RecentlyPlayedOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return RecentlyPlayedOutcome::refused(ConsolesRefusal::unknown_user);
        }
        const auto recent =
            opened->consoles().recently_played(*user, request.token());
        if (!recent) {
          return RecentlyPlayedOutcome::unanswered(recent.error());
        }
        ConsoleShelves shelves;
        for (const auto& shelf : recent.value()) {
          if (shelf.console) {
            shelves.push_back(
                shelf_of(shelf.console->hardware_id(), shelf.titles));
          }
        }
        return RecentlyPlayedOutcome::listed(std::move(shelves));
      });
}

auto ConsoleTitlesBridge::titles(const Request& request,
                                 const Bytes& account_id,
                                 const Bytes& hardware_id) -> TitlesOutcome {
  return Boundary::fenced(
      TitlesOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> TitlesOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return TitlesOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return TitlesOutcome::refused(ConsolesRefusal::unknown_user);
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return TitlesOutcome::refused(ConsolesRefusal::unknown_console);
        }
        const auto listed = console->titles(*user, request.token());
        if (!listed) {
          return TitlesOutcome::unavailable(listed.error());
        }
        InstalledTitleList installed;
        for (const auto& title : listed.value()) {
          installed.push_back(facts_of(title));
        }
        return TitlesOutcome::listed(std::move(installed));
      });
}

auto ConsoleTitlesBridge::start_title(
    const Request& request, const Bytes& account_id, const Bytes& hardware_id,
    const std::string& title_id, const std::string& start_id,
    StartStateWatcher watcher, void* context) -> StartOutcome {
  return Boundary::fenced(
      StartOutcome::refused(ConsolesRefusal::core_closed),
      [&]() -> StartOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return StartOutcome::refused(ConsolesRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return StartOutcome::refused(ConsolesRefusal::unknown_user);
        }
        const auto console = opened->console(hardware_id);
        if (!console) {
          return StartOutcome::refused(ConsolesRefusal::unknown_console);
        }
        const auto listed = console->titles(*user, request.token());
        if (!listed) {
          return StartOutcome::unavailable(listed.error());
        }
        const auto title = std::ranges::find_if(
            listed.value(), [&](const InstalledTitle& held) {
              return held.title_id() == title_id && held.start_id() == start_id;
            });
        if (title == listed.value().end()) {
          return StartOutcome::refused(ConsolesRefusal::invalid_title);
        }
        StartStates states{watcher, context};
        const auto started =
            console->start(*title, *user, &states, request.token());
        if (started) {
          return StartOutcome::started(started.value());
        }
        return StartOutcome::failed(started.error());
      });
}

}  // namespace chiaki_bridge
