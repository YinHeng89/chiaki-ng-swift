#include <chrono>
#include <utility>

#include "boundary.hpp"
#include "chiaki_bridge/catalog.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

namespace catalog = libchiaking::catalog;

auto CatalogBridge::refusal_of(const catalog::LaunchVerdict& verdict)
    -> std::optional<catalog::LaunchRefusal::Kind> {
  if (const auto* refused = verdict.refusal()) {
    return refused->kind();
  }
  return std::nullopt;
}

auto CatalogBridge::game_of(libchiaking::users::PsUser& user,
                            const catalog::MyGame& game,
                            catalog::Catalog& catalog) -> GameFacts {
  const auto& title = game.title();
  const auto release = game.release();
  GameFacts facts{};
  facts.product_id = game.product_id().text();
  facts.name = title.name();
  facts.cover_url = title.cover_url();
  facts.landscape_cover_url = title.landscape_cover_url();
  if (title.concept_id()) {
    facts.concept_id = title.concept_id()->text();
  }
  if (title.concept_page()) {
    facts.concept_url = title.concept_page()->url();
  }
  facts.launch_identifier = game.launch_identifier().text();
  if (game.ownership()) {
    facts.ownership_id = game.ownership()->id().text();
    facts.is_trial =
        title.service() == catalog::ServiceGeneration::ps5_cloud &&
        game.ownership()->held_as() == catalog::HeldAs::trial_access;
    facts.trial_ended = facts.is_trial && game.ownership()->trial_ended();
    facts.is_play_first_trial =
        facts.is_trial && game.ownership()->is_play_first_trial();
  }
  facts.trial_offer = game.trial_offer();
  facts.platform = title.platform();
  facts.service = title.service();
  facts.ownership = game.ownership_state();
  facts.standing = game.standing();
  facts.included = game.inclusion().is_included();
  facts.visible = game.is_visible();
  facts.hide_reason = game.visibility().hide_reason();
  if (release.is_unrestricted()) {
    facts.release = ReleaseKind::unrestricted;
  } else if (release.is_unannounced()) {
    facts.release = ReleaseKind::unannounced;
  } else {
    facts.release = ReleaseKind::scheduled;
  }
  if (const auto time = release.time()) {
    facts.release_ms = Timestamp::milliseconds_of(*time);
  }
  facts.launch_refusal =
      refusal_of(catalog.can_launch(user, game.product_id()));
  facts.needs_library_add = game.needs_library_add();
  facts.can_be_added_to_library = game.can_be_added_to_library();
  facts.needs_storefront_check = game.needs_storefront_check();
  facts.is_bundle = game.is_bundle();
  facts.bundle_owned = game.is_bundle_owned();
  for (const auto& child : game.children()) {
    BundledGameFacts bundled{};
    if (child.product) {
      bundled.product_id = child.product->text();
      bundled.launch_refusal =
          refusal_of(catalog.can_launch(user, *child.product));
    }
    bundled.entitlement_id = child.entitlement.text();
    bundled.owned = child.owned;
    facts.children.push_back(std::move(bundled));
  }
  if (const auto& other = game.other_version()) {
    facts.other_version_product_id = other->product.text();
    facts.leads_versions = other->leads;
  }
  return facts;
}

auto CatalogBridge::state_of(const catalog::FetchState& state)
    -> FetchStateFacts {
  FetchStateFacts facts{};
  facts.attempt = state.attempt();
  facts.step = state.step();
  facts.activity = state.activity();
  facts.pages_read = state.pages_read();
  facts.pages_expected = state.pages_expected();
  facts.time_server = state.time_server();
  facts.passed.assign(state.passed().begin(), state.passed().end());
  if (const auto& failure = state.failure()) {
    facts.failure = unanswered_of(*failure);
  }
  facts.running = state.is_running();
  return facts;
}

auto CatalogBridge::fetch_state(const Bytes& account_id)
    -> std::optional<FetchStateFacts> {
  return Boundary::fenced(
      std::optional<FetchStateFacts>{},
      [&]() -> std::optional<FetchStateFacts> {
        const auto opened = Opened::shared();
        if (!opened) {
          return std::nullopt;
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return std::nullopt;
        }
        return state_of(opened->catalog().fetch_state(*user));
      });
}

