#pragma once

#ifdef __cplusplus
#include <libchiaking/users.hpp>
#include <memory>
#include <vector>

namespace chiaki_store_adapters {

class CredentialStoreAdapter final
    : public libchiaking::users::CredentialStore {
 public:
  explicit CredentialStoreAdapter(void* gateway);
  ~CredentialStoreAdapter() override;
  CredentialStoreAdapter(const CredentialStoreAdapter&) = delete;
  auto operator=(const CredentialStoreAdapter&)
      -> CredentialStoreAdapter& = delete;

  [[nodiscard]] auto load_saved_users()
      -> libchiaking::Expected<std::vector<libchiaking::users::SavedSignIn>,
                               Error> override;
  [[nodiscard]] auto load_home_users()
      -> libchiaking::Expected<std::vector<libchiaking::users::SavedHomeUser>,
                               Error> override;
  [[nodiscard]] auto save(const libchiaking::users::SavedSignIn& user)
      -> libchiaking::Expected<void, Error> override;
  [[nodiscard]] auto save(const libchiaking::users::SavedHomeUser& user)
      -> libchiaking::Expected<void, Error> override;
  [[nodiscard]] auto remove(libchiaking::AccountId account)
      -> libchiaking::Expected<void, Error> override;

 private:
  struct Gateway;

  std::unique_ptr<Gateway> gateway_;
};

}  // namespace chiaki_store_adapters

#endif
