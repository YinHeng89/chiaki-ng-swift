#pragma once

#ifdef __cplusplus
#include <libchiaking/consoles.hpp>
#include <memory>

namespace chiaki_store_adapters {

class ConsoleStoreAdapter final : public libchiaking::consoles::ConsoleStore {
 public:
  explicit ConsoleStoreAdapter(void* gateway);
  ~ConsoleStoreAdapter() override;
  ConsoleStoreAdapter(const ConsoleStoreAdapter&) = delete;
  auto operator=(const ConsoleStoreAdapter&) -> ConsoleStoreAdapter& = delete;

  [[nodiscard]] auto load_saved_consoles()
      -> libchiaking::Expected<Saved, Error> override;
  [[nodiscard]] auto save(const libchiaking::consoles::SavedConsole& console)
      -> libchiaking::Expected<void, Error> override;
  [[nodiscard]] auto save(const libchiaking::consoles::SavedPairing& pairing)
      -> libchiaking::Expected<void, Error> override;
  [[nodiscard]] auto remove_pairing(libchiaking::AccountId account,
                                    libchiaking::consoles::HardwareId console)
      -> libchiaking::Expected<void, Error> override;
  [[nodiscard]] auto remove_console(libchiaking::consoles::HardwareId console)
      -> libchiaking::Expected<void, Error> override;

 private:
  struct Gateway;

  std::unique_ptr<Gateway> gateway_;
};

}  // namespace chiaki_store_adapters

#endif
