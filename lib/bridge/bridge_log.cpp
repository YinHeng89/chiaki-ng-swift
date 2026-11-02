#include "bridge_log.hpp"

#include <array>
#include <cstdarg>
#include <cstdio>
#include <new>

#include "boundary.hpp"

nx_bridge_log* nx_bridge_log_create(void) {
  return chiaki_bridge::Boundary::fenced(static_cast<nx_bridge_log*>(nullptr),
                                         [] { return new nx_bridge_log; });
}

void nx_bridge_log_destroy(nx_bridge_log* log) { delete log; }

void nx_bridge_log_write(nx_bridge_log* log, nx_log_severity severity,
                         const char* format, ...) {
  if (log == nullptr || format == nullptr) {
    return;
  }
  std::array<char, libchiaking::diagnostics::SessionJournal::message_limit + 1>
      text{};
  va_list arguments;
  va_start(arguments, format);
  std::vsnprintf(text.data(), text.size(), format, arguments);
  va_end(arguments);
  log->write(nx_bridge_log::severity_of(severity), text.data());
}

bool nx_bridge_log_read(nx_bridge_log* log, int* severity, char* message,
                        size_t capacity) {
  if (log == nullptr || severity == nullptr || message == nullptr ||
      capacity == 0) {
    return false;
  }
  return chiaki_bridge::Boundary::fenced(false, [&] {
    const auto entry = log->journal()->read();
    if (!entry) {
      return false;
    }
    *severity = static_cast<int>(entry->severity());
    std::snprintf(message, capacity, "%s", entry->line().c_str());
    return true;
  });
}
