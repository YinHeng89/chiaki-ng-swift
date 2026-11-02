#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <libchiaking/catalog.hpp>
#include <libchiaking/users.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

class ClearedLaunch;

enum class CatalogRefusal : std::uint8_t {
  core_closed,
  unknown_user,
  invalid_product,
  invalid_concept,
  invalid_image,
};

enum class CatalogReason : std::uint8_t {
  cancelled,
  user,
  unavailable,
  rejected,
  region_unsupported,
  malformed,
  not_listed,
  storage,
  ownership_unknown,
  restriction_list_unavailable,
};

struct CatalogUnanswered {
  CatalogReason reason;
  std::uint16_t http_status;
  bool needs_sign_in;
};

enum class ReleaseKind : std::uint8_t {
  unrestricted,
  scheduled,
  unannounced,
};

struct BundledGameFacts {
  std::optional<std::string> product_id;
  std::string entitlement_id;
  bool owned;
  std::optional<libchiaking::catalog::LaunchRefusal::Kind> launch_refusal;
};

using BundledGameList = std::vector<BundledGameFacts>;

struct GameFacts {
  std::string product_id;
  std::string name;
  std::string cover_url;
  std::string landscape_cover_url;
  std::optional<std::string> concept_id;
  std::optional<std::string> concept_url;
  std::string launch_identifier;
  std::optional<std::string> ownership_id;
  bool is_trial;
  bool trial_ended;
  bool is_play_first_trial;
  libchiaking::catalog::TrialOffer trial_offer;
  libchiaking::catalog::Platform platform;
  libchiaking::catalog::ServiceGeneration service;
  libchiaking::catalog::OwnershipState ownership;
  libchiaking::catalog::Standing standing;
  bool included;
  bool visible;
  std::optional<libchiaking::catalog::HideReason> hide_reason;
  ReleaseKind release;
  std::optional<std::int64_t> release_ms;
  std::optional<libchiaking::catalog::LaunchRefusal::Kind> launch_refusal;
  bool needs_library_add;
  bool can_be_added_to_library;
  bool needs_storefront_check;
  bool is_bundle;
  bool bundle_owned;
  BundledGameList children;
  std::optional<std::string> other_version_product_id;
  bool leads_versions;
};

using GameList = std::vector<GameFacts>;

