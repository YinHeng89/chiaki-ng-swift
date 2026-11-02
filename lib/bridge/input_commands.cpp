#include "input_commands.h"

#include <cstddef>
#include <cstdint>
#include <optional>

namespace chiaki_bridge {

class InputCommands {
 public:
  explicit InputCommands(nx_input_commands& storage) noexcept;

  void reset() noexcept;
  auto push(const nx_input_command& command) noexcept -> bool;
  auto pop() noexcept -> std::optional<nx_input_command>;
  void forget(std::uint32_t instance) noexcept;

 private:
  static constexpr std::size_t capacity = NX_INPUT_COMMAND_CAPACITY;

  static auto barrier(nx_input_command_kind kind) noexcept -> bool;

  auto at(std::size_t position) noexcept -> nx_input_command&;
  auto coalesce(const nx_input_command& command) noexcept -> bool;

  nx_input_commands* storage_;
};

InputCommands::InputCommands(nx_input_commands& storage) noexcept
    : storage_(&storage) {}

auto InputCommands::barrier(nx_input_command_kind kind) noexcept -> bool {
  return kind == NX_INPUT_COMMAND_WAVEFORM_MODE ||
         kind == NX_INPUT_COMMAND_RESET_FEEDBACK;
}

auto InputCommands::at(std::size_t position) noexcept -> nx_input_command& {
  return storage_->items[(storage_->head + position) % capacity];
}

void InputCommands::reset() noexcept { *storage_ = nx_input_commands{}; }

auto InputCommands::coalesce(const nx_input_command& command) noexcept -> bool {
  if (barrier(command.kind)) {
    return false;
  }
  for (auto position = storage_->count; position > 0; --position) {
    auto& pending = at(position - 1);
    if (pending.instance != command.instance) {
      continue;
    }
    if (barrier(pending.kind)) {
      return false;
    }
    if (pending.kind == command.kind) {
      pending = command;
      return true;
    }
  }
  return false;
}

auto InputCommands::push(const nx_input_command& command) noexcept -> bool {
  if (coalesce(command)) {
    return true;
  }
  if (storage_->count == capacity) {
    ++storage_->dropped;
    return false;
  }
  at(storage_->count) = command;
  ++storage_->count;
  return true;
}

auto InputCommands::pop() noexcept -> std::optional<nx_input_command> {
  if (storage_->count == 0) {
    return std::nullopt;
  }
  const auto command = at(0);
  storage_->head = (storage_->head + 1) % capacity;
  --storage_->count;
  return command;
}

void InputCommands::forget(std::uint32_t instance) noexcept {
  std::size_t kept = 0;
  for (std::size_t position = 0; position < storage_->count; ++position) {
    const auto pending = at(position);
    if (pending.instance != instance) {
      at(kept) = pending;
      ++kept;
    }
  }
  storage_->count = kept;
}

}  // namespace chiaki_bridge

void nx_input_commands_reset(nx_input_commands* commands) {
  if (commands != nullptr) {
    chiaki_bridge::InputCommands{*commands}.reset();
  }
}

bool nx_input_commands_push(nx_input_commands* commands,
                            const nx_input_command* command) {
  return commands != nullptr && command != nullptr &&
         chiaki_bridge::InputCommands{*commands}.push(*command);
}

bool nx_input_commands_pop(nx_input_commands* commands,
                           nx_input_command* command) {
  if (commands == nullptr || command == nullptr) {
    return false;
  }
  const auto next = chiaki_bridge::InputCommands{*commands}.pop();
  if (!next) {
    return false;
  }
  *command = *next;
  return true;
}

void nx_input_commands_forget(nx_input_commands* commands, uint32_t instance) {
  if (commands != nullptr) {
    chiaki_bridge::InputCommands{*commands}.forget(instance);
  }
}
