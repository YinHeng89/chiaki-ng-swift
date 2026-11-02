#include "CredentialStoreAdapter.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <libchiaking/users_types.hpp>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

#include "ChiakiPersistence-Swift.h"
#include "boundary.hpp"

namespace chiaki_store_adapters {

using ChiakiPersistence::CoreTokenKind;
using libchiaking::SecretString;
using libchiaking::unexpected;
using libchiaking::users::AccountContext;
using libchiaking::users::DeviceId;
using libchiaking::users::Region;
using libchiaking::users::SavedHomeUser;
using libchiaking::users::SavedSignIn;

struct CredentialStoreAdapter::Gateway {
  ChiakiPersistence::CoreCredentialGateway store;

  static auto account_of(const swift::Array<std::uint8_t>& array)
      -> std::optional<libchiaking::AccountId> {
    constexpr auto size = libchiaking::psn_account_id_size;
    if (array.getCount() != static_cast<swift::Int>(size)) {
      return std::nullopt;
    }
    std::array<std::byte, size> bytes{};
    for (std::size_t index = 0; index < size; ++index) {
      bytes[index] =
          static_cast<std::byte>(array[static_cast<swift::Int>(index)]);
    }
    return libchiaking::AccountId::from_bytes(bytes);
  }

  static auto moment_of(const swift::Optional<std::int64_t>& milliseconds)
      -> std::optional<chiaki_bridge::Timestamp::Moment> {
    if (!milliseconds.isSome()) {
      return std::nullopt;
    }
    return chiaki_bridge::Timestamp::moment_of(milliseconds.getSome());
  }

  static auto crossing(const std::optional<chiaki_bridge::Timestamp::Moment>& moment)
      -> swift::Optional<std::int64_t> {
    return moment ? swift::Optional<std::int64_t>::init(
                        chiaki_bridge::Timestamp::milliseconds_of(*moment))
                  : swift::Optional<std::int64_t>::none();
  }

  static auto text_of(const swift::Optional<swift::String>& text)
      -> std::optional<std::string> {
    if (!text.isSome()) {
      return std::nullopt;
    }
    return std::string(text.getSome());
  }

  template <class Copy>
  static auto secret_of(swift::Int length, Copy copy)
      -> std::optional<SecretString> {
    if (length <= 0) {
      return std::nullopt;
    }
    SecretString secret;
    secret.resize(static_cast<std::size_t>(length));
    if (!copy(secret.data())) {
      return std::nullopt;
    }
    return secret;
  }

  template <class Token>
  static auto token_of(ChiakiPersistence::CoreSignInLedger& ledger,
                       swift::Int index, const CoreTokenKind& kind)
      -> std::optional<Token> {
    auto secret = secret_of(ledger.tokenLength(index, kind), [&](char* into) {
      return ledger.copyToken(index, kind, into);
    });
    if (!secret) {
      return std::nullopt;
    }
    return Token{std::move(*secret)};
  }

  static auto context_of(const ChiakiPersistence::CoreSignInRecord& record)
      -> AccountContext {
    AccountContext::Stated stated;
    stated.legal_country = text_of(record.getLegalCountry());
    stated.locale = text_of(record.getLocale());
    if (const auto age = record.getAge(); age.isSome()) {
      stated.age = age.getSome();
    }
    if (const auto child = record.getIsChild(); child.isSome()) {
      stated.is_child = child.getSome();
    }
    stated.issued_at = moment_of(record.getContextIssuedAt());
    return AccountContext::stating(stated);
  }