auto CatalogBridge::my_games(const Request& request, const Bytes& account_id,
                             bool start_over, FetchStateWatcher watcher,
                             void* context) -> GamesOutcome {
  return Boundary::fenced(
      GamesOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> GamesOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return GamesOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return GamesOutcome::refused(CatalogRefusal::unknown_user);
        }
        if (start_over) {
          opened->catalog().start_over(*user);
        }
        const catalog::FetchObserver observer =
            [watcher, context](const catalog::FetchState& state) {
              if (watcher != nullptr) {
                const auto facts = state_of(state);
                watcher(&facts, context);
              }
            };
        const auto games = opened->catalog().process_library_and_list(
            *user, request.token(), observer);
        if (!games) {
          return GamesOutcome::unanswered(unanswered_of(games.error()));
        }
        const auto& listed = *games.value();
        GameList found;
        for (const auto& game : listed.visible()) {
          found.push_back(game_of(*user, game, opened->catalog()));
        }
        for (const auto& game : listed.hidden()) {
          found.push_back(game_of(*user, game, opened->catalog()));
        }
        return GamesOutcome::answered(std::move(found));
      });
}

auto CatalogBridge::recently_played(const Request& request,
                                    const Bytes& account_id) -> PlayedOutcome {
  return Boundary::fenced(
      PlayedOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> PlayedOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return PlayedOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return PlayedOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto played =
            opened->catalog().recently_played(*user, request.token());
        if (!played) {
          return PlayedOutcome::unanswered(unanswered_of(played.error()));
        }
        PlayedList recent;
        for (const auto& game : played.value()) {
          recent.push_back(
              PlayedFacts{game.product.text(),
                          Timestamp::milliseconds_of(game.last_played)});
        }
        return PlayedOutcome::answered(std::move(recent));
      });
}

auto CatalogBridge::recheck_ownership(const Request& request,
                                      const Bytes& account_id,
                                      const std::string& product_id)
    -> OwnershipOutcome {
  return Boundary::fenced(
      OwnershipOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> OwnershipOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return OwnershipOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return OwnershipOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto product = catalog::ProductId::parse(product_id);
        if (!product) {
          return OwnershipOutcome::refused(CatalogRefusal::invalid_product);
        }
        const auto checked = opened->catalog().recheck_ownership(
            *user, *product, request.token());
        if (!checked) {
          return OwnershipOutcome::unanswered(unanswered_of(checked.error()));
        }
        OwnershipFacts ownership{checked.value().kind(), std::nullopt};
        if (const auto& game = checked.value().game()) {
          ownership.game = game_of(*user, *game, opened->catalog());
        }
        return OwnershipOutcome::answered(std::move(ownership));
      });
}

auto CatalogBridge::held_trials(const Bytes& account_id) -> GameList {
  return Boundary::fenced(GameList{}, [&]() -> GameList {
    const auto opened = Opened::shared();
    if (!opened) {
      return {};
    }
    const auto user = opened->user(account_id);
    if (!user) {
      return {};
    }
    auto& held = opened->catalog();
    GameList trials;
    for (const auto& game : held.held_trials(*user)) {
      trials.push_back(game_of(*user, game, held));
    }
    return trials;
  });
}

auto CatalogBridge::explain(const Bytes& account_id,
                            const std::string& product_id)
    -> std::optional<ExplanationFacts> {
  return Boundary::fenced(
      std::optional<ExplanationFacts>{},
      [&]() -> std::optional<ExplanationFacts> {
        const auto opened = Opened::shared();
        if (!opened) {
          return std::nullopt;
        }
        const auto user = opened->user(account_id);
        const auto product = catalog::ProductId::parse(product_id);
        if (!user || !product) {
          return std::nullopt;
        }
        const auto explanation = opened->catalog().explain(*user, *product);
        ExplanationFacts facts{};
        facts.listed = explanation.is_listed();
        for (const auto& step : explanation.steps()) {
          ExplanationStepFacts row{};
          row.rule = step.rule;
          row.outcome = step.outcome;
          row.hides = step.hides.has_value();
          if (step.product) {
            row.product_id = step.product->text();
          }
          if (step.ownership) {
            row.ownership_id = step.ownership->text();
          }
          if (step.title_number) {
            row.title_number = step.title_number->text();
          }
          row.tier = step.tier;
          facts.steps.push_back(std::move(row));
        }
        return facts;
      });
}

