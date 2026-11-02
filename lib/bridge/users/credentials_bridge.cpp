#include <chrono>

#include "boundary.hpp"
#include "chiaki_bridge/users.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::users::CredentialKind;
using libchiaking::users::HeldCredential;
using libchiaking::users::NotRevealed;

auto CredentialsBridge::facts_of(const HeldCredential& credential)
    -> HeldCredentialFacts {
  HeldCredentialFacts facts{};
  facts.kind = credential.kind;
  facts.held = credential.held;
  facts.kept = credential.kept;
  facts.state = credential.state;
  if (credential.obtained_at) {
    facts.obtained_at_ms = Timestamp::milliseconds_of(*credential.obtained_at);
  }
  if (credential.expires_at) {
    facts.expires_at_ms = Timestamp::milliseconds_of(*credential.expires_at);
  }
  facts.scopes = credential.scopes;
  facts.last_reply_status = credential.last_reply_status;
  facts.used_for.assign(credential.used_for.begin(), credential.used_for.end());
  return facts;
}

auto CredentialsBridge::refusal_of(NotRevealed::Reason reason)
    -> RevealRefusal {
  switch (reason) {
    case NotRevealed::Reason::not_held:
      return RevealRefusal::not_held;
    case NotRevealed::Reason::signed_out:
      return RevealRefusal::signed_out;
  }
  return RevealRefusal::not_held;
}

auto CredentialsBridge::held_by(const Bytes& account_id)
    -> std::optional<HeldCredentialList> {
  return Boundary::fenced(
      std::optional<HeldCredentialList>{},
      [&]() -> std::optional<HeldCredentialList> {
        const auto opened = Opened::shared();
        if (!opened) {
          return std::nullopt;
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return std::nullopt;
        }
        HeldCredentialList list;
        for (const auto& credential : user->held_credentials()) {
          list.push_back(facts_of(credential));
        }
        return list;
      });
}

auto CredentialsBridge::reveal(const Bytes& account_id, CredentialKind kind,
                               RevealedSink sink, void* context)
    -> std::optional<RevealRefusal> {
  if (sink == nullptr) {
    return RevealRefusal::unknown_user;
  }
  return Boundary::fenced(
      std::optional<RevealRefusal>{RevealRefusal::core_closed},
      [&]() -> std::optional<RevealRefusal> {
        const auto opened = Opened::shared();
        if (!opened) {
          return RevealRefusal::core_closed;
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return RevealRefusal::unknown_user;
        }
        const auto revealed = user->reveal(kind);
        if (!revealed) {
          return refusal_of(revealed.error().reason);
        }
        sink(revealed.value().data(), revealed.value().size(), context);
        return std::nullopt;
      });
}

}  // namespace chiaki_bridge
