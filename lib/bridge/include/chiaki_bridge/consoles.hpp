#pragma once

#include <cstddef>
#include <cstdint>
#include <libchiaking/consoles.hpp>
#include <libchiaking/users.hpp>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

enum class PairingRefusal : std::uint8_t {
  core_closed,
  unknown_user,
  unknown_console,
  invalid_address,
  invalid_pin,
};

/// How pairing ended: paired, refused before the core ran, or failed.
class PairingOutcome {
 public:
  /// The ways the pairing can end.
  enum class Kind : std::uint8_t {
    /// The console is paired.
    paired,
    /// The bridge refused before the core ran.
    refused,
    /// The core could not pair.
    failed,
  };

  /// A console now paired.
  static auto paired(ConsoleFacts value) -> PairingOutcome {
    return PairingOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::paired)>,
             std::move(value)}};
  }

  /// A pairing the bridge refused.
  static auto refused(PairingRefusal value) -> PairingOutcome {
    return PairingOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// A pairing that failed.
  static auto failed(libchiaking::consoles::PairingFailure value)
      -> PairingOutcome {
    return PairingOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::failed)>,
             std::move(value)}};
  }

  /// How the pairing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The paired console; valid for `paired`.
  auto console() const -> ConsoleFacts {
    return std::get<std::to_underlying(Kind::paired)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> PairingRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

  /// Why pairing failed; valid for `failed`.
  auto failure() const -> libchiaking::consoles::PairingFailure {
    return std::get<std::to_underlying(Kind::failed)>(held_);
  }

 private:
  using Case = std::variant<ConsoleFacts, PairingRefusal,
                            libchiaking::consoles::PairingFailure>;

  explicit PairingOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

using PairingProgressWatcher = void (*)(
    const libchiaking::consoles::PairingProgress* progress, void* context);

class PairingBridge {
 public:
  static auto pair_at_home(const Request& request, const Bytes& account_id,
                           const std::string& address,
                           libchiaking::consoles::Generation generation,
                           const char* pin, PairingProgressWatcher watcher,
                           void* context) -> PairingOutcome;
  static auto pair_over_internet(
      const Request& request, const Bytes& account_id, const Bytes& device_uid,
      const std::string& name, libchiaking::consoles::Generation generation,
      PairingProgressWatcher watcher, void* context) -> PairingOutcome;

 private:
  class Steps final : public libchiaking::consoles::PairingWatcher {
   public:
    Steps(PairingProgressWatcher watcher, void* context) noexcept;
    void on_progress(
        const libchiaking::consoles::PairingProgress& progress) override;

   private:
    PairingProgressWatcher watcher_;
    void* context_;
  };

  using Paired =
      libchiaking::Expected<std::shared_ptr<libchiaking::consoles::Console>,
                            libchiaking::consoles::PairingFailure>;

  static auto outcome_of(const Paired& result) -> PairingOutcome;
};

enum class ConsolesRefusal : std::uint8_t {
  core_closed,
  unknown_user,
  unknown_console,
  invalid_address,
  address_not_for_generation,
  invalid_title,
  store_unavailable,
};

/// A console that could not be reached when checked.
struct UnreachableFacts {
  /// What the core now believes of the console.
  libchiaking::consoles::Presence presence;
  /// Why it could not be reached.
  libchiaking::consoles::Unreachable unreachable;
};

/// How checking a console ended: checked, unreachable or refused.
class CheckOutcome {
 public:
  /// The ways the check can end.
  enum class Kind : std::uint8_t {
    /// The console answered.
    checked,
    /// The console could not be reached.
    unreachable,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A console that answered.
  static auto checked(libchiaking::consoles::Presence value) -> CheckOutcome {
    return CheckOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::checked)>,
             std::move(value)}};
  }

  /// A console that could not be reached.
  static auto unreachable(UnreachableFacts value) -> CheckOutcome {
    return CheckOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unreachable)>,
             std::move(value)}};
  }

  /// A check the bridge refused.
  static auto refused(ConsolesRefusal value) -> CheckOutcome {
    return CheckOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the check ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// What the console is doing; valid for `checked`.
  auto presence() const -> libchiaking::consoles::Presence {
    return std::get<std::to_underlying(Kind::checked)>(held_);
  }

  /// Why the console could not be reached; valid for `unreachable`.
  auto failure() const -> UnreachableFacts {
    return std::get<std::to_underlying(Kind::unreachable)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<libchiaking::consoles::Presence, UnreachableFacts,
                            ConsolesRefusal>;

  explicit CheckOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How waking a console ended: woken, declined by the core or refused.
class WakeOutcome {
 public:
  /// The ways the wake can end.
  enum class Kind : std::uint8_t {
    /// The console was woken.
    woken,
    /// The core could not wake the console.
    declined,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A console now woken.
  static auto woken() -> WakeOutcome {
    return WakeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::woken)>}};
  }

  /// A wake the core declined.
  static auto declined(libchiaking::consoles::WakeRefusal value)
      -> WakeOutcome {
    return WakeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::declined)>,
             std::move(value)}};
  }

  /// A wake the bridge refused.
  static auto refused(ConsolesRefusal value) -> WakeOutcome {
    return WakeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the wake ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// Why the core declined; valid for `declined`.
  auto decline() const -> libchiaking::consoles::WakeRefusal {
    return std::get<std::to_underlying(Kind::declined)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<std::monostate, libchiaking::consoles::WakeRefusal,
                            ConsolesRefusal>;

  explicit WakeOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How changing a console's details ended: changed, unchanged or refused.
class ChangeOutcome {
 public:
  /// The ways the change can end.
  enum class Kind : std::uint8_t {
    /// The core saved the change.
    changed,
    /// The core kept the console as it was.
    unchanged,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A change the core saved.
  static auto changed() -> ChangeOutcome {
    return ChangeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::changed)>}};
  }

  /// A change the core did not make.
  static auto unchanged(libchiaking::consoles::Console::Unchanged value)
      -> ChangeOutcome {
    return ChangeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unchanged)>,
             std::move(value)}};
  }

  /// A change the bridge refused.
  static auto refused(ConsolesRefusal value) -> ChangeOutcome {
    return ChangeOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the change ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// Why the console is unchanged; valid for `unchanged`.
  auto why_unchanged() const -> libchiaking::consoles::Console::Unchanged {
    return std::get<std::to_underlying(Kind::unchanged)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<std::monostate, libchiaking::consoles::Console::Unchanged,
                   ConsolesRefusal>;

  explicit ChangeOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class ConsolesBridge {
 public:
  static auto everything() -> ConsoleList;
  static auto paired_with(const Bytes& hardware_id, const Bytes& account_id)
      -> bool;
  static auto forget(const Bytes& hardware_id)
      -> std::optional<ConsolesRefusal>;
  static auto unpair(const Bytes& account_id, const Bytes& hardware_id)
      -> std::optional<ConsolesRefusal>;
  static auto check(const Request& request, const Bytes& hardware_id)
      -> CheckOutcome;
  static auto route(const Request& request, const Bytes& account_id,
                    const Bytes& hardware_id)
      -> std::optional<libchiaking::consoles::Route>;
  static auto wake(const Request& request, const Bytes& account_id,
                   const Bytes& hardware_id, bool wait) -> WakeOutcome;
  static auto rename(const Bytes& hardware_id, const std::string& name)
      -> ChangeOutcome;
  static auto moved_to(const Bytes& hardware_id, const std::string& address)
      -> ChangeOutcome;
};

struct NetworkView {
  ConsoleList nearby;
  std::size_t targets;
  std::size_t visited;
  bool network_available;
  bool permission_denied;
  Texts broadcast_ranges;
  Texts unicast_ranges;
};

using NetworkViewWatcher = void (*)(const NetworkView* view, void* context);

/// A search that stopped before its end.
struct SearchFailureFacts {
  /// How many addresses the ranges hold.
  std::size_t targets;
  /// Why the search stopped.
  libchiaking::consoles::SearchFailure failure;
};

/// How checking search ranges or searching ended: covered, failed, with
/// invalid ranges, or refused.
class SearchOutcome {
 public:
  /// The ways the search can end.
  enum class Kind : std::uint8_t {
    /// The ranges are valid, and a search ran to its end.
    covered,
    /// The search stopped before its end.
    failed,
    /// The ranges are invalid.
    invalid,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Ranges that hold their targets.
  static auto covered(std::size_t value) -> SearchOutcome {
    return SearchOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::covered)>,
             std::move(value)}};
  }

  /// A search that stopped.
  static auto failed(SearchFailureFacts value) -> SearchOutcome {
    return SearchOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::failed)>,
             std::move(value)}};
  }

  /// Ranges the core found invalid.
  static auto invalid(libchiaking::consoles::SearchRanges::Invalid value)
      -> SearchOutcome {
    return SearchOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::invalid)>,
             std::move(value)}};
  }

  /// A search the bridge refused.
  static auto refused(ConsolesRefusal value) -> SearchOutcome {
    return SearchOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the search ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// How many addresses the ranges hold; valid for `covered`.
  auto targets() const -> std::size_t {
    return std::get<std::to_underlying(Kind::covered)>(held_);
  }

  /// Why the search stopped; valid for `failed`.
  auto failure() const -> SearchFailureFacts {
    return std::get<std::to_underlying(Kind::failed)>(held_);
  }

  /// Why the ranges are invalid; valid for `invalid`.
  auto why_invalid() const -> libchiaking::consoles::SearchRanges::Invalid {
    return std::get<std::to_underlying(Kind::invalid)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<std::size_t, SearchFailureFacts,
                            libchiaking::consoles::SearchRanges::Invalid,
                            ConsolesRefusal>;

  explicit SearchOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class DiscoveryBridge {
 public:
  static auto ranges(const Texts& subnets, bool unicast) -> SearchOutcome;
  static auto search(const Request& request, const Texts& subnets, bool unicast,
                     NetworkViewWatcher watcher, void* context)
      -> SearchOutcome;

 private:
  class Lookout final : public libchiaking::consoles::NetworkWatcher {
   public:
    Lookout(NetworkViewWatcher watcher, void* context) noexcept;
    void on_view(const libchiaking::consoles::NetworkView& view) override;

   private:
    NetworkViewWatcher watcher_;
    void* context_;
  };
};

struct AccountConsoleFacts {
  Bytes device_uid;
  std::string name;
  libchiaking::consoles::Generation generation;
  bool remote_play_enabled;
  bool main_ps4;
};

using AccountConsoleList = std::vector<AccountConsoleFacts>;

/// How listing an account's consoles ended: listed, unanswered or refused.
class AccountConsolesOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// PSN listed the consoles.
    listed,
    /// PSN gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Consoles PSN listed.
  static auto listed(AccountConsoleList value) -> AccountConsolesOutcome {
    return AccountConsolesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::listed)>,
             std::move(value)}};
  }

  /// A listing PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered value)
      -> AccountConsolesOutcome {
    return AccountConsolesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A listing the bridge refused.
  static auto refused(ConsolesRefusal value) -> AccountConsolesOutcome {
    return AccountConsolesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The consoles; valid for `listed`.
  auto consoles() const -> AccountConsoleList {
    return std::get<std::to_underlying(Kind::listed)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<AccountConsoleList, libchiaking::users::Unanswered,
                            ConsolesRefusal>;

  explicit AccountConsolesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class AccountConsolesBridge {
 public:
  static auto on_account(const Request& request, const Bytes& account_id,
                         libchiaking::consoles::Generation generation)
      -> AccountConsolesOutcome;
};

struct InstalledTitleFacts {
  std::string title_id;
  std::string start_id;
  std::string name;
  std::string cover_url;
  libchiaking::consoles::Generation platform;
  std::optional<std::int64_t> last_used_ms;
  std::optional<libchiaking::consoles::InstalledTitle::LastUse::Known>
      last_use_known;
  bool recently_played;
  std::string concept_id;
};

using InstalledTitleList = std::vector<InstalledTitleFacts>;

struct ConsoleShelf {
  Bytes hardware_id;
  InstalledTitleList titles;
};

using ConsoleShelves = std::vector<ConsoleShelf>;

/// How listing the titles recently played on the account's consoles ended:
/// listed, unanswered or refused.
class RecentlyPlayedOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// PSN listed the titles.
    listed,
    /// PSN gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Titles PSN listed.
  static auto listed(ConsoleShelves value) -> RecentlyPlayedOutcome {
    return RecentlyPlayedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::listed)>,
             std::move(value)}};
  }

  /// A listing PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered value)
      -> RecentlyPlayedOutcome {
    return RecentlyPlayedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A listing the bridge refused.
  static auto refused(ConsolesRefusal value) -> RecentlyPlayedOutcome {
    return RecentlyPlayedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// Each console with its titles; valid for `listed`.
  auto shelves() const -> ConsoleShelves {
    return std::get<std::to_underlying(Kind::listed)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<ConsoleShelves, libchiaking::users::Unanswered,
                            ConsolesRefusal>;

  explicit RecentlyPlayedOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How listing a console's titles ended: listed, unavailable or refused.
class TitlesOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// The core listed the titles.
    listed,
    /// The titles could not be listed.
    unavailable,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Titles the core listed.
  static auto listed(InstalledTitleList value) -> TitlesOutcome {
    return TitlesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::listed)>,
             std::move(value)}};
  }

  /// A listing the core could not make.
  static auto unavailable(libchiaking::consoles::TitlesUnavailable value)
      -> TitlesOutcome {
    return TitlesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unavailable)>,
             std::move(value)}};
  }

  /// A listing the bridge refused.
  static auto refused(ConsolesRefusal value) -> TitlesOutcome {
    return TitlesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The titles; valid for `listed`.
  auto titles() const -> InstalledTitleList {
    return std::get<std::to_underlying(Kind::listed)>(held_);
  }

  /// Why the titles are unavailable; valid for `unavailable`.
  auto why_unavailable() const -> libchiaking::consoles::TitlesUnavailable {
    return std::get<std::to_underlying(Kind::unavailable)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<InstalledTitleList, libchiaking::consoles::TitlesUnavailable,
                   ConsolesRefusal>;

  explicit TitlesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

using StartStateWatcher = void (*)(libchiaking::consoles::StartState state,
                                   void* context);

/// How starting a title ended: started, with the titles unavailable,
/// failed or refused.
class StartOutcome {
 public:
  /// The ways the start can end.
  enum class Kind : std::uint8_t {
    /// The console started the title, or got as far as the state.
    started,
    /// The console's titles could not be listed.
    unavailable,
    /// The console did not start the title.
    failed,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A start that got as far as a state.
  static auto started(libchiaking::consoles::StartState value) -> StartOutcome {
    return StartOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::started)>,
             std::move(value)}};
  }

  /// A start whose titles could not be listed.
  static auto unavailable(libchiaking::consoles::TitlesUnavailable value)
      -> StartOutcome {
    return StartOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unavailable)>,
             std::move(value)}};
  }

  /// A start that failed.
  static auto failed(libchiaking::consoles::StartFailure value)
      -> StartOutcome {
    return StartOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::failed)>,
             std::move(value)}};
  }

  /// A start the bridge refused.
  static auto refused(ConsolesRefusal value) -> StartOutcome {
    return StartOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the start ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// How far the console got; valid for `started`.
  auto state() const -> libchiaking::consoles::StartState {
    return std::get<std::to_underlying(Kind::started)>(held_);
  }

  /// Why the titles are unavailable; valid for `unavailable`.
  auto why_unavailable() const -> libchiaking::consoles::TitlesUnavailable {
    return std::get<std::to_underlying(Kind::unavailable)>(held_);
  }

  /// Why the start failed; valid for `failed`.
  auto failure() const -> libchiaking::consoles::StartFailure {
    return std::get<std::to_underlying(Kind::failed)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<libchiaking::consoles::StartState,
                   libchiaking::consoles::TitlesUnavailable,
                   libchiaking::consoles::StartFailure, ConsolesRefusal>;

  explicit StartOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class ConsoleTitlesBridge {
 public:
  static auto recently_played(const Request& request, const Bytes& account_id)
      -> RecentlyPlayedOutcome;
  static auto titles(const Request& request, const Bytes& account_id,
                     const Bytes& hardware_id) -> TitlesOutcome;
  static auto start_title(const Request& request, const Bytes& account_id,
                          const Bytes& hardware_id, const std::string& title_id,
                          const std::string& start_id,
                          StartStateWatcher watcher, void* context)
      -> StartOutcome;
  static auto facts_of(const libchiaking::consoles::InstalledTitle& title)
      -> InstalledTitleFacts;
  static auto shelf_of(
      libchiaking::consoles::HardwareId console,
      std::span<const libchiaking::consoles::InstalledTitle> titles)
      -> ConsoleShelf;

 private:
  class StartStates final : public libchiaking::consoles::StartWatcher {
   public:
    StartStates(StartStateWatcher watcher, void* context) noexcept;
    void on_state(libchiaking::consoles::StartState state) override;

   private:
    StartStateWatcher watcher_;
    void* context_;
  };
};

struct GameInvitationFacts {
  std::string session_id;
  std::string invitation_id;
  Texts notification_ids;
  std::string inviter;
  std::string session_name;
  Texts title_ids;
  std::int64_t sent_ms;
  bool unread;
  std::uint32_t players;
  std::uint32_t max_players;
  libchiaking::consoles::GameInvitation::Joining joining;
  libchiaking::consoles::GameInvitation::Kind kind;
};

using GameInvitationList = std::vector<GameInvitationFacts>;

struct MessageAlertFacts {
  std::string sender;
  std::string group_id;
  std::string thread_id;
};

using InvitationArrived = void (*)(const GameInvitationFacts* invitation,
                                   void* context);
struct PartyAlertFacts {
  std::string sender;
  std::string session_id;
};

using MessageArrived = void (*)(const MessageAlertFacts* message,
                                void* context);
using PartyArrived = void (*)(const PartyAlertFacts* party, void* context);

/// How a request about an account's game invitations ended: answered,
/// unanswered or refused.
class GameInvitationsOutcome {
 public:
  /// The ways the request can end.
  enum class Kind : std::uint8_t {
    /// PSN answered, with the invitations when listing them.
    answered,
    /// PSN gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A request PSN answered.
  static auto answered(GameInvitationList value) -> GameInvitationsOutcome {
    return GameInvitationsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A request PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered value)
      -> GameInvitationsOutcome {
    return GameInvitationsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A request the bridge refused.
  static auto refused(ConsolesRefusal value) -> GameInvitationsOutcome {
    return GameInvitationsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the request ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The invitations, empty unless listing them; valid for `answered`.
  auto invitations() const -> GameInvitationList {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> ConsolesRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<GameInvitationList, libchiaking::users::Unanswered,
                            ConsolesRefusal>;

  explicit GameInvitationsOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class GameInvitationsBridge {
 public:
  static auto invitations(const Request& request, const Bytes& account_id)
      -> GameInvitationsOutcome;
  static auto join(const Request& request, const Bytes& account_id,
                   const std::string& session_id)
      -> std::optional<libchiaking::consoles::InvitationJoinFailure>;
  static auto join_party_on(const Request& request, const Bytes& account_id,
                            const Bytes& hardware_id,
                            const std::string& session_id)
      -> std::optional<libchiaking::consoles::InvitationJoinFailure>;
  static auto join_on(const Request& request, const Bytes& account_id,
                      const Bytes& hardware_id, const std::string& session_id)
      -> std::optional<libchiaking::consoles::InvitationJoinFailure>;
  static auto dismiss(const Request& request, const Bytes& account_id,
                      const Texts& notification_ids) -> GameInvitationsOutcome;
  static auto watch(const Request& request, const Bytes& account_id,
                    InvitationArrived invitation, MessageArrived message,
                    PartyArrived party, void* context)
      -> GameInvitationsOutcome;

 private:
  static auto facts_of(const libchiaking::consoles::GameInvitation& invitation)
      -> GameInvitationFacts;
  template <class Join>
  static auto joined_as(const Bytes& account_id, Join&& join)
      -> std::optional<libchiaking::consoles::InvitationJoinFailure>;

  class Arrivals final : public libchiaking::consoles::AlertWatcher {
   public:
    Arrivals(InvitationArrived invitation, MessageArrived message,
             PartyArrived party, void* context) noexcept;
    void on_invitation(
        const libchiaking::consoles::GameInvitation& invitation) override;
    void on_message(
        const libchiaking::consoles::MessageAlert& message) override;
    void on_party_invitation(
        const libchiaking::consoles::PartyInvitationAlert& party) override;

   private:
    InvitationArrived invitation_;
    MessageArrived message_;
    PartyArrived party_;
    void* context_;
  };
};

}  // namespace chiaki_bridge
