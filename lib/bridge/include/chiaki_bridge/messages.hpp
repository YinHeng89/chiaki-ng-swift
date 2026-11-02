#pragma once

#include <cstdint>
#include <libchiaking/messages.hpp>
#include <libchiaking/users.hpp>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "core.hpp"

namespace chiaki_bridge {

/// One message of a conversation, as the app shows it.
struct ChatMessageFacts {
  /// The message's id.
  std::string id;
  /// Whether the message is text rather than a sticker or other media.
  bool text;
  /// The message's text, empty when it is not text.
  std::string body;
  /// The sender's online id.
  std::string sender;
  /// The sender's account id.
  std::string sender_account_id;
  /// Whether the signed-in user sent it.
  bool from_user;
  /// When it was sent, in milliseconds since the epoch.
  std::int64_t sent_ms;
};

/// One conversation of an account, as the app lists it.
struct ConversationFacts {
  /// The conversation's group.
  std::string group_id;
  /// The conversation's thread.
  std::string thread_id;
  /// Whether more than two people are in it.
  bool group;
  /// The conversation's name.
  std::string name;
  /// The members' online ids.
  Texts member_names;
  /// The members' account ids, in the order of `member_names`.
  Texts member_account_ids;
  /// The newest message, when there is one.
  std::optional<ChatMessageFacts> latest;
  /// When it last changed, in milliseconds since the epoch.
  std::int64_t updated_ms;
  /// Whether it holds a message the user has not read.
  bool unread;
  /// Whether the user marked it a favourite.
  bool favorite;
};

/// A page of a conversation's messages.
struct ChatThreadFacts {
  /// The messages, oldest first.
  std::vector<ChatMessageFacts> messages;
  /// Whether no older message is left to read.
  bool complete;
};

/// How listing an account's conversations ended: listed, unanswered or with
/// the core closed.
class ConversationsOutcome {
 public:
  /// The ways the listing can end.
  enum class Kind : std::uint8_t {
    /// PSN listed the conversations.
    listed,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A listing PSN answered.
  static auto listed(std::vector<ConversationFacts> value)
      -> ConversationsOutcome {
    return ConversationsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::listed)>,
             std::move(value)}};
  }

  /// A listing PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> ConversationsOutcome {
    return ConversationsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>, why}};
  }

  /// A listing made while the core was closed.
  static auto closed() -> ConversationsOutcome {
    return ConversationsOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the listing ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The conversations, most recently changed first; valid for `listed`.
  auto conversations() const -> std::vector<ConversationFacts> {
    return std::get<std::to_underlying(Kind::listed)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<std::vector<ConversationFacts>,
                            libchiaking::users::Unanswered, std::monostate>;

  explicit ConversationsOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How reading a page of a conversation ended: read, unanswered or with the
/// core closed.
class ChatThreadOutcome {
 public:
  /// The ways the read can end.
  enum class Kind : std::uint8_t {
    /// PSN returned the page.
    read,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A page PSN returned.
  static auto read(ChatThreadFacts value) -> ChatThreadOutcome {
    return ChatThreadOutcome{Case{
        std::in_place_index<std::to_underlying(Kind::read)>, std::move(value)}};
  }

  /// A read PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> ChatThreadOutcome {
    return ChatThreadOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>, why}};
  }

  /// A read made while the core was closed.
  static auto closed() -> ChatThreadOutcome {
    return ChatThreadOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the read ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The page; valid for `read`.
  auto page() const -> ChatThreadFacts {
    return std::get<std::to_underlying(Kind::read)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<ChatThreadFacts, libchiaking::users::Unanswered,
                            std::monostate>;

  explicit ChatThreadOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// How sending a message ended: sent, unanswered or with the core closed.
class ChatSendOutcome {
 public:
  /// The ways the send can end.
  enum class Kind : std::uint8_t {
    /// PSN took the message.
    sent,
    /// PSN gave no answer.
    unanswered,
    /// The core is not open.
    closed,
  };

  /// A message PSN took.
  static auto sent(ChatMessageFacts value) -> ChatSendOutcome {
    return ChatSendOutcome{Case{
        std::in_place_index<std::to_underlying(Kind::sent)>, std::move(value)}};
  }

  /// A send PSN did not answer.
  static auto unanswered(libchiaking::users::Unanswered why)
      -> ChatSendOutcome {
    return ChatSendOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::unanswered)>, why}};
  }

  /// A send made while the core was closed.
  static auto closed() -> ChatSendOutcome {
    return ChatSendOutcome{
        Case{std::in_place_index<std::to_underlying(Kind::closed)>}};
  }

  /// How the send ended.
  auto kind() const noexcept -> Kind {
    return static_cast<Kind>(held_.index());
  }

  /// The message as sent; valid for `sent`.
  auto message() const -> ChatMessageFacts {
    return std::get<std::to_underlying(Kind::sent)>(held_);
  }

  /// Why PSN gave no answer; valid for `unanswered`.
  auto why_unanswered() const -> libchiaking::users::Unanswered {
    return std::get<std::to_underlying(Kind::unanswered)>(held_);
  }

 private:
  using Case = std::variant<ChatMessageFacts, libchiaking::users::Unanswered,
                            std::monostate>;

  explicit ChatSendOutcome(Case held) : held_(std::move(held)) {}

  Case held_;
};

/// Reads and sends an account's PSN messages through the open core.
class MessagesBridge {
 public:
  /// The account's conversations.
  static auto conversations(const Request& request, const Bytes& account_id)
      -> ConversationsOutcome;
  /// A conversation's newest messages, or the ones before `before` when it is
  /// not empty.
  static auto thread(const Request& request, const Bytes& account_id,
                     const std::string& group_id, const std::string& thread_id,
                     const std::string& before) -> ChatThreadOutcome;
  /// Sends text in a conversation.
  static auto send(const Request& request, const Bytes& account_id,
                   const std::string& group_id, const std::string& thread_id,
                   const std::string& text) -> ChatSendOutcome;
  /// Marks a conversation read up to a message, giving why PSN did not answer
  /// when it did not.
  [[nodiscard]] static auto mark_read(const Request& request,
                                      const Bytes& account_id,
                                      const std::string& group_id,
                                      const std::string& thread_id,
                                      const std::string& message_id)
      -> std::optional<libchiaking::users::Unanswered>;

 private:
  static auto facts_of(const libchiaking::messages::ChatMessage& message)
      -> ChatMessageFacts;
  static auto facts_of(const libchiaking::messages::Conversation& conversation)
      -> ConversationFacts;
  static auto signed_out() -> libchiaking::users::Unanswered;
};

}  // namespace chiaki_bridge