/// How listing an account's games ended: answered, unanswered or refused.
class GamesOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// The catalog listed the games.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Games the catalog listed.
  static auto answered(GameList value) -> GamesOutcome {
    return GamesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A listing the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> GamesOutcome {
    return GamesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A listing the bridge refused.
  static auto refused(CatalogRefusal value) -> GamesOutcome {
    return GamesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The games, visible ones first; valid for `answered`.
  auto games() const -> GameList {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<GameList, CatalogUnanswered, CatalogRefusal>;

  explicit GamesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

struct PlayedFacts {
  std::string product_id;
  std::int64_t last_played_ms;
};

using PlayedList = std::vector<PlayedFacts>;

/// How listing an account's recently played games ended: answered,
/// unanswered or refused.
class PlayedOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// The catalog listed the games.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Games the catalog listed.
  static auto answered(PlayedList value) -> PlayedOutcome {
    return PlayedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A listing the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> PlayedOutcome {
    return PlayedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A listing the bridge refused.
  static auto refused(CatalogRefusal value) -> PlayedOutcome {
    return PlayedOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The games; valid for `answered`.
  auto played() const -> PlayedList {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<PlayedList, CatalogUnanswered, CatalogRefusal>;

  explicit PlayedOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// What a fresh ownership check found.
struct OwnershipFacts {
  /// The answer.
  libchiaking::catalog::OwnershipAnswer::Kind answer;
  /// The game as the catalog now has it, when it has one.
  std::optional<GameFacts> game;
};

/// How checking the ownership of a game again ended: answered, unanswered
/// or refused.
class OwnershipOutcome {
 public:
  /// The ways the check can end.
  enum class Kind : std::uint8_t {
    /// The catalog answered.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A check the catalog answered.
  static auto answered(OwnershipFacts value) -> OwnershipOutcome {
    return OwnershipOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A check the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> OwnershipOutcome {
    return OwnershipOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A check the bridge refused.
  static auto refused(CatalogRefusal value) -> OwnershipOutcome {
    return OwnershipOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the check ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// What the check found; valid for `answered`.
  auto ownership() const -> OwnershipFacts {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<OwnershipFacts, CatalogUnanswered, CatalogRefusal>;

  explicit OwnershipOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

struct ExplanationStepFacts {
  libchiaking::catalog::Explanation::Rule rule;
  libchiaking::catalog::Explanation::Outcome outcome;
  bool hides;
  std::optional<std::string> product_id;
  std::optional<std::string> ownership_id;
  std::optional<std::string> title_number;
  std::optional<libchiaking::users::Tier> tier;
};

using ExplanationSteps = std::vector<ExplanationStepFacts>;

struct ExplanationFacts {
  bool listed;
  ExplanationSteps steps;
};

struct FetchFacts {
  bool from_account_service;
  bool complete;
  std::int64_t fetched_at_ms;
  std::size_t ps_now_titles;
  std::optional<std::size_t> copies_asked;
  std::optional<std::size_t> copies_answered;
  std::size_t without_a_covered_copy;
  std::size_t ps_cloud_titles;
  std::optional<std::string> audience_country;
  std::optional<std::string> audience_language;
  std::optional<int> audience_age;
  std::optional<std::int64_t> premium_category_fetched_at_ms;
  std::optional<std::size_t> premium_category_titles;
  std::optional<libchiaking::catalog::LibraryState> library;
  std::optional<std::int64_t> library_fetched_at_ms;
  std::size_t library_records;
  std::optional<libchiaking::users::Tier> tier;
};

using PassedSteps = std::vector<libchiaking::catalog::PassedStep>;

struct FetchStateFacts {
  std::uint64_t attempt;
  libchiaking::catalog::FetchStep step;
  std::optional<libchiaking::catalog::FetchActivity> activity;
  std::uint32_t pages_read;
  std::optional<std::uint32_t> pages_expected;
  std::optional<std::string> time_server;
  PassedSteps passed;
  std::optional<CatalogUnanswered> failure;
  bool running;
};

using FetchStateWatcher = void (*)(const FetchStateFacts* state, void* context);

/// What an account may stream from the cloud.
struct CloudAccessFacts {
  /// Whether the account may stream.
  libchiaking::catalog::CloudAccess::Availability availability;
  /// How many titles the account may stream, when listed.
  std::optional<std::size_t> title_count;
  /// Whether the listing was read to its end.
  bool complete;
  /// Whether the listing came from the account service.
  bool from_account_service;
};

/// How checking cloud access ended: answered, unanswered or refused.
class CloudAccessOutcome {
 public:
  /// The ways the check can end.
  enum class Kind : std::uint8_t {
    /// The catalog answered.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A check the catalog answered.
  static auto answered(CloudAccessFacts value) -> CloudAccessOutcome {
    return CloudAccessOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A check the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> CloudAccessOutcome {
    return CloudAccessOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A check the bridge refused.
  static auto refused(CatalogRefusal value) -> CloudAccessOutcome {
    return CloudAccessOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the check ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// What the account may stream; valid for `answered`.
  auto access() const -> CloudAccessFacts {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<CloudAccessFacts, CatalogUnanswered, CatalogRefusal>;

  explicit CloudAccessOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

struct CaptureFileFacts {
  std::string url;
  std::string file_type;
  std::uint64_t size;
};

/// How finding a cloud capture ended: answered, unanswered or refused.
class CaptureFileOutcome {
 public:
  /// The ways the lookup can end.
  enum class Kind : std::uint8_t {
    /// The catalog found the capture.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A capture the catalog found.
  static auto answered(CaptureFileFacts value) -> CaptureFileOutcome {
    return CaptureFileOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A lookup the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> CaptureFileOutcome {
    return CaptureFileOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A lookup the bridge refused.
  static auto refused(CatalogRefusal value) -> CaptureFileOutcome {
    return CaptureFileOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the lookup ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The capture; valid for `answered`.
  auto file() const -> CaptureFileFacts {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<CaptureFileFacts, CatalogUnanswered, CatalogRefusal>;

  explicit CaptureFileOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How reading the cloud capture download setting ended: answered,
/// unanswered or refused.
class CaptureDownloadOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// The catalog read the setting.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A setting the catalog read.
  static auto answered(bool value) -> CaptureDownloadOutcome {
    return CaptureDownloadOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A read the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> CaptureDownloadOutcome {
    return CaptureDownloadOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A read the bridge refused.
  static auto refused(CatalogRefusal value) -> CaptureDownloadOutcome {
    return CaptureDownloadOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// Whether captures download; valid for `answered`.
  auto downloads() const -> bool {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<bool, CatalogUnanswered, CatalogRefusal>;

  explicit CaptureDownloadOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class CatalogBridge {
 public:
  static auto my_games(const Request& request, const Bytes& account_id,
                       bool start_over, FetchStateWatcher watcher,
                       void* context) -> GamesOutcome;
  static auto fetch_state(const Bytes& account_id)
      -> std::optional<FetchStateFacts>;
  static auto recently_played(const Request& request, const Bytes& account_id)
      -> PlayedOutcome;
  static auto recheck_ownership(const Request& request, const Bytes& account_id,
                                const std::string& product_id)
      -> OwnershipOutcome;
  static auto explain(const Bytes& account_id, const std::string& product_id)
      -> std::optional<ExplanationFacts>;
  static auto how_fetched(const Bytes& account_id) -> std::optional<FetchFacts>;
  static auto held_trials(const Bytes& account_id) -> GameList;
  static auto cloud_access(const Request& request, const Bytes& account_id)
      -> CloudAccessOutcome;
  static auto cloud_capture(const Request& request, const Bytes& account_id,
                            const std::string& gallery_id)
      -> CaptureFileOutcome;
  static auto cloud_capture_download(const Request& request,
                                     const Bytes& account_id)
      -> CaptureDownloadOutcome;
  template <class Reason>
  static auto unanswered_of(
      const libchiaking::catalog::CallFailure<Reason>& failure)
      -> CatalogUnanswered {
    return CatalogUnanswered{reason_of(failure.reason()), failure.http_status(),
                             failure.needs_sign_in()};
  }
  static auto game_of(libchiaking::users::PsUser& user,
                      const libchiaking::catalog::MyGame& game,
                      libchiaking::catalog::Catalog& catalog) -> GameFacts;

 private:
  template <class Reason>
  static constexpr auto reason_of(Reason reason) noexcept -> CatalogReason {
    using enum CatalogReason;
    if constexpr (requires { Reason::cancelled; })
      if (reason == Reason::cancelled) return cancelled;
    if constexpr (requires { Reason::user; })
      if (reason == Reason::user) return user;
    if constexpr (requires { Reason::rejected; })
      if (reason == Reason::rejected) return rejected;
    if constexpr (requires { Reason::region_unsupported; })
      if (reason == Reason::region_unsupported) return region_unsupported;
    if constexpr (requires { Reason::malformed; })
      if (reason == Reason::malformed) return malformed;
    if constexpr (requires { Reason::not_listed; })
      if (reason == Reason::not_listed) return not_listed;
    if constexpr (requires { Reason::storage; })
      if (reason == Reason::storage) return storage;
    if constexpr (requires { Reason::ownership_unknown; })
      if (reason == Reason::ownership_unknown) return ownership_unknown;
    if constexpr (requires { Reason::restriction_list_unavailable; })
      if (reason == Reason::restriction_list_unavailable)
        return restriction_list_unavailable;
    return unavailable;
  }
  static auto refusal_of(const libchiaking::catalog::LaunchVerdict& verdict)
      -> std::optional<libchiaking::catalog::LaunchRefusal::Kind>;
  static auto state_of(const libchiaking::catalog::FetchState& state)
      -> FetchStateFacts;
};

/// What the storefront says of a title.
struct StorefrontFacts {
  /// Whether the title streams.
  libchiaking::catalog::StorefrontAnswer::Streaming streaming;
  /// Whether the store says the account owns it.
  bool owned_per_store;
  /// Whether the store offers to add it to the library.
  bool offers_library_add;
  /// Whether the store offers a trial, when it answered for the product.
  std::optional<bool> offers_trial;
  /// The store's notice, empty when there is none.
  std::string notice;
};

/// How checking a title against the storefront ended: answered, unanswered
/// or refused.
class StorefrontOutcome {
 public:
  /// The ways the check can end.
  enum class Kind : std::uint8_t {
    /// The storefront answered.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A check the storefront answered.
  static auto answered(StorefrontFacts value) -> StorefrontOutcome {
    return StorefrontOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A check the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> StorefrontOutcome {
    return StorefrontOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A check the bridge refused.
  static auto refused(CatalogRefusal value) -> StorefrontOutcome {
    return StorefrontOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the check ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// What the storefront says; valid for `answered`.
  auto storefront() const -> StorefrontFacts {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<StorefrontFacts, CatalogUnanswered, CatalogRefusal>;

  explicit StorefrontOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How finding a title's store page ended: answered, unanswered or refused.
class StorePageOutcome {
 public:
  /// The ways the lookup can end.
  enum class Kind : std::uint8_t {
    /// The catalog found the page.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A page the catalog found.
  static auto answered(std::string value) -> StorePageOutcome {
    return StorePageOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A lookup the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> StorePageOutcome {
    return StorePageOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A lookup the bridge refused.
  static auto refused(CatalogRefusal value) -> StorePageOutcome {
    return StorePageOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the lookup ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The page address; valid for `answered`.
  auto url() const -> std::string {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<std::string, CatalogUnanswered, CatalogRefusal>;

  explicit StorePageOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

using LaunchCheckWatcher = void (*)(libchiaking::catalog::LaunchCheck check,
                                    void* context);

/// A launch the checks cleared.
struct ClearedFacts {
  /// The cleared launch, which the caller releases, or null.
  ClearedLaunch* launch;
};

/// Why the launch checks refused a title.
struct LaunchDeclineFacts {
  /// The reason.
  libchiaking::catalog::LaunchRefusal::Kind kind;
  /// When the title becomes playable, in milliseconds since the epoch, when
  /// known.
  std::optional<std::int64_t> time_ms;
  /// The notice to show, empty when there is none.
  std::string notice;
  /// The request that went unanswered behind the refusal, when one did.
  std::optional<CatalogUnanswered> cause;
};

/// How the launch checks ended: cleared, declined or refused.
class ClearanceOutcome {
 public:
  /// The ways the checks can end.
  enum class Kind : std::uint8_t {
    /// The title may launch.
    cleared,
    /// The checks refused the title.
    declined,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A launch the checks cleared.
  static auto cleared(ClearedFacts value) -> ClearanceOutcome {
    return ClearanceOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::cleared)>,
             std::move(value)}};
  }

  /// A launch the checks refused.
  static auto declined(LaunchDeclineFacts value) -> ClearanceOutcome {
    return ClearanceOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::declined)>,
             std::move(value)}};
  }

  /// Checks the bridge refused.
  static auto refused(CatalogRefusal value) -> ClearanceOutcome {
    return ClearanceOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the checks ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The cleared launch; valid for `cleared`.
  auto clearance() const -> ClearedFacts {
    return std::get<std::to_underlying(Kind::cleared)>(held_);
  }

  /// Why the checks refused; valid for `declined`.
  auto decline() const -> LaunchDeclineFacts {
    return std::get<std::to_underlying(Kind::declined)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<ClearedFacts, LaunchDeclineFacts, CatalogRefusal>;

  explicit ClearanceOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

using StarPercents = std::vector<int>;

struct GameDetailsFacts {
  std::optional<std::string> background_url;
  std::optional<std::string> hero_url;
  std::optional<std::string> logo_url;
  std::optional<std::string> game_hub_cover_url;
  Texts screenshot_urls;
  Texts trailer_urls;
  std::optional<double> star_average;
  std::string star_average_text;
  std::int64_t star_ratings;
  StarPercents star_percent;
  std::optional<std::string> age_authority;
  std::string age_name;
  std::string age_description;
  std::optional<std::string> age_icon_url;
  Texts age_descriptors;
  std::string publisher;
  std::optional<std::int64_t> released_ms;
  Texts genres;
};

/// How reading a title's detail page ended: answered, unanswered or refused.
class DetailsOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// The catalog returned the details.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Details the catalog returned.
  static auto answered(GameDetailsFacts value) -> DetailsOutcome {
    return DetailsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A read the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> DetailsOutcome {
    return DetailsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A read the bridge refused.
  static auto refused(CatalogRefusal value) -> DetailsOutcome {
    return DetailsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The details; valid for `answered`.
  auto details() const -> GameDetailsFacts {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<GameDetailsFacts, CatalogUnanswered, CatalogRefusal>;

  explicit DetailsOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How fetching an image ended: answered, unanswered or refused.
class ImageOutcome {
 public:
  /// The ways the fetch can end.
  enum class Kind : std::uint8_t {
    /// The catalog returned the image.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// An image the catalog returned.
  static auto answered(Bytes value) -> ImageOutcome {
    return ImageOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A fetch the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> ImageOutcome {
    return ImageOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A fetch the bridge refused.
  static auto refused(CatalogRefusal value) -> ImageOutcome {
    return ImageOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the fetch ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The image bytes; valid for `answered`.
  auto bytes() const -> Bytes {
    return std::get<std::to_underlying(Kind::answered)>(held_);
  }

  /// Why the catalog gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> CatalogUnanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> CatalogRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case = std::variant<Bytes, CatalogUnanswered, CatalogRefusal>;

  explicit ImageOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class TitleChecksBridge {
 public:
  static auto storefront(const Request& request, const Bytes& account_id,
                         const std::string& product_id) -> StorefrontOutcome;
  static auto store_page(const Request& request, const Bytes& account_id,
                         const std::string& product_id) -> StorePageOutcome;
  static auto clear_for_launch(const Request& request, const Bytes& account_id,
                               const std::string& product_id,
                               LaunchCheckWatcher watcher, void* context)
      -> ClearanceOutcome;
  static void release(ClearedLaunch* cleared);
  static auto details(const Request& request, const Bytes& account_id,
                      const std::string& product_id) -> DetailsOutcome;
  static auto details_by_concept(const Request& request,
                                 const Bytes& account_id,
                                 const std::string& concept_id)
      -> DetailsOutcome;
  static auto image(const Request& request, const std::string& url)
      -> ImageOutcome;
  static auto details_of(const libchiaking::catalog::GameDetails& details)
      -> GameDetailsFacts;
};

}  // namespace chiaki_bridge
