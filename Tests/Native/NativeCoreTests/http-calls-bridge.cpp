#include <cassert>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <libchiaking/chiaki_ng.hpp>
#include <libchiaking/platform/stock_providers.hpp>
#include <libchiaking/testing/in_memory_console_store.hpp>
#include <libchiaking/testing/in_memory_credential_store.hpp>
#include <libchiaking/testing/in_memory_record_store.hpp>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "chiaki_bridge/diagnostics.hpp"
#include "runtime.hpp"

namespace {

auto& native_test_threading = chiaki_bridge::Runtime::process().threading();
auto& native_test_clock = chiaki_bridge::Runtime::process().clock();

namespace catalog = libchiaking::catalog;
namespace diagnostics = libchiaking::diagnostics;
namespace platform = libchiaking::platform;
namespace play = libchiaking::play;
namespace testing = libchiaking::testing;

class QuietDatacenters final : public play::DatacenterStore {
 public:
  [[nodiscard]] auto load(catalog::ServiceGeneration)
      -> libchiaking::Expected<std::vector<play::DatacenterMeasurement>,
                               Error> override {
    return std::vector<play::DatacenterMeasurement>{};
  }

  [[nodiscard]] auto save(catalog::ServiceGeneration,
                          std::span<const play::DatacenterMeasurement>)
      -> libchiaking::Expected<void, Error> override {
    return {};
  }
};

class Household {
 public:
  Household() {
    auto opened = libchiaking::ChiakiNg::open(
        platform_.factory(),
        libchiaking::ChiakiNg::Stores{credentials_, consoles_, datacenters_,
                                      nullptr, records_});
    assert(opened);
    core = std::make_shared<libchiaking::ChiakiNg>(std::move(opened.value()));
  }

  auto log() const -> diagnostics::HttpCallLog& { return core->http_calls(); }

  void exchange(std::string_view url, std::uint16_t status,
                std::string_view body) {
    platform::HttpRequest request;
    request.method = platform::HttpMethod::post;
    request.url = libchiaking::SecretString{url};
    request.label = "test.exchange";
    request.headers.push_back(
        {"Authorization", libchiaking::SecretString{"Bearer SECRETTOKEN1"}});
    request.body.assign(std::string_view{"a=1"});
    request.provenance.credentials = request.provenance.credentials.with(
        platform::HttpCredential::account_token);
    request.provenance.attempt = 2;
    platform::HttpResponse response;
    response.status_code = status;
    response.reason = "Reason";
    response.body.assign(body);
    core->http_calls().record(
        diagnostics::HttpArea::catalog, request,
        libchiaking::Expected<platform::HttpResponse, platform::HttpError>{
            std::move(response)},
        diagnostics::HttpCall::Clock::time_point{
            std::chrono::milliseconds{1'700'000'000'000}},
        std::chrono::microseconds{2500});
  }

  void failure(std::string_view url) {
    platform::HttpRequest request;
    request.url = libchiaking::SecretString{url};
    core->http_calls().record(
        diagnostics::HttpArea::other, request,
        libchiaking::unexpected(platform::HttpError::timed_out),
        diagnostics::HttpCall::Clock::now(), std::chrono::microseconds{10});
  }

 private:
  platform::DefaultPlatform platform_;
  testing::InMemoryCredentialStore credentials_{native_test_threading};
  testing::InMemoryConsoleStore consoles_{native_test_threading};
  testing::InMemoryRecordStore records_{native_test_threading};
  QuietDatacenters datacenters_;

 public:
  std::shared_ptr<libchiaking::ChiakiNg> core;
};

using chiaki_bridge::HttpCallsBridge;

struct Row {
  std::uint64_t sequence{};
  diagnostics::HttpArea area{};
  std::vector<platform::HttpCredential> credentials;
  std::uint16_t attempt{};
  std::int64_t started_at_ms{};
  std::int64_t duration_us{};
  std::optional<std::uint16_t> status;
  std::optional<platform::HttpError> transport_error;
  bool failed{};
  std::uint64_t bytes_sent{};
  std::string base;
  std::string url;
  std::string method;
  std::string label;
  std::vector<chiaki_bridge::SecretSpanFacts> url_spans;
};

class Shown {
 public:
  static void call(const chiaki_bridge::HttpCallView* view, void* sink) {
    auto& shown = *static_cast<Shown*>(sink);
    shown.rows.push_back(
        Row{.sequence = view->sequence,
            .area = view->area,
            .credentials = {view->credentials.begin(), view->credentials.end()},
            .attempt = view->attempt,
            .started_at_ms = view->started_at_ms,
            .duration_us = view->duration_us,
            .status = view->status,
            .transport_error = view->transport_error,
            .failed = view->failed,
            .bytes_sent = view->bytes_sent,
            .base = view->base,
            .url = text_of(view->url),
            .method = view->method,
            .label = view->label,
            .url_spans = view->url.spans});
  }

  static void detail(const chiaki_bridge::HttpCallDetailView* view,
                     void* sink) {
    auto& shown = *static_cast<Shown*>(sink);
    shown.detailed = true;
    for (const auto& header : view->request_headers) {
      shown.request_headers.emplace_back(header.name, text_of(header.value));
      shown.request_header_spans.push_back(header.value.spans);
    }
    shown.response_body = text_of(view->response_body.text);
    shown.response_spans = view->response_body.text.spans;
    shown.response_binary = view->response_body.binary;
    shown.response_truncated = view->response_body.truncated;
  }

  static auto text_of(const chiaki_bridge::MarkedTextView& text)
      -> std::string {
    return std::string{reinterpret_cast<const char*>(text.text), text.size};
  }

