#include <algorithm>
#include <memory>
#include <type_traits>
#include <utility>
#include <variant>

#include "boundary.hpp"
#include "chiaki_bridge/catalog.hpp"
#include "cleared_launch.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

namespace catalog = libchiaking::catalog;

auto TitleChecksBridge::storefront(const Request& request,
                                   const Bytes& account_id,
                                   const std::string& product_id)
    -> StorefrontOutcome {
  return Boundary::fenced(
      StorefrontOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> StorefrontOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return StorefrontOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return StorefrontOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto product = catalog::ProductId::parse(product_id);
        if (!product) {
          return StorefrontOutcome::refused(CatalogRefusal::invalid_product);
        }
        const auto checked = opened->catalog().check_title_against_storefront(
            *user, *product, request.token());
        if (!checked) {
          return StorefrontOutcome::unanswered(
              CatalogBridge::unanswered_of(checked.error()));
        }
        StorefrontFacts answer{checked.value().streaming(),
                               checked.value().owned_per_store(),
                               checked.value().offers_library_add(),
                               std::nullopt, checked.value().notice()};
        if (checked.value().answered_product()) {
          answer.offers_trial = checked.value().offers_trial();
        }
        return StorefrontOutcome::answered(std::move(answer));
      });
}

auto TitleChecksBridge::store_page(const Request& request,
                                   const Bytes& account_id,
                                   const std::string& product_id)
    -> StorePageOutcome {
  return Boundary::fenced(
      StorePageOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> StorePageOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return StorePageOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return StorePageOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto product = catalog::ProductId::parse(product_id);
        if (!product) {
          return StorePageOutcome::refused(CatalogRefusal::invalid_product);
        }
        const auto page =
            opened->catalog().store_page_of(*user, *product, request.token());
        if (!page) {
          return StorePageOutcome::unanswered(
              CatalogBridge::unanswered_of(page.error()));
        }
        return StorePageOutcome::answered(page.value().url());
      });
}

auto TitleChecksBridge::clear_for_launch(const Request& request,
                                         const Bytes& account_id,
                                         const std::string& product_id,
                                         LaunchCheckWatcher watcher,
                                         void* context) -> ClearanceOutcome {
  return Boundary::fenced(
      ClearanceOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> ClearanceOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return ClearanceOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return ClearanceOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto product = catalog::ProductId::parse(product_id);
        if (!product) {
          return ClearanceOutcome::refused(CatalogRefusal::invalid_product);
        }
        const auto observer = [watcher, context](catalog::LaunchCheck check) {
          if (watcher != nullptr) {
            watcher(check, context);
          }
        };
        const auto verdict = opened->catalog().clear_for_launch(
            *user, *product, request.token(), observer);
        if (const auto* refused = verdict.refusal()) {
          LaunchDeclineFacts decline{refused->kind(), std::nullopt,
                                     std::string{refused->notice()},
                                     std::nullopt};
          if (const auto time = refused->time()) {
            decline.time_ms = Timestamp::milliseconds_of(*time);
          }
          if (const auto cause = refused->cause()) {
            decline.cause = CatalogBridge::unanswered_of(*cause);
          }
          return ClearanceOutcome::declined(std::move(decline));
        }
        if (const auto* launch = verdict.cleared_launch()) {
          return ClearanceOutcome::cleared(
              ClearedFacts{std::make_unique<ClearedLaunch>(*launch).release()});
        }
        return ClearanceOutcome::cleared(ClearedFacts{nullptr});
      });
}

void TitleChecksBridge::release(ClearedLaunch* cleared) { delete cleared; }

auto TitleChecksBridge::details_of(const catalog::GameDetails& details)
    -> GameDetailsFacts {
  GameDetailsFacts facts{};
  if (const auto& art = details.key_art) {
    std::visit(
        [&facts](const auto& shown) {
          using Shown = std::decay_t<decltype(shown)>;
          if constexpr (std::is_same_v<Shown, catalog::LayeredArt>) {
            facts.background_url = shown.background.url();
            facts.hero_url = shown.hero.url();
            facts.logo_url = shown.logo.url();
          } else {
            facts.game_hub_cover_url = shown.cover.url();
            if (shown.logo) {
              facts.logo_url = shown.logo->url();
            }
          }
        },
        art->choice());
  }
  for (const auto& screenshot : details.screenshots) {
    facts.screenshot_urls.push_back(screenshot.url());
  }
  for (const auto& trailer : details.trailers) {
    facts.trailer_urls.push_back(trailer.url());
  }
  if (const auto& stars = details.star_rating) {
    facts.star_average = stars->average;
    facts.star_average_text = stars->average_text;
    facts.star_ratings = stars->ratings;
    facts.star_percent.assign(stars->percent_by_stars.begin(),
                              stars->percent_by_stars.end());
  }
  if (const auto& age = details.age_rating) {
    facts.age_authority = age->authority;
    facts.age_name = age->name;
    facts.age_description = age->description;
    if (age->icon) {
      facts.age_icon_url = age->icon->url();
    }
    facts.age_descriptors = age->descriptors;
  }
  facts.publisher = details.publisher;
  if (const auto& released = details.released_at) {
    facts.released_ms = Timestamp::milliseconds_of(*released);
  }
  facts.genres = details.genres;
  return facts;
}

auto TitleChecksBridge::details(const Request& request, const Bytes& account_id,
                                const std::string& product_id)
    -> DetailsOutcome {
  return Boundary::fenced(
      DetailsOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> DetailsOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return DetailsOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return DetailsOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto product = catalog::ProductId::parse(product_id);
        if (!product) {
          return DetailsOutcome::refused(CatalogRefusal::invalid_product);
        }
        const auto shown =
            opened->catalog().details_of(*user, *product, request.token());
        if (!shown) {
          return DetailsOutcome::unanswered(
              CatalogBridge::unanswered_of(shown.error()));
        }
        return DetailsOutcome::answered(details_of(shown.value()));
      });
}

auto TitleChecksBridge::details_by_concept(const Request& request,
                                           const Bytes& account_id,
                                           const std::string& concept_id)
    -> DetailsOutcome {
  return Boundary::fenced(
      DetailsOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> DetailsOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return DetailsOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return DetailsOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto grouped_under = catalog::ConceptId::parse(concept_id);
        if (!grouped_under) {
          return DetailsOutcome::refused(CatalogRefusal::invalid_concept);
        }
        const auto shown = opened->catalog().details_of(*user, *grouped_under,
                                                        request.token());
        if (!shown) {
          return DetailsOutcome::unanswered(
              CatalogBridge::unanswered_of(shown.error()));
        }
        return DetailsOutcome::answered(details_of(shown.value()));
      });
}

auto TitleChecksBridge::image(const Request& request, const std::string& url)
    -> ImageOutcome {
  return Boundary::fenced(
      ImageOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> ImageOutcome {
        const auto image = catalog::ImageRef::at(url);
        if (!image) {
          return ImageOutcome::refused(CatalogRefusal::invalid_image);
        }
        const auto opened = Opened::shared();
        if (!opened) {
          return ImageOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto held = opened->catalog().image_of(*image, request.token());
        if (!held) {
          return ImageOutcome::unanswered(
              CatalogBridge::unanswered_of(held.error()));
        }
        const auto& held_bytes = held.value();
        Bytes image_bytes;
        image_bytes.reserve(held_bytes.size());
        for (const auto byte : held_bytes) {
          image_bytes.push_back(static_cast<std::uint8_t>(byte));
        }
        return ImageOutcome::answered(std::move(image_bytes));
      });
}

}  // namespace chiaki_bridge