  static auto sign_in_of(ChiakiPersistence::CoreSignInLedger& ledger,
                         const ChiakiPersistence::CoreSignInRecord& record,
                         swift::Int index) -> std::optional<SavedSignIn> {
    const auto account = account_of(record.getAccountID());
    if (!account) {
      return std::nullopt;
    }
    auto npsso = secret_of(ledger.npssoLength(index), [&](char* into) {
      return ledger.copyNPSSO(index, into);
    });
    if (!npsso) {
      return std::nullopt;
    }
    SavedSignIn saved{*account, std::string(record.getOnlineID()),
                      libchiaking::users::Npsso{std::move(*npsso)}};
    saved.npsso_obtained_at = moment_of(record.getNpssoObtainedAt());
    saved.npsso_expires_at = moment_of(record.getNpssoExpiresAt());
    if (auto token = token_of<libchiaking::users::AppToken>(
            ledger, index, CoreTokenKind::storeAccess())) {
      saved.store.emplace(
          std::move(*token),
          moment_of(ledger.tokenExpiresAt(index, CoreTokenKind::storeAccess()))
              .value_or(chiaki_bridge::Timestamp::Moment{}),
          moment_of(
              ledger.tokenObtainedAt(index, CoreTokenKind::storeAccess())));
    }
    if (auto token = token_of<libchiaking::users::AppRefreshToken>(
            ledger, index, CoreTokenKind::storeRefresh())) {
      saved.store_refresh.emplace(std::move(*token),
                                  moment_of(ledger.tokenObtainedAt(
                                      index, CoreTokenKind::storeRefresh())),
                                  moment_of(ledger.tokenExpiresAt(
                                      index, CoreTokenKind::storeRefresh())));
    }
    if (auto token = token_of<libchiaking::users::BearerToken>(
            ledger, index, CoreTokenKind::remotePlayAccess())) {
      saved.remote_play.emplace(
          std::move(*token),
          moment_of(
              ledger.tokenExpiresAt(index, CoreTokenKind::remotePlayAccess()))
              .value_or(chiaki_bridge::Timestamp::Moment{}),
          moment_of(ledger.tokenObtainedAt(index,
                                           CoreTokenKind::remotePlayAccess())));
    }
    if (auto token = token_of<libchiaking::users::RemotePlayRefreshToken>(
            ledger, index, CoreTokenKind::remotePlayRefresh())) {
      saved.remote_play_refresh.emplace(
          std::move(*token),
          moment_of(ledger.tokenObtainedAt(index,
                                           CoreTokenKind::remotePlayRefresh())),
          moment_of(ledger.tokenExpiresAt(index,
                                          CoreTokenKind::remotePlayRefresh())));
    }
    const auto country = text_of(record.getCountry());
    const auto language = text_of(record.getLanguage());
    if (country && language) {
      saved.region = Region{*country, *language};
    }
    saved.context = context_of(record);
    if (const auto device = text_of(record.getDeviceID())) {
      if (auto parsed = DeviceId::parse(*device)) {
        saved.device.emplace(std::move(*parsed));
      }
    }
    return saved;
  }

