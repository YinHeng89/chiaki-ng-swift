#pragma once

#include <cstddef>
#include <cstdint>
#include <libchiaking/catalog.hpp>
#include <libchiaking/chiaki_ng.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "catalog.hpp"
#include "core.hpp"

namespace chiaki_bridge {

struct CacheSummaryFacts {
  libchiaking::catalog::CacheId cache;
  std::size_t entries;
  std::uint64_t bytes;
};

using CacheSummaryList = std::vector<CacheSummaryFacts>;

/// How summarising the caches ended: answered, unanswered or refused.
class SummariesOutcome {
 public:
  /// The ways the summary can end.
  enum class Kind : std::uint8_t {
    /// The core summarised the caches.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A summary the core made.
  static auto answered(CacheSummaryList value) -> SummariesOutcome {
    return SummariesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A summary the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> SummariesOutcome {
    return SummariesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A summary the bridge refused.
  static auto refused(CatalogRefusal value) -> SummariesOutcome {
    return SummariesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the summary ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// Each cache with its size; valid for `answered`.
  auto summaries() const -> CacheSummaryList {
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
      std::variant<CacheSummaryList, CatalogUnanswered, CatalogRefusal>;

  explicit SummariesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

struct CacheEntryFacts {
  libchiaking::catalog::CacheId cache;
  std::optional<Bytes> account_id;
  std::optional<std::string> locale;
  std::optional<std::string> product_id;
  std::optional<std::string> concept_id;
  std::optional<std::string> image_url;
  std::uint64_t bytes;
  std::int64_t stored_at_ms;
  std::optional<std::int64_t> expires_at_ms;
};

using CacheEntryList = std::vector<CacheEntryFacts>;

/// How listing a cache's entries ended: answered, unanswered or refused.
class EntriesOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// The core listed the entries.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// Entries the core listed.
  static auto answered(CacheEntryList value) -> EntriesOutcome {
    return EntriesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>,
             std::move(value)}};
  }

  /// A listing the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> EntriesOutcome {
    return EntriesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A listing the bridge refused.
  static auto refused(CatalogRefusal value) -> EntriesOutcome {
    return EntriesOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The entries; valid for `answered`.
  auto entries() const -> CacheEntryList {
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
  using Case = std::variant<CacheEntryList, CatalogUnanswered, CatalogRefusal>;

  explicit EntriesOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How clearing caches ended: answered, unanswered or refused.
class ClearOutcome {
 public:
  /// The ways the clearing can end.
  enum class Kind : std::uint8_t {
    /// The caches were cleared.
    answered,
    /// The catalog gave no answer.
    unanswered,
    /// The bridge refused before the core ran.
    refused,
  };

  /// A clearing the core made.
  static auto answered() -> ClearOutcome {
    return ClearOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::answered)>}};
  }

  /// A clearing the catalog did not answer.
  static auto unanswered(CatalogUnanswered value) -> ClearOutcome {
    return ClearOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A clearing the bridge refused.
  static auto refused(CatalogRefusal value) -> ClearOutcome {
    return ClearOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the clearing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
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
  using Case = std::variant<std::monostate, CatalogUnanswered, CatalogRefusal>;

  explicit ClearOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

class CachesBridge {
 public:
  static auto summaries() -> SummariesOutcome;
  static auto entries(libchiaking::catalog::CacheId cache) -> EntriesOutcome;
  static auto clear(libchiaking::catalog::CacheId cache) -> ClearOutcome;
  static auto clear_all() -> ClearOutcome;

  static auto summaries_of(libchiaking::ChiakiNg& core) -> SummariesOutcome;
  static auto entries_of(libchiaking::ChiakiNg& core,
                         libchiaking::catalog::CacheId cache) -> EntriesOutcome;
  static auto clear_of(libchiaking::ChiakiNg& core,
                       libchiaking::catalog::CacheId cache) -> ClearOutcome;
  static auto clear_all_of(libchiaking::ChiakiNg& core) -> ClearOutcome;

 private:
  static auto entry_of(const libchiaking::catalog::CacheEntry& entry)
      -> CacheEntryFacts;
  template <class Reason>
  static auto cleared(const libchiaking::Expected<
                      void, libchiaking::catalog::CallFailure<Reason>>& done)
      -> ClearOutcome {
    if (!done) {
      return ClearOutcome::unanswered(
          CatalogBridge::unanswered_of(done.error()));
    }
    return ClearOutcome::answered();
  }
};

}  // namespace chiaki_bridge
