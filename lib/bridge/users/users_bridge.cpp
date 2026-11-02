#include <chrono>
#include <utility>

#include "account_ids.hpp"
#include "boundary.hpp"
#include "chiaki_bridge/users.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::users::DeviceId;
using libchiaking::users::Npsso;
using libchiaking::users::PsUser;
using libchiaking::users::SavedSignIn;
using libchiaking::users::SignInError;
using libchiaking::users::Unanswered;

auto UsersBridge::valid_until(std::optional<std::int64_t> milliseconds)
    -> std::optional<SavedSignIn::Time> {
  if (!milliseconds) {
    return std::nullopt;
  }
  return Timestamp::moment_of(*milliseconds);
}

auto UsersBridge::facts_of(const PsUser& user) -> UserFacts {
  UserFacts facts{};
  facts.account_id = IdentifierBytes::of(user.account_id());
  facts.online_id = std::string{user.online_id()};
  facts.has_psn_account = user.has_psn_account();
  facts.sign_in_state = user.sign_in_state();
  const auto membership = user.membership();
  facts.tier = membership.tier();
  facts.plus_member = membership.is_ps_plus_member();
  facts.avatar_url = user.avatar_url();
  if (const auto region = user.region()) {
    facts.country = region->country;
    facts.language = region->language;
  }
  return facts;
}

auto UsersBridge::failed(const SignInError& error) -> SignInOutcome {
  SignInFailureFacts failure{error.kind(), std::nullopt};
  if (error.http_status() != 0) {
    failure.http_status = error.http_status();
  }
  return SignInOutcome::failed(failure);
}

auto UsersBridge::welcome_back() -> std::optional<WelcomedBack> {
  return Boundary::fenced(
      std::optional<WelcomedBack>{}, []() -> std::optional<WelcomedBack> {
        const auto opened = Opened::shared();
        if (!opened) {
          return std::nullopt;
        }
        const auto returned = opened->users().welcome_back();
        if (!returned) {
          return std::nullopt;
        }
        return WelcomedBack{returned.value().users.size(),
                            returned.value().rejected};
      });
}

auto UsersBridge::everyone() -> UserList {
  return Boundary::fenced(UserList{}, [] {
    UserList list;
    if (const auto opened = Opened::shared()) {
      for (const auto& user : opened->users().everyone()) {
        list.push_back(facts_of(*user));
      }
    }
    return list;
  });
}

auto UsersBridge::find(const Bytes& account_id) -> std::optional<UserFacts> {
  return Boundary::fenced(std::optional<UserFacts>{},
                          [&]() -> std::optional<UserFacts> {
                            const auto opened = Opened::shared();
                            if (!opened) {
                              return std::nullopt;
                            }
                            const auto user = opened->user(account_id);
                            if (!user) {
                              return std::nullopt;
                            }
                            return facts_of(*user);
                          });
}

auto UsersBridge::server_time() -> std::optional<std::int64_t> {
  return Boundary::fenced(std::optional<std::int64_t>{},
                          []() -> std::optional<std::int64_t> {
                            const auto opened = Opened::shared();
                            if (!opened) {
                              return std::nullopt;
                            }
                            const auto time = opened->users().server_time();
                            if (!time) {
                              return std::nullopt;
                            }
                            return Timestamp::milliseconds_of(*time);
                          });
}

auto UsersBridge::sign_in(const Request& request, const char* npsso,
                          Milliseconds valid_until_ms,
                          const std::string& device_id,
                          const std::string& correlation_id) -> SignInOutcome {
  if (npsso == nullptr) {
    return SignInOutcome::failed(SignInFailureFacts{
        libchiaking::users::SignInErrorKind::invalid_request, std::nullopt});
  }
  return Boundary::fenced(
      SignInOutcome::refused(UsersRefusal::core_closed),
      [&]() -> SignInOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return SignInOutcome::refused(UsersRefusal::core_closed);
        }
        const auto device = DeviceId::parse(device_id);
        if (!device) {
          return SignInOutcome::refused(UsersRefusal::invalid_device);
        }
        const auto result = opened->users().sign_in(
            Npsso{npsso}, *device, correlation_id, request.token(),
            valid_until(valid_until_ms));
        if (!result) {
          return failed(result.error());
        }
        return SignInOutcome::signed_in(facts_of(*result.value()));
      });
}

