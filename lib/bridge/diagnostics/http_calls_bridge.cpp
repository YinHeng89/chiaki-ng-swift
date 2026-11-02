#include <algorithm>
#include <chrono>

#include "boundary.hpp"
#include "chiaki_bridge/diagnostics.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

namespace diagnostics = libchiaking::diagnostics;
namespace platform = libchiaking::platform;

auto HttpCallsBridge::revision() -> std::uint64_t {
  return Boundary::fenced(std::uint64_t{0}, [] {
    const auto opened = Opened::shared();
    return opened ? opened->chiaki().http_calls().revision() : std::uint64_t{0};
  });
}

auto HttpCallsBridge::calls(HttpCallWatcher watcher, void* context)
    -> std::optional<HttpTotalsFacts> {
  return Boundary::fenced(std::optional<HttpTotalsFacts>{},
                          [&]() -> std::optional<HttpTotalsFacts> {
                            const auto opened = Opened::shared();
                            if (!opened) {
                              return std::nullopt;
                            }
                            return calls_of(opened->chiaki().http_calls(),
                                            watcher, context);
                          });
}

auto HttpCallsBridge::detail(std::uint64_t sequence,
                             HttpCallDetailWatcher watcher, void* context)
    -> bool {
  return Boundary::fenced(false, [&] {
    const auto opened = Opened::shared();
    return opened != nullptr &&
           detail_of(opened->chiaki().http_calls(), sequence, watcher, context);
  });
}

void HttpCallsBridge::clear() {
  Boundary::fenced(0, [] {
    if (const auto opened = Opened::shared()) {
      opened->chiaki().http_calls().clear();
    }
    return 0;
  });
}

void HttpCallsBridge::reset_totals() {
  Boundary::fenced(0, [] {
    if (const auto opened = Opened::shared()) {
      opened->chiaki().http_calls().reset_totals();
    }
    return 0;
  });
}

void HttpCallsBridge::drop_connections(const std::string& reason) {
  Boundary::fenced(0, [&reason] {
    if (const auto opened = Opened::shared()) {
      opened->platform().http_transport().drop_connections(reason);
    }
    return 0;
  });
}

auto HttpCallsBridge::marked_of(const diagnostics::HttpMarkedText& text)
    -> MarkedTextView {
  MarkedTextView view{};
  const auto shown = text.text();
  view.text = reinterpret_cast<const std::uint8_t*>(shown.data());
  view.size = shown.size();
  for (const auto& span : text.spans()) {
    if (span.length == 0 || span.offset >= shown.size()) {
      continue;
    }
    const auto length = std::min(span.length, shown.size() - span.offset);
    if (!view.spans.empty()) {
      auto& last = view.spans.back();
      if (span.offset <= last.offset + last.length) {
        last.length = std::max(last.length, span.offset + length - last.offset);
        continue;
      }
    }
    view.spans.push_back(SecretSpanFacts{span.offset, length, span.kind});
  }
  return view;
}

auto HttpCallsBridge::tally_of(const diagnostics::HttpTally& tally)
    -> HttpTallyFacts {
  return HttpTallyFacts{tally.requests, tally.http_errors,
                        tally.transport_errors, tally.bytes_sent,
                        tally.bytes_received};
}

auto HttpCallsBridge::headers_of(
    const std::vector<diagnostics::HttpMarkedHeader>& headers)
    -> HttpHeaderViews {
  HttpHeaderViews views;
  views.reserve(headers.size());
  for (const auto& header : headers) {
    views.push_back(HttpHeaderView{header.name, marked_of(header.value)});
  }
  return views;
}

auto HttpCallsBridge::body_of(const diagnostics::HttpShownBody& body)
    -> HttpBodyView {
  return HttpBodyView{body.size, body.kept, body.truncated, body.binary,
                      marked_of(body.text)};
}

auto HttpCallsBridge::calls_of(const diagnostics::HttpCallLog& log,
                               HttpCallWatcher watcher, void* context)
    -> HttpTotalsFacts {
  const auto snapshot = log.snapshot();
  HttpTotalsFacts totals{};
  totals.revision = snapshot.revision;
  totals.all = tally_of(snapshot.totals.all);
  totals.anonymous = tally_of(snapshot.totals.anonymous);
  for (const auto& kind : snapshot.totals.credentials) {
    totals.credentials.push_back(
        HttpCredentialTallyFacts{kind.credential, tally_of(kind.tally)});
  }
  for (const auto& base : snapshot.totals.bases) {
    totals.bases.push_back(HttpBaseTallyFacts{base.base, tally_of(base.tally)});
  }
  if (watcher == nullptr) {
    return totals;
  }
  for (const auto& call : snapshot.calls) {
    const auto url = call->url();
    HttpCallView view{};
    view.sequence = call->sequence();
    view.area = call->area();
    for (const auto kind : platform::every_http_credential) {
      if (call->credentials().contains(kind)) {
        view.credentials.push_back(kind);
      }
    }
    view.credential_label = call->credential_label();
    view.label = call->label();
    view.attempt = call->attempt();
    view.method = platform::http_method_name(call->method());
    view.started_at_ms = Timestamp::milliseconds_of(call->started());
    view.duration_us = call->duration().count();
    view.base = call->base();
    view.url = marked_of(url);
    view.status = call->status();
    view.reason = call->reason();
    view.transport_error = call->transport_error();
    view.failed = call->failed();
    view.bytes_sent = call->bytes_sent();
    view.bytes_received = call->bytes_received();
    watcher(&view, context);
  }
  return totals;
}

auto HttpCallsBridge::detail_of(const diagnostics::HttpCallLog& log,
                                std::uint64_t sequence,
                                HttpCallDetailWatcher watcher, void* context)
    -> bool {
  if (watcher == nullptr) {
    return false;
  }
  const auto snapshot = log.snapshot();
  const auto found = std::ranges::find_if(
      snapshot.calls,
      [sequence](const auto& call) { return call->sequence() == sequence; });
  if (found == snapshot.calls.end()) {
    return false;
  }
  const auto& call = **found;
  const auto request_headers = call.request_headers();
  const auto response_headers = call.response_headers();
  const auto request_body = call.request_body();
  const auto response_body = call.response_body();
  const HttpCallDetailView view{
      headers_of(request_headers), body_of(request_body),
      headers_of(response_headers), body_of(response_body)};
  watcher(&view, context);
  return true;
}

}  // namespace chiaki_bridge
