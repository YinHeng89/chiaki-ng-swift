#pragma once

#include <cstddef>
#include <cstdint>
#include <libchiaking/users.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

enum class UsersRefusal : std::uint8_t {
  core_closed,
  unknown_user,
  invalid_device,
  not_saved,
};

struct UserFacts {
  Bytes account_id;
  std::string online_id;
  bool has_psn_account;
  libchiaking::users::SignInState sign_in_state;
  std::optional<libchiaking::users::Tier> tier;
  std::optional<bool> plus_member;
  std::optional<std::string> avatar_url;
  std::optional<std::string> country;
  std::optional<std::string> language;
};

using UserList = std::vector<UserFacts>;
using Milliseconds = std::optional<std::int64_t>;

struct WelcomedBack {
  std::size_t admitted;
  std::size_t rejected;
};

struct OtherAccount {
  Bytes account_id;
  std::string online_id;
};

/// Why PSN refused a sign-in.
struct SignInFailureFacts {
  /// What went wrong.
  libchiaking::users::SignInErrorKind kind;
  /// The HTTP status of the reply behind the failure, when there was one.
  std::optional<std::uint16_t> http_status;
};

/// How a sign-in ended: signed in, as a different account, refused before
/// the core ran, or failed.
class SignInOutcome {
 public:
  /// The ways the sign-in can end.
  enum class Kind : std::uint8_t {
    /// The user is signed in.
    signed_in,
    /// The sign-in belongs to another account than the one asked for.
    different_account,
    /// The bridge refused the sign-in before the core ran.
    refused,
    /// PSN or the core refused the sign-in.
    failed,
  };