auto UsersBridge::sign_in_with_qr(const Request& request,
                                  const std::string& device_id,
                                  const std::string& correlation_id,
                                  QrSignInSink sink, void* context)
    -> SignInOutcome {
  return Boundary::fenced(
      SignInOutcome::refused(UsersRefusal::core_closed),
      [&]() -> SignInOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return SignInOutcome::refused(UsersRefusal::core_closed);
        }
        const auto device = DeviceId::parse(device_id);
        if (!device) {
          return SignInOutcome::refused(UsersRefusal::invalid_device);
        }
        const auto observer =
            [sink, context](const libchiaking::users::QrSignInState& state) {
              if (sink == nullptr) {
                return;
              }
              const std::string url{state.approval_url()};
              const std::string code{state.user_code()};
              const auto expires = state.expires_at();
              const std::int64_t expires_at_ms =
                  expires ? Timestamp::milliseconds_of(*expires) : -1;
              sink(state.attempt(), static_cast<std::uint8_t>(state.step()),
                   url.c_str(), code.c_str(), expires_at_ms, context);
            };
        const auto result = opened->users().sign_in_with_qr(
            *device, correlation_id, request.token(), observer);
        if (!result) {
          return failed(result.error());
        }
        return SignInOutcome::signed_in(facts_of(*result.value()));
      });
}

auto UsersBridge::sign_in_again(const Request& request, const Bytes& account_id,
                                const char* npsso, Milliseconds valid_until_ms,
                                const std::string& device_id,
                                const std::string& correlation_id)
    -> SignInOutcome {
  using Refusal = libchiaking::users::SignedInUsers::SignInAgainRefusal;
  if (npsso == nullptr) {
    return SignInOutcome::failed(SignInFailureFacts{
        libchiaking::users::SignInErrorKind::invalid_request, std::nullopt});
  }
  return Boundary::fenced(
      SignInOutcome::refused(UsersRefusal::core_closed),
      [&]() -> SignInOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return SignInOutcome::refused(UsersRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return SignInOutcome::refused(UsersRefusal::unknown_user);
        }
        const auto device = DeviceId::parse(device_id);
        if (!device) {
          return SignInOutcome::refused(UsersRefusal::invalid_device);
        }
        const auto result = opened->users().sign_in_again(
            *user, Npsso{npsso}, *device, correlation_id, request.token(),
            valid_until(valid_until_ms));
        if (result) {
          return SignInOutcome::signed_in(facts_of(*result.value()));
        }
        const auto& refusal = result.error();
        switch (refusal.kind()) {
          case Refusal::Kind::different_account: {
            if (const auto& other = refusal.signed_in_as()) {
              return SignInOutcome::different_account(
                  OtherAccount{IdentifierBytes::of(other->account),
                               std::string{other->online_id}});
            }
            return SignInOutcome::different_account(OtherAccount{});
          }
          case Refusal::Kind::unknown_user:
            return SignInOutcome::refused(UsersRefusal::unknown_user);
          case Refusal::Kind::sign_in_failed:
            break;
        }
        if (const auto& error = refusal.sign_in_error()) {
          return failed(*error);
        }
        return SignInOutcome::refused(UsersRefusal::unknown_user);
      });
}

auto UsersBridge::add_home_user(const Bytes& account_id,
                                const std::string& name) -> HomeUserOutcome {
  const auto account = AccountIds::account_of(account_id);
  if (!account) {
    return HomeUserOutcome::refused(UsersRefusal::unknown_user);
  }
  return Boundary::fenced(
      HomeUserOutcome::refused(UsersRefusal::core_closed),
      [&]() -> HomeUserOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return HomeUserOutcome::refused(UsersRefusal::core_closed);
        }
        const auto added = opened->users().add_home_user(*account, name);
        if (!added) {
          return HomeUserOutcome::invalid(added.error());
        }
        return HomeUserOutcome::added(facts_of(*added.value()));
      });
}

auto UsersBridge::sign_out(const Bytes& account_id)
    -> std::optional<UsersRefusal> {
  const auto account = AccountIds::account_of(account_id);
  if (!account) {
    return UsersRefusal::unknown_user;
  }
  return Boundary::fenced(
      std::optional<UsersRefusal>{UsersRefusal::core_closed},
      [&]() -> std::optional<UsersRefusal> {
        const auto opened = Opened::shared();
        if (!opened) {
          return UsersRefusal::core_closed;
        }
        if (!opened->chiaki().sign_out(*account)) {
          return UsersRefusal::not_saved;
        }
        return std::nullopt;
      });
}

auto UsersBridge::refresh(const Request& request, const Bytes& account_id)
    -> RefreshOutcome {
  return Boundary::fenced(
      RefreshOutcome::refused(UsersRefusal::core_closed),
      [&]() -> RefreshOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return RefreshOutcome::refused(UsersRefusal::core_closed);
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return RefreshOutcome::refused(UsersRefusal::unknown_user);
        }
        const auto stop = request.token();
        std::optional<Unanswered> failure;
        if (const auto stayed = user->stay_signed_in(stop); !stayed) {
          failure = stayed.error();
        }
        if (!failure) {
          if (const auto profile = user->get_my_profile(stop); !profile) {
            failure = profile.error();
          }
        }
        if (!failure) {
          static_cast<void>(user->get_my_membership(stop));
        }
        if (failure) {
          return RefreshOutcome::unanswered(*failure);
        }
        return RefreshOutcome::refreshed(facts_of(*user));
      });
}

}  // namespace chiaki_bridge
