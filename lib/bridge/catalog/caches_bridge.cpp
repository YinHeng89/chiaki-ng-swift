#include <utility>

#include "account_ids.hpp"
#include "boundary.hpp"
#include "chiaki_bridge/caches.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

namespace catalog = libchiaking::catalog;

auto CachesBridge::summaries() -> SummariesOutcome {
  return Boundary::fenced(
      SummariesOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> SummariesOutcome {
        const auto opened = Opened::shared();
        return opened ? summaries_of(opened->chiaki())
                      : SummariesOutcome::refused(CatalogRefusal::core_closed);
      });
}

auto CachesBridge::entries(catalog::CacheId cache) -> EntriesOutcome {
  return Boundary::fenced(
      EntriesOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> EntriesOutcome {
        const auto opened = Opened::shared();
        return opened ? entries_of(opened->chiaki(), cache)
                      : EntriesOutcome::refused(CatalogRefusal::core_closed);
      });
}

auto CachesBridge::clear(catalog::CacheId cache) -> ClearOutcome {
  return Boundary::fenced(
      ClearOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> ClearOutcome {
        const auto opened = Opened::shared();
        return opened ? clear_of(opened->chiaki(), cache)
                      : ClearOutcome::refused(CatalogRefusal::core_closed);
      });
}

auto CachesBridge::clear_all() -> ClearOutcome {
  return Boundary::fenced(
      ClearOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> ClearOutcome {
        const auto opened = Opened::shared();
        return opened ? clear_all_of(opened->chiaki())
                      : ClearOutcome::refused(CatalogRefusal::core_closed);
      });
}

auto CachesBridge::summaries_of(libchiaking::ChiakiNg& core)
    -> SummariesOutcome {
  const auto held = core.caches();
  if (!held) {
    return SummariesOutcome::unanswered(
        CatalogBridge::unanswered_of(held.error()));
  }
  CacheSummaryList held_caches;
  for (const auto& summary : held.value()) {
    held_caches.push_back(
        CacheSummaryFacts{summary.id, summary.entries, summary.bytes});
  }
  return SummariesOutcome::answered(std::move(held_caches));
}

auto CachesBridge::entries_of(libchiaking::ChiakiNg& core,
                              catalog::CacheId cache) -> EntriesOutcome {
  const auto held = core.cache_entries(cache);
  if (!held) {
    return EntriesOutcome::unanswered(
        CatalogBridge::unanswered_of(held.error()));
  }
  CacheEntryList listed;
  for (const auto& entry : held.value()) {
    listed.push_back(entry_of(entry));
  }
  return EntriesOutcome::answered(std::move(listed));
}

auto CachesBridge::clear_of(libchiaking::ChiakiNg& core, catalog::CacheId cache)
    -> ClearOutcome {
  return cleared(core.clear_cache(cache));
}

auto CachesBridge::clear_all_of(libchiaking::ChiakiNg& core) -> ClearOutcome {
  return cleared(core.clear_caches());
}

auto CachesBridge::entry_of(const catalog::CacheEntry& entry)
    -> CacheEntryFacts {
  CacheEntryFacts facts{};
  facts.cache = entry.cache;
  if (entry.account) {
    facts.account_id = IdentifierBytes::of(*entry.account);
  }
  if (entry.locale) {
    facts.locale = entry.locale->text();
  }
  if (entry.product) {
    facts.product_id = entry.product->text();
  }
  if (entry.concept_id) {
    facts.concept_id = entry.concept_id->text();
  }
  if (entry.image) {
    facts.image_url = entry.image->url();
  }
  facts.bytes = entry.bytes;
  facts.stored_at_ms = Timestamp::milliseconds_of(entry.stored_at);
  if (entry.expires_at) {
    facts.expires_at_ms = Timestamp::milliseconds_of(*entry.expires_at);
  }
  return facts;
}

}  // namespace chiaki_bridge
