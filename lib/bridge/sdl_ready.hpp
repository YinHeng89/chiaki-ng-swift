#pragma once

#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#include <TargetConditionals.h>

namespace chiaki_bridge {

/// Tells SDL that the app, not SDL, owns the entry point.
class SdlReady {
 public:
  /// Marks SDL ready on the platforms that need it before SDL is initialised.
  static void mark() noexcept {
#if TARGET_OS_IOS
    SDL_SetMainReady();
#endif
  }
};

}  // namespace chiaki_bridge
