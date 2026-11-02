#include <array>
#include <cassert>
#include <chrono>
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "chiaki_bridge/catalog.hpp"

namespace {

namespace catalog = libchiaking::catalog;
using chiaki_bridge::TitleChecksBridge;

class GameDetailsFacts {
 public:
  static void full_details_cross_with_every_part() {
    const auto product =
        catalog::ProductId::parse("EP9000-PPSA01968_00-DEATHSTRANDINGEU");
    assert(product);
    catalog::GameDetails details{.product = *product,
                                 .locale = catalog::StoreLocale::english_us()};
    details.key_art = catalog::KeyArt::preferring_layers(
        catalog::LayeredArt::of(image("background.png"), image("hero.png"),
                                image("logo.png")),
        catalog::GameHubArt::of(image("cover.png"), image("logo.png")));
    assert(details.key_art);
    details.screenshots = {*image("one.jpg"), *image("two.jpg")};
    const auto trailer = catalog::TrailerRef::at(
        "https://vulcan.dl.playstation.net/trailer.mp4");
    assert(trailer);
    details.trailers = {*trailer};
    details.star_rating =
        catalog::StarRating{.average = 4.74,
                            .average_text = "4.74",
                            .ratings = 216539,
                            .percent_by_stars = {2, 1, 3, 8, 86}};
    details.age_rating = catalog::AgeRating{.authority = "PEGI",
                                            .name = "PEGI 16",
                                            .description = "Ages 16 and over",
                                            .icon = image("pegi.png"),
                                            .descriptors = {"Violence"}};
    details.publisher = "Sony Interactive Entertainment";
    details.released_at = catalog::GameDetails::Time{
        std::chrono::milliseconds{1'730'332'800'000}};
    details.genres = {"Role Playing Games", "Action"};

    const auto facts = TitleChecksBridge::details_of(details);
    assert(facts.background_url == url("background.png") &&
           facts.hero_url == url("hero.png") &&
           facts.logo_url == url("logo.png") && !facts.game_hub_cover_url);
    assert((facts.screenshot_urls ==
            std::vector<std::string>{url("one.jpg"), url("two.jpg")}));
    assert((facts.trailer_urls ==
            std::vector<std::string>{
                "https://vulcan.dl.playstation.net/trailer.mp4"}));
    assert(facts.star_average == 4.74 && facts.star_average_text == "4.74" &&
           facts.star_ratings == 216539);
    assert((facts.star_percent == std::vector{2, 1, 3, 8, 86}));
    assert(facts.age_authority == "PEGI" && facts.age_name == "PEGI 16" &&
           facts.age_icon_url == url("pegi.png"));
    assert((facts.age_descriptors == std::vector<std::string>{"Violence"}));
    assert(facts.publisher == "Sony Interactive Entertainment");
    assert(facts.released_ms == 1'730'332'800'000);
    assert((facts.genres ==
            std::vector<std::string>{"Role Playing Games", "Action"}));
  }

  static void bare_details_cross_with_nothing_invented() {
    const auto product =
        catalog::ProductId::parse("EP9000-PPSA01968_00-DEATHSTRANDINGEU");
    assert(product);
    const catalog::GameDetails details{
        .product = *product, .locale = catalog::StoreLocale::english_us()};
    const auto facts = TitleChecksBridge::details_of(details);
    assert(!facts.background_url && !facts.hero_url && !facts.logo_url &&
           !facts.game_hub_cover_url);
    assert(facts.screenshot_urls.empty() && facts.trailer_urls.empty() &&
           facts.genres.empty() && facts.age_descriptors.empty());
    assert(!facts.star_average && !facts.age_authority && !facts.released_ms);
    assert(facts.publisher.empty());
  }

  static void game_hub_art_crosses_as_a_cover_and_any_logo() {
    const auto grouped_under = catalog::ConceptId::parse("10000237");
    assert(grouped_under);
    catalog::GameDetails details{.concept_id = *grouped_under,
                                 .locale = catalog::StoreLocale::english_us()};
    details.key_art = catalog::KeyArt::preferring_layers(
        catalog::LayeredArt::of(image("background.png"), std::nullopt,
                                image("logo.png")),
        catalog::GameHubArt::of(image("cover.png"), image("logo.png")));
    assert(details.key_art);
    const auto branded = TitleChecksBridge::details_of(details);
    assert(branded.game_hub_cover_url == url("cover.png") &&
           branded.logo_url == url("logo.png") && !branded.background_url &&
           !branded.hero_url);

    details.key_art = catalog::KeyArt::preferring_layers(
        std::nullopt,
        catalog::GameHubArt::of(image("cover.png"), std::nullopt));
    const auto bare = TitleChecksBridge::details_of(details);
    assert(bare.game_hub_cover_url == url("cover.png") && !bare.logo_url);
  }

  static void a_closed_core_answers_closed() {
    const chiaki_bridge::Request unhurried;
    const chiaki_bridge::Bytes account{1, 2, 3, 4, 5, 6, 7, 8};
    using chiaki_bridge::CatalogRefusal;
    assert(TitleChecksBridge::image(unhurried,
                                    "https://image.api.playstation.com/a.png")
               .refusal() == CatalogRefusal::core_closed);
    assert(TitleChecksBridge::image(unhurried, "not an image").refusal() ==
           CatalogRefusal::invalid_image);
    assert(chiaki_bridge::CatalogBridge::my_games(unhurried, account, false,
                                                  nullptr, nullptr)
               .refusal() == CatalogRefusal::core_closed);
    assert(!chiaki_bridge::CatalogBridge::fetch_state(account));
    const auto cleared = TitleChecksBridge::clear_for_launch(
        unhurried, account, "EP9000-PPSA01234_00-0000000000000000", nullptr,
        nullptr);
    assert(cleared.kind() == chiaki_bridge::ClearanceOutcome::Kind::refused &&
           cleared.refusal() == CatalogRefusal::core_closed);
    TitleChecksBridge::release(nullptr);
  }

 private:
  static auto url(std::string_view name) -> std::string {
    return std::string{catalog::ImageRef::origins.front()} + std::string{name};
  }

  static auto image(std::string_view name) -> std::optional<catalog::ImageRef> {
    return catalog::ImageRef::at(url(name));
  }
};

}  // namespace

int main() {
  GameDetailsFacts::full_details_cross_with_every_part();
  GameDetailsFacts::bare_details_cross_with_nothing_invented();
  GameDetailsFacts::game_hub_art_crosses_as_a_cover_and_any_logo();
  GameDetailsFacts::a_closed_core_answers_closed();
  return 0;
}