  /// A user now signed in.
  static auto signed_in(UserFacts value) -> SignInOutcome {
    return SignInOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::signed_in)>,
             std::move(value)}};
  }

  /// A sign-in that belongs to another account.
  static auto different_account(OtherAccount value) -> SignInOutcome {
    return SignInOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::different_account)>,
             std::move(value)}};
  }

  /// A sign-in the bridge refused.
  static auto refused(UsersRefusal value) -> SignInOutcome {
    return SignInOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// A sign-in that failed.
  static auto failed(SignInFailureFacts value) -> SignInOutcome {
    return SignInOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::failed)>,
             std::move(value)}};
  }

  /// How the sign-in ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The signed-in user; valid for `signed_in`.
  auto user() const -> UserFacts {
    return std::get<std::to_underlying(Kind::signed_in)>(held_);
  }

  /// The account the sign-in belongs to; valid for `different_account`.
  auto other_account() const -> OtherAccount {
    return std::get<std::to_underlying(Kind::different_account)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> UsersRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

  /// Why the sign-in failed; valid for `failed`.
  auto failure() const -> SignInFailureFacts {
    return std::get<std::to_underlying(Kind::failed)>(held_);
  }

 private:
  using Case =
      std::variant<UserFacts, OtherAccount, UsersRefusal, SignInFailureFacts>;

  explicit SignInOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How adding a home user ended: added, refused or with an invalid user.
class HomeUserOutcome {
 public:
  /// The ways the addition can end.
  enum class Kind : std::uint8_t {
    /// The user was added.
    added,
    /// The bridge refused the addition.
    refused,
    /// The core found the user invalid.
    invalid,
  };

  /// A user now added.
  static auto added(UserFacts value) -> HomeUserOutcome {
    return HomeUserOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::added)>,
             std::move(value)}};
  }

  /// An addition the bridge refused.
  static auto refused(UsersRefusal value) -> HomeUserOutcome {
    return HomeUserOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// An addition the core found invalid.
  static auto invalid(libchiaking::users::PsUser::Invalid value)
      -> HomeUserOutcome {
    return HomeUserOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::invalid)>,
             std::move(value)}};
  }

  /// How the addition ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The added user; valid for `added`.
  auto user() const -> UserFacts {
    return std::get<std::to_underlying(Kind::added)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> UsersRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

  /// Why the user is invalid; valid for `invalid`.
  auto invalid_because() const -> libchiaking::users::PsUser::Invalid {
    return std::get<std::to_underlying(Kind::invalid)>(held_);
  }

 private:
  using Case = std::variant<UserFacts, UsersRefusal,
                            libchiaking::users::PsUser::Invalid>;

  explicit HomeUserOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How refreshing a user's sign-in ended: refreshed, unanswered or refused.
class RefreshOutcome {
 public:
  /// The ways the refresh can end.
  enum class Kind : std::uint8_t {
    /// The sign-in, profile and membership were renewed.
    refreshed,
    /// PSN gave no answer.
    unanswered,
    /// The bridge refused the refresh.
    refused,
  };

  /// A user now refreshed.
  static auto refreshed(UserFacts value) -> RefreshOutcome {
    return RefreshOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refreshed)>,
             std::move(value)}};
  }

  /// A refresh PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered value)
      -> RefreshOutcome {
    return RefreshOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>,
             std::move(value)}};
  }

  /// A refresh the bridge refused.
  static auto refused(UsersRefusal value) -> RefreshOutcome {
    return RefreshOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::refused)>,
             std::move(value)}};
  }

  /// How the refresh ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The refreshed user; valid for `refreshed`.
  auto user() const -> UserFacts {
    return std::get<std::to_underlying(Kind::refreshed)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

  /// Why the bridge refused; valid for `refused`.
  auto refusal() const -> UsersRefusal {
    return std::get<std::to_underlying(Kind::refused)>(held_);
  }

 private:
  using Case =
      std::variant<UserFacts, libchiaking::users::Unanswered, UsersRefusal>;

  explicit RefreshOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

using CredentialUses = std::vector<libchiaking::users::CredentialUse>;

struct HeldCredentialFacts {
  libchiaking::users::CredentialKind kind;
  bool held;
  libchiaking::users::HeldCredential::Kept kept;
  libchiaking::users::HeldCredential::State state;
  std::optional<std::int64_t> obtained_at_ms;
  std::optional<std::int64_t> expires_at_ms;
  std::string scopes;
  std::optional<std::uint16_t> last_reply_status;
  CredentialUses used_for;
};

using HeldCredentialList = std::vector<HeldCredentialFacts>;

enum class RevealRefusal : std::uint8_t {
  core_closed,
  unknown_user,
  not_held,
  signed_out,
};

using RevealedSink = void (*)(const char* secret, std::size_t size,
                              void* context);
using QrSignInSink = void (*)(std::uint32_t attempt, std::uint8_t step,
                              const char* approval_url, const char* user_code,
                              std::int64_t expires_at_ms, void* context);

class UsersBridge {
 public:
  static auto welcome_back() -> std::optional<WelcomedBack>;
  static auto everyone() -> UserList;
  static auto find(const Bytes& account_id) -> std::optional<UserFacts>;
  static auto server_time() -> std::optional<std::int64_t>;
  static auto sign_in(const Request& request, const char* npsso,
                      Milliseconds valid_until_ms, const std::string& device_id,
                      const std::string& correlation_id) -> SignInOutcome;
  static auto sign_in_with_qr(const Request& request,
                              const std::string& device_id,
                              const std::string& correlation_id,
                              QrSignInSink sink, void* context)
      -> SignInOutcome;
  static auto sign_in_again(const Request& request, const Bytes& account_id,
                            const char* npsso, Milliseconds valid_until_ms,
                            const std::string& device_id,
                            const std::string& correlation_id) -> SignInOutcome;
  static auto add_home_user(const Bytes& account_id, const std::string& name)
      -> HomeUserOutcome;
  static auto sign_out(const Bytes& account_id) -> std::optional<UsersRefusal>;
  static auto refresh(const Request& request, const Bytes& account_id)
      -> RefreshOutcome;
  static auto facts_of(const libchiaking::users::PsUser& user) -> UserFacts;

 private:
  static auto valid_until(std::optional<std::int64_t> milliseconds)
      -> std::optional<libchiaking::users::SavedSignIn::Time>;
  static auto failed(const libchiaking::users::SignInError& error)
      -> SignInOutcome;
};

class CredentialsBridge {
 public:
  static auto held_by(const Bytes& account_id)
      -> std::optional<HeldCredentialList>;
  static auto reveal(const Bytes& account_id,
                     libchiaking::users::CredentialKind kind, RevealedSink sink,
                     void* context) -> std::optional<RevealRefusal>;
  static auto facts_of(const libchiaking::users::HeldCredential& credential)
      -> HeldCredentialFacts;
  static auto refusal_of(libchiaking::users::NotRevealed::Reason reason)
      -> RevealRefusal;
};

}  // namespace chiaki_bridge
