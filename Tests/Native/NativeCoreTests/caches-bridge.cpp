#include <array>
#include <cassert>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <libchiaking/chiaki_ng.hpp>
#include <libchiaking/platform/stock_providers.hpp>
#include <libchiaking/testing/in_memory_console_store.hpp>
#include <libchiaking/testing/in_memory_credential_store.hpp>
#include <libchiaking/testing/in_memory_record_store.hpp>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "chiaki_bridge/caches.hpp"
#include "runtime.hpp"

namespace {

auto& native_test_threading = chiaki_bridge::Runtime::process().threading();
auto& native_test_clock = chiaki_bridge::Runtime::process().clock();

namespace catalog = libchiaking::catalog;
namespace platform = libchiaking::platform;
namespace play = libchiaking::play;
namespace testing = libchiaking::testing;

class QuietDatacenters final : public play::DatacenterStore {
 public:
  [[nodiscard]] auto load(catalog::ServiceGeneration)
      -> libchiaking::Expected<std::vector<play::DatacenterMeasurement>,
                               Error> override {
    return std::vector<play::DatacenterMeasurement>{};
  }

  [[nodiscard]] auto save(catalog::ServiceGeneration,
                          std::span<const play::DatacenterMeasurement>)
      -> libchiaking::Expected<void, Error> override {
    return {};
  }
};

class Household {
 public:
  Household() {
    auto opened = libchiaking::ChiakiNg::open(
        platform_.factory(),
        libchiaking::ChiakiNg::Stores{credentials_, consoles_, datacenters_,
                                      nullptr, records});
    assert(opened);
    core_ = std::make_shared<libchiaking::ChiakiNg>(std::move(opened.value()));
  }

  auto core() const -> libchiaking::ChiakiNg& { return *core_; }

  void keep(std::string_view name, std::string_view text) {
    const auto record = platform::RecordName::parse(name);
    assert(record);
    assert(records.write_atomic(
        *record, std::as_bytes(std::span{text.data(), text.size()})));
  }

  testing::InMemoryRecordStore records{native_test_threading};

 private:
  platform::DefaultPlatform platform_;
  testing::InMemoryCredentialStore credentials_{native_test_threading};
  testing::InMemoryConsoleStore consoles_{native_test_threading};
  QuietDatacenters datacenters_;
  std::shared_ptr<libchiaking::ChiakiNg> core_;
};

using chiaki_bridge::CachesBridge;

class CachesBridgeFacts {
 public:
  static void every_cache_is_listed_with_its_count_and_size() {
    Household home;
    const auto empty = CachesBridge::summaries_of(home.core());
    assert(empty.kind() == chiaki_bridge::SummariesOutcome::Kind::answered);
    assert(empty.summaries().size() == catalog::every_cache.size());
    for (const auto& row : empty.summaries()) {
      assert(row.entries == 0 && row.bytes == 0);
    }

    home.keep("streamable/us-en", "{}");
    home.keep("included/en-us", "{}");
    home.keep("user/40/library", "{}");
    const auto held = CachesBridge::summaries_of(home.core());
    assert(held.kind() == chiaki_bridge::SummariesOutcome::Kind::answered);
    for (const auto id : catalog::every_cache) {
      const bool written = id == catalog::CacheId::streamable_lists ||
                           id == catalog::CacheId::included_titles ||
                           id == catalog::CacheId::libraries;
      const auto row = summary_of(held, id);
      assert(row.entries == (written ? 1U : 0U));
      assert(row.bytes == (written ? 2U : 0U));
    }
  }

  static void a_caches_entries_carry_their_size_and_stored_time() {
    Household home;
    const auto stored = std::chrono::system_clock::time_point{
        std::chrono::milliseconds{1'700'000'000'000}};
    home.records.modified_at = stored;
    home.keep("user/40/library", "{}");
    const auto seen =
        CachesBridge::entries_of(home.core(), catalog::CacheId::libraries);
    assert(seen.kind() == chiaki_bridge::EntriesOutcome::Kind::answered &&
           seen.entries().size() == 1);
    const auto row = seen.entries().front();
    assert(row.cache == catalog::CacheId::libraries);
    assert(row.bytes == 2);
    assert(row.stored_at_ms == 1'700'000'000'000);
    assert(!row.expires_at_ms && !row.account_id);
    assert(!row.locale && !row.product_id && !row.image_url && !row.concept_id);

    const auto other =
        CachesBridge::entries_of(home.core(), catalog::CacheId::images);
    assert(other.kind() == chiaki_bridge::EntriesOutcome::Kind::answered &&
           other.entries().empty());
  }

  static void one_cache_or_all_of_them_can_be_cleared() {
    Household home;
    home.keep("streamable/us-en", "{}");
    home.keep("included/en-us", "{}");
    home.keep("user/40/library", "{}");
    const auto one =
        CachesBridge::clear_of(home.core(), catalog::CacheId::libraries);
    assert(one.kind() == chiaki_bridge::ClearOutcome::Kind::answered);
    assert(home.records.names().size() == 2);
    const auto after = CachesBridge::summaries_of(home.core());
    assert(summary_of(after, catalog::CacheId::libraries).entries == 0);
    assert(summary_of(after, catalog::CacheId::streamable_lists).entries == 1);
    assert(CachesBridge::clear_all_of(home.core()).kind() ==
           chiaki_bridge::ClearOutcome::Kind::answered);
    assert(home.records.names().empty());
  }

  static void a_store_that_cannot_list_is_reported_as_storage() {
    Household home;
    home.records.fail_lists = true;
    const auto seen = CachesBridge::summaries_of(home.core());
    assert(seen.kind() == chiaki_bridge::SummariesOutcome::Kind::unanswered &&
           seen.why_unanswered().reason ==
               chiaki_bridge::CatalogReason::storage);
  }

  static void a_closed_core_answers_closed() {
    using chiaki_bridge::CatalogRefusal;
    assert(CachesBridge::summaries().refusal() == CatalogRefusal::core_closed);
    assert(CachesBridge::entries(catalog::CacheId::images).refusal() ==
           CatalogRefusal::core_closed);
    assert(CachesBridge::clear(catalog::CacheId::images).refusal() ==
           CatalogRefusal::core_closed);
    assert(CachesBridge::clear_all().refusal() == CatalogRefusal::core_closed);
  }

 private:
  static auto summary_of(const chiaki_bridge::SummariesOutcome& outcome,
                         catalog::CacheId id)
      -> chiaki_bridge::CacheSummaryFacts {
    for (const auto& row : outcome.summaries()) {
      if (row.cache == id) {
        return row;
      }
    }
    assert(false);
    return {};
  }
};

}  // namespace

int main() {
  CachesBridgeFacts::every_cache_is_listed_with_its_count_and_size();
  CachesBridgeFacts::a_caches_entries_carry_their_size_and_stored_time();
  CachesBridgeFacts::one_cache_or_all_of_them_can_be_cleared();
  CachesBridgeFacts::a_store_that_cannot_list_is_reported_as_storage();
  CachesBridgeFacts::a_closed_core_answers_closed();
  return 0;
}