auto CatalogBridge::how_fetched(const Bytes& account_id)
    -> std::optional<FetchFacts> {
  return Boundary::fenced(
      std::optional<FetchFacts>{}, [&]() -> std::optional<FetchFacts> {
        const auto opened = Opened::shared();
        if (!opened) {
          return std::nullopt;
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return std::nullopt;
        }
        const auto fetched = opened->catalog().how_fetched(*user);
        if (!fetched) {
          return std::nullopt;
        }
        FetchFacts facts{};
        facts.from_account_service = fetched->legacy_cloud_stream.origin ==
                                     catalog::ListOrigin::account_service;
        facts.complete = fetched->legacy_cloud_stream.complete;
        facts.fetched_at_ms =
            Timestamp::milliseconds_of(fetched->legacy_cloud_stream.fetched_at);
        facts.ps_now_titles = fetched->legacy_cloud_stream.titles;
        if (const auto& copies = fetched->legacy_cloud_stream.copies_checked) {
          facts.copies_asked = copies->asked;
          facts.copies_answered = copies->answered;
        }
        facts.without_a_covered_copy =
            fetched->legacy_cloud_stream.without_a_covered_copy;
        facts.ps_cloud_titles = fetched->cloud_stream.titles;
        if (const auto& audience = fetched->cloud_stream.audience) {
          facts.audience_country = audience->country;
          facts.audience_language = audience->language;
          facts.audience_age = audience->age;
        }
        if (const auto& premium = fetched->cloud_stream.premium_category) {
          facts.premium_category_fetched_at_ms =
              Timestamp::milliseconds_of(premium->fetched_at);
          facts.premium_category_titles = premium->titles;
        }
        facts.library = fetched->library;
        if (fetched->library_fetched_at) {
          facts.library_fetched_at_ms =
              Timestamp::milliseconds_of(*fetched->library_fetched_at);
        }
        facts.library_records = fetched->library_records;
        facts.tier = fetched->tier;
        return facts;
      });
}

auto CatalogBridge::cloud_access(const Request& request,
                                 const Bytes& account_id)
    -> CloudAccessOutcome {
  return Boundary::fenced(
      CloudAccessOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> CloudAccessOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return CloudAccessOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return CloudAccessOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto checked =
            opened->catalog().cloud_access_of(*user, request.token());
        if (!checked) {
          return CloudAccessOutcome::unanswered(unanswered_of(checked.error()));
        }
        CloudAccessFacts access{checked.value().availability(), std::nullopt,
                                false, false};
        if (const auto& listing = checked.value().listing()) {
          access.title_count = listing->title_count;
          access.complete = listing->complete;
          access.from_account_service =
              listing->origin == catalog::ListOrigin::account_service;
        }
        return CloudAccessOutcome::answered(std::move(access));
      });
}

auto CatalogBridge::cloud_capture(const Request& request,
                                  const Bytes& account_id,
                                  const std::string& gallery_id)
    -> CaptureFileOutcome {
  return Boundary::fenced(
      CaptureFileOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> CaptureFileOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return CaptureFileOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return CaptureFileOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto found =
            opened->catalog().cloud_capture(*user, gallery_id, request.token());
        if (!found) {
          return CaptureFileOutcome::unanswered(unanswered_of(found.error()));
        }
        return CaptureFileOutcome::answered(
            CaptureFileFacts{found->url, found->file_type, found->size});
      });
}

auto CatalogBridge::cloud_capture_download(const Request& request,
                                           const Bytes& account_id)
    -> CaptureDownloadOutcome {
  return Boundary::fenced(
      CaptureDownloadOutcome::refused(CatalogRefusal::core_closed),
      [&]() -> CaptureDownloadOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return CaptureDownloadOutcome::refused(CatalogRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return CaptureDownloadOutcome::refused(CatalogRefusal::unknown_user);
        }
        const auto setting =
            opened->catalog().cloud_capture_download(*user, request.token());
        if (!setting) {
          return CaptureDownloadOutcome::unanswered(
              unanswered_of(setting.error()));
        }
        return CaptureDownloadOutcome::answered(*setting);
      });
}

}  // namespace chiaki_bridge
