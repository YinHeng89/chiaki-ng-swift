#pragma once

#include <cstddef>
#include <cstdint>
#include <libchiaking/chiaki_ng.hpp>
#include <optional>
#include <string>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

struct SecretSpanFacts {
  std::size_t offset;
  std::size_t length;
  libchiaking::diagnostics::HttpSecretKind kind;
};

using SecretSpans = std::vector<SecretSpanFacts>;

struct MarkedTextView {
  const std::uint8_t* text;
  std::size_t size;
  SecretSpans spans;
};

struct HttpHeaderView {
  std::string name;
  MarkedTextView value;
};

using HttpHeaderViews = std::vector<HttpHeaderView>;

struct HttpBodyView {
  std::uint64_t size;
  std::uint64_t kept;
  bool truncated;
  bool binary;
  MarkedTextView text;
};

using HttpCredentials = std::vector<libchiaking::platform::HttpCredential>;

struct HttpCallView {
  std::uint64_t sequence;
  libchiaking::diagnostics::HttpArea area;
  HttpCredentials credentials;
  std::string credential_label;
  std::string label;
  std::uint16_t attempt;
  std::string method;
  std::int64_t started_at_ms;
  std::int64_t duration_us;
  std::string base;
  MarkedTextView url;
  std::optional<std::uint16_t> status;
  std::string reason;
  std::optional<libchiaking::platform::HttpError> transport_error;
  bool failed;
  std::uint64_t bytes_sent;
  std::uint64_t bytes_received;
};

struct HttpCallDetailView {
  HttpHeaderViews request_headers;
  HttpBodyView request_body;
  HttpHeaderViews response_headers;
  HttpBodyView response_body;
};

struct HttpTallyFacts {
  std::uint64_t requests;
  std::uint64_t http_errors;
  std::uint64_t transport_errors;
  std::uint64_t bytes_sent;
  std::uint64_t bytes_received;
};

struct HttpCredentialTallyFacts {
  libchiaking::platform::HttpCredential credential;
  HttpTallyFacts tally;
};

struct HttpBaseTallyFacts {
  std::string base;
  HttpTallyFacts tally;
};

using HttpCredentialTallies = std::vector<HttpCredentialTallyFacts>;
using HttpBaseTallies = std::vector<HttpBaseTallyFacts>;

struct HttpTotalsFacts {
  std::uint64_t revision;
  HttpTallyFacts all;
  HttpTallyFacts anonymous;
  HttpCredentialTallies credentials;
  HttpBaseTallies bases;
};

using HttpCallWatcher = void (*)(const HttpCallView* call, void* context);
using HttpCallDetailWatcher = void (*)(const HttpCallDetailView* detail,
                                       void* context);

struct CoreLogLine {
  libchiaking::platform::LogSeverity severity{};
  std::string message;
};

using CoreLogLines = std::vector<CoreLogLine>;

class CoreLogBridge {
 public:
  static auto read(std::size_t limit) -> CoreLogLines;
};

class HttpCallsBridge {
 public:
  static auto revision() -> std::uint64_t;
  static auto calls(HttpCallWatcher watcher, void* context)
      -> std::optional<HttpTotalsFacts>;
  static auto detail(std::uint64_t sequence, HttpCallDetailWatcher watcher,
                     void* context) -> bool;
  static void clear();
  static void reset_totals();
  static void drop_connections(const std::string& reason);

  static auto calls_of(const libchiaking::diagnostics::HttpCallLog& log,
                       HttpCallWatcher watcher, void* context)
      -> HttpTotalsFacts;
  static auto detail_of(const libchiaking::diagnostics::HttpCallLog& log,
                        std::uint64_t sequence, HttpCallDetailWatcher watcher,
                        void* context) -> bool;
  static auto marked_of(const libchiaking::diagnostics::HttpMarkedText& text)
      -> MarkedTextView;

 private:
  static auto tally_of(const libchiaking::diagnostics::HttpTally& tally)
      -> HttpTallyFacts;
  static auto headers_of(
      const std::vector<libchiaking::diagnostics::HttpMarkedHeader>& headers)
      -> HttpHeaderViews;
  static auto body_of(const libchiaking::diagnostics::HttpShownBody& body)
      -> HttpBodyView;
};

}  // namespace chiaki_bridge