  static void place_token(
      ChiakiPersistence::CoreSignInDraft& draft, const CoreTokenKind& kind,
      std::string_view token,
      const std::optional<chiaki_bridge::Timestamp::Moment>& obtained_at,
      const std::optional<chiaki_bridge::Timestamp::Moment>& expires_at) {
    static constexpr char empty = '\0';
    draft.setToken(kind, token.empty() ? &empty : token.data(),
                   static_cast<swift::Int>(token.size()), crossing(obtained_at),
                   crossing(expires_at));
  }
};

CredentialStoreAdapter::CredentialStoreAdapter(void* gateway)
    : gateway_(std::make_unique<Gateway>(
          Gateway{ChiakiPersistence::CoreStoreGateway::adopting(gateway)
                      .getCredentials()})) {}

CredentialStoreAdapter::~CredentialStoreAdapter() = default;

auto CredentialStoreAdapter::load_saved_users()
    -> libchiaking::Expected<std::vector<SavedSignIn>, Error> {
  auto loaded = gateway_->store.loadSignIns();
  if (!loaded.isSome()) {
    return unexpected(Error::unavailable);
  }
  auto ledger = loaded.getSome();
  std::vector<SavedSignIn> users;
  swift::Int index = 0;
  for (const auto& record : ledger.getSignIns()) {
    if (auto user = Gateway::sign_in_of(ledger, record, index)) {
      users.push_back(std::move(*user));
    }
    ++index;
  }
  return users;
}

auto CredentialStoreAdapter::load_home_users()
    -> libchiaking::Expected<std::vector<SavedHomeUser>, Error> {
  auto loaded = gateway_->store.loadHomeUsers();
  if (!loaded.isSome()) {
    return unexpected(Error::unavailable);
  }
  std::vector<SavedHomeUser> users;
  for (const auto& record : loaded.getSome().getUsers()) {
    if (const auto account = Gateway::account_of(record.getAccountID())) {
      users.push_back(SavedHomeUser{*account, std::string(record.getName())});
    }
  }
  return users;
}

auto CredentialStoreAdapter::save(const SavedSignIn& user)
    -> libchiaking::Expected<void, Error> {
  static constexpr char empty = '\0';
  const auto account = user.account.bytes();
  const auto npsso = user.npsso.view();
  auto draft =
      gateway_->store.beginSignIn(account.data(), swift::String(user.online_id),
                                  npsso.empty() ? &empty : npsso.data(),
                                  static_cast<swift::Int>(npsso.size()));
  if (user.npsso_obtained_at) {
    draft.setNPSSOObtainedAt(
        chiaki_bridge::Timestamp::milliseconds_of(*user.npsso_obtained_at));
  }
  if (user.npsso_expires_at) {
    draft.setNPSSOExpiresAt(
        chiaki_bridge::Timestamp::milliseconds_of(*user.npsso_expires_at));
  }
  if (user.store) {
    Gateway::place_token(draft, CoreTokenKind::storeAccess(),
                         user.store->token.view(), user.store->obtained_at,
                         user.store->expires_at);
  }
  if (user.store_refresh) {
    Gateway::place_token(
        draft, CoreTokenKind::storeRefresh(), user.store_refresh->token.view(),
        user.store_refresh->obtained_at, user.store_refresh->expires_at);
  }
  if (user.remote_play) {
    Gateway::place_token(draft, CoreTokenKind::remotePlayAccess(),
                         user.remote_play->token.view(),
                         user.remote_play->obtained_at,
                         user.remote_play->expires_at);
  }
  if (user.remote_play_refresh) {
    Gateway::place_token(draft, CoreTokenKind::remotePlayRefresh(),
                         user.remote_play_refresh->token.view(),
                         user.remote_play_refresh->obtained_at,
                         user.remote_play_refresh->expires_at);
  }
  if (user.region) {
    draft.setRegion(swift::String(user.region->country),
                    swift::String(user.region->language));
  }
  if (const auto& country = user.context.legal_country()) {
    draft.setLegalCountry(swift::String(*country));
  }
  if (const auto& locale = user.context.locale()) {
    draft.setLocale(swift::String(*locale));
  }
  if (const auto age = user.context.age()) {
    draft.setAge(*age);
  }
  if (const auto child = user.context.is_child()) {
    draft.setIsChild(*child);
  }
  if (const auto issued = user.context.issued_at()) {
    draft.setContextIssuedAt(chiaki_bridge::Timestamp::milliseconds_of(*issued));
  }
  if (!gateway_->store.saveSignIn(draft)) {
    return unexpected(Error::unavailable);
  }
  return {};
}

auto CredentialStoreAdapter::save(const SavedHomeUser& user)
    -> libchiaking::Expected<void, Error> {
  const auto account = user.account.bytes();
  if (!gateway_->store.saveHomeUser(account.data(), swift::String(user.name))) {
    return unexpected(Error::unavailable);
  }
  return {};
}

auto CredentialStoreAdapter::remove(libchiaking::AccountId account)
    -> libchiaking::Expected<void, Error> {
  const auto bytes = account.bytes();
  if (!gateway_->store.removeAccount(bytes.data())) {
    return unexpected(Error::unavailable);
  }
  return {};
}

}  // namespace chiaki_store_adapters
