#pragma once

#include <algorithm>
#include <libchiaking/play_types.hpp>
#include <memory>
#include <string_view>

#include "bridge_log.h"
#include "runtime.hpp"

struct nx_bridge_log {
 public:
  nx_bridge_log()
      : journal_(std::make_shared<libchiaking::diagnostics::SessionJournal>(
            chiaki_bridge::Runtime::process().threading(),
            chiaki_bridge::Runtime::process().clock(), 1,
            libchiaking::diagnostics::SessionJournal::Labels{.session =
                                                                 "bridge"})) {}

  static auto severity_of(nx_log_severity severity) noexcept
      -> libchiaking::platform::LogSeverity {
    return static_cast<libchiaking::platform::LogSeverity>(
        std::clamp(static_cast<int>(severity), static_cast<int>(NX_LOG_ERROR),
                   static_cast<int>(NX_LOG_DEBUG)));
  }

  auto journal() const noexcept
      -> const std::shared_ptr<libchiaking::diagnostics::SessionJournal>& {
    return journal_;
  }

  void write(libchiaking::platform::LogSeverity severity,
             std::string_view message) const noexcept {
    journal_->write({severity, message});
  }

  void info(std::string_view message) const noexcept {
    write(libchiaking::platform::LogSeverity::info, message);
  }

  void warning(std::string_view message) const noexcept {
    write(libchiaking::platform::LogSeverity::warning, message);
  }

  void error(std::string_view message) const noexcept {
    write(libchiaking::platform::LogSeverity::error, message);
  }

 private:
  std::shared_ptr<libchiaking::diagnostics::SessionJournal> journal_;
};