  std::vector<Row> rows;
  std::vector<std::pair<std::string, std::string>> request_headers;
  std::vector<chiaki_bridge::SecretSpans> request_header_spans;
  std::string response_body;
  chiaki_bridge::SecretSpans response_spans;
  bool response_binary = false;
  bool response_truncated = false;
  bool detailed = false;
};

auto requests_of(const chiaki_bridge::HttpTotalsFacts& totals,
                 platform::HttpCredential credential) -> std::uint64_t {
  for (const auto& kind : totals.credentials) {
    if (kind.credential == credential) {
      return kind.tally.requests;
    }
  }
  return 0;
}

void calls_are_listed_newest_first_with_their_totals() {
  Household home;
  const auto before = home.log().revision();
  home.exchange("https://m.np.playstation.com/api/one?code=QUERYSECRET1", 200,
                R"({"access_token":"JSONSECRET1","n":1})");
  home.failure("https://cc.prod.gaikai.com/v1/start");
  assert(home.log().revision() != before);
  Shown shown;
  const auto totals =
      HttpCallsBridge::calls_of(home.log(), Shown::call, &shown);
  assert(shown.rows.size() == 2);
  assert(totals.revision == home.log().revision());
  assert(totals.all.requests == 2);
  assert(totals.all.transport_errors == 1);
  assert(totals.anonymous.requests == 1);
  assert(requests_of(totals, platform::HttpCredential::account_token) == 1);
  assert(totals.bases.size() == 2);
  assert(totals.bases[0].base == "https://cc.prod.gaikai.com");
  assert(totals.bases[1].base == "https://m.np.playstation.com");

  const auto& failed = shown.rows[0];
  assert(failed.sequence == 2 && failed.failed);
  assert(!failed.status);
  assert(failed.transport_error == platform::HttpError::timed_out);
  assert(failed.area == diagnostics::HttpArea::other);
  assert(failed.credentials.empty());

  const auto& ok = shown.rows[1];
  assert(ok.sequence == 1 && !ok.failed && ok.status == 200);
  assert(ok.attempt == 2 && !ok.transport_error);
  assert(ok.area == diagnostics::HttpArea::catalog);
  assert(
      (ok.credentials == std::vector{platform::HttpCredential::account_token}));
  assert(ok.base == "https://m.np.playstation.com" && ok.method == "POST");
  assert(ok.label == "test.exchange");
  assert(ok.started_at_ms == 1'700'000'000'000);
  assert(ok.duration_us == 2500 && ok.bytes_sent == 3);
  assert(ok.url_spans.size() == 1);
  assert(ok.url.substr(ok.url_spans[0].offset, ok.url_spans[0].length) ==
         "QUERYSECRET1");
  assert(ok.url_spans[0].kind == diagnostics::HttpSecretKind::parameter);

  Shown detail;
  assert(HttpCallsBridge::detail_of(home.log(), 1, Shown::detail, &detail) &&
         detail.detailed);
  assert(detail.request_headers.size() == 1);
  assert(detail.request_headers[0].first == "Authorization");
  const auto& span = detail.request_header_spans[0].front();
  assert(detail.request_headers[0].second.substr(span.offset, span.length) ==
         "SECRETTOKEN1");
  assert(detail.response_body.find("\"access_token\": \"JSONSECRET1\"") !=
         std::string::npos);
  assert(detail.response_spans.size() == 1);
  assert(!detail.response_binary && !detail.response_truncated);
  Shown missing;
  assert(!HttpCallsBridge::detail_of(home.log(), 99, Shown::detail, &missing) &&
         !missing.detailed);
  assert(!HttpCallsBridge::detail_of(home.log(), 1, nullptr, &missing));

  home.log().clear();
  Shown cleared;
  const auto kept =
      HttpCallsBridge::calls_of(home.log(), Shown::call, &cleared);
  assert(cleared.rows.empty() && kept.all.requests == 2);
  home.log().reset_totals();
  const auto reset = HttpCallsBridge::calls_of(home.log(), nullptr, nullptr);
  assert(reset.all.requests == 0 && reset.bases.empty());
}

void marked_text_crosses_with_sorted_spans_inside_the_text() {
  const diagnostics::HttpMarkedText text{
      libchiaking::SecretString{std::string_view{"abcdefghij"}},
      {{.offset = 6, .length = 2, .kind = diagnostics::HttpSecretKind::field},
       {.offset = 0, .length = 3, .kind = diagnostics::HttpSecretKind::cookie},
       {.offset = 2, .length = 2, .kind = diagnostics::HttpSecretKind::body},
       {.offset = 8, .length = 99, .kind = diagnostics::HttpSecretKind::body}}};
  const auto view = HttpCallsBridge::marked_of(text);
  assert(Shown::text_of(view) == "abcdefghij");
  std::size_t end = 0;
  for (const auto& span : view.spans) {
    assert(span.length > 0 && span.offset >= end);
    end = span.offset + span.length;
    assert(end <= view.size);
  }
  assert(view.spans.front().offset == 0 && view.spans.front().length == 4);
}

void the_entry_points_answer_nothing_without_a_core() {
  assert(HttpCallsBridge::revision() == 0);
  Shown shown;
  assert(!HttpCallsBridge::calls(Shown::call, &shown));
  assert(!HttpCallsBridge::detail(1, Shown::detail, &shown));
  HttpCallsBridge::clear();
  HttpCallsBridge::reset_totals();
  HttpCallsBridge::drop_connections("test");
  assert(shown.rows.empty());
}

}  // namespace

int main() {
  calls_are_listed_newest_first_with_their_totals();
  marked_text_crosses_with_sorted_spans_inside_the_text();
  the_entry_points_answer_nothing_without_a_core();
}
