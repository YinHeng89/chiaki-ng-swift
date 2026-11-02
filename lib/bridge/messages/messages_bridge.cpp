#include "boundary.hpp"
#include "chiaki_bridge/messages.hpp"
#include "opened.hpp"

namespace chiaki_bridge {

using libchiaking::users::Unanswered;

auto MessagesBridge::facts_of(const libchiaking::messages::ChatMessage& message)
    -> ChatMessageFacts {
  return ChatMessageFacts{
      message.id,
      message.kind == libchiaking::messages::ChatMessage::Kind::text,
      message.text,
      message.sender,
      message.sender_account_id,
      message.from_user,
      Timestamp::milliseconds_of(message.sent)};
}

auto MessagesBridge::facts_of(
    const libchiaking::messages::Conversation& conversation)
    -> ConversationFacts {
  ConversationFacts facts{conversation.group_id,
                          conversation.thread_id,
                          conversation.group,
                          conversation.name,
                          {},
                          {},
                          std::nullopt,
                          Timestamp::milliseconds_of(conversation.updated),
                          conversation.unread,
                          conversation.favorite};
  for (const auto& member : conversation.members) {
    facts.member_names.push_back(member.online_id);
    facts.member_account_ids.push_back(member.account_id);
  }
  if (conversation.latest) {
    facts.latest = facts_of(*conversation.latest);
  }
  return facts;
}

auto MessagesBridge::signed_out() -> Unanswered {
  return Unanswered{Unanswered::Reason::signed_out};
}

auto MessagesBridge::conversations(const Request& request,
                                   const Bytes& account_id)
    -> ConversationsOutcome {
  return Boundary::fenced(
      ConversationsOutcome::closed(), [&]() -> ConversationsOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return ConversationsOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return ConversationsOutcome::unanswered(signed_out());
        }
        auto listed =
            opened->chiaki().messages().conversations(*user, request.token());
        if (!listed) {
          return ConversationsOutcome::unanswered(listed.error());
        }
        std::vector<ConversationFacts> found;
        for (const auto& conversation : listed.value()) {
          found.push_back(facts_of(conversation));
        }
        return ConversationsOutcome::listed(std::move(found));
      });
}

auto MessagesBridge::thread(const Request& request, const Bytes& account_id,
                            const std::string& group_id,
                            const std::string& thread_id,
                            const std::string& before) -> ChatThreadOutcome {
  return Boundary::fenced(
      ChatThreadOutcome::closed(), [&]() -> ChatThreadOutcome {
        const auto opened = Opened::shared();
        if (!opened) {
          return ChatThreadOutcome::closed();
        }
        const auto user = opened->user(account_id);
        if (!user) {
          return ChatThreadOutcome::unanswered(signed_out());
        }
        auto read = opened->chiaki().messages().thread(
            *user, group_id, thread_id, before, request.token());
        if (!read) {
          return ChatThreadOutcome::unanswered(read.error());
        }
        ChatThreadFacts page{{}, read->complete};
        for (const auto& message : read->messages) {
          page.messages.push_back(facts_of(message));
        }
        return ChatThreadOutcome::read(std::move(page));
      });
}

auto MessagesBridge::send(const Request& request, const Bytes& account_id,
                          const std::string& group_id,
                          const std::string& thread_id, const std::string& text)
    -> ChatSendOutcome {
  return Boundary::fenced(ChatSendOutcome::closed(), [&]() -> ChatSendOutcome {
    const auto opened = Opened::shared();
    if (!opened) {
      return ChatSendOutcome::closed();
    }
    const auto user = opened->user(account_id);
    if (!user) {
      return ChatSendOutcome::unanswered(signed_out());
    }
    auto sent = opened->chiaki().messages().send(*user, group_id, thread_id,
                                                 text, request.token());
    if (!sent) {
      return ChatSendOutcome::unanswered(sent.error());
    }
    return ChatSendOutcome::sent(facts_of(sent.value()));
  });
}

auto MessagesBridge::mark_read(const Request& request, const Bytes& account_id,
                               const std::string& group_id,
                               const std::string& thread_id,
                               const std::string& message_id)
    -> std::optional<Unanswered> {
  const std::optional<Unanswered> closed{
      Unanswered{Unanswered::Reason::unavailable}};
  return Boundary::fenced(closed, [&]() -> std::optional<Unanswered> {
    const auto opened = Opened::shared();
    if (!opened) {
      return closed;
    }
    const auto user = opened->user(account_id);
    if (!user) {
      return signed_out();
    }
    auto marked = opened->chiaki().messages().mark_read(
        *user, group_id, thread_id, message_id, request.token());
    if (!marked) {
      return marked.error();
    }
    return std::nullopt;
  });
}

}  // namespace chiaki_bridge
