#include <cassert>
#include <cstdio>
#include <cstring>

#include "bridge_log.h"

int main() {
  nx_bridge_log* log = nx_bridge_log_create();
  assert(log);
  int severity = -1;
  char message[1024];
  assert(!nx_bridge_log_read(log, &severity, message, sizeof message));
  nx_bridge_log_write(log, NX_LOG_WARNING,
                      "core video recovery: frame=%u decoder=%d\nnext", 17u,
                      -8969);
  assert(nx_bridge_log_read(log, &severity, message, sizeof message));
  assert(severity == NX_LOG_WARNING);
  assert(!std::strncmp(message, "bridge attempt=", 15));
  assert(std::strstr(message, " sequence=1 elapsed_us="));
  assert(
      std::strstr(message, "core video recovery: frame=17 decoder=-8969 next"));
  assert(!std::strchr(message, '\n'));
  for (int index = 0; index < 300; index++) {
    nx_bridge_log_write(log, NX_LOG_INFO, "probe %d", index);
  }
  nx_bridge_log_write(log, NX_LOG_ERROR, "still kept");
  int count = 0;
  bool error_kept = false;
  while (nx_bridge_log_read(log, &severity, message, sizeof message)) {
    error_kept |= std::strstr(message, "still kept") != nullptr;
    count++;
  }
  assert(count == 226 && error_kept);
  assert(!std::strncmp(message, "bridge attempt=", 15));
  assert(std::strstr(message,
                     " the session journal dropped 76 diagnostic records"));
  assert(severity == NX_LOG_WARNING);
  nx_bridge_log_write(nullptr, NX_LOG_ERROR, "ignored");
  assert(!nx_bridge_log_read(nullptr, &severity, message, sizeof message));
  nx_bridge_log_destroy(log);
  nx_bridge_log_destroy(nullptr);
  std::puts("PASS: bridge log writes to the session journal");
  return 0;
}
