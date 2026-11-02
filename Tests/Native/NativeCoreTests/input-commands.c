#include <stdio.h>

#include "input_commands.h"

static nx_input_command rumble(uint32_t instance, uint16_t low) {
  nx_input_command command = {.kind = NX_INPUT_COMMAND_RUMBLE,
                              .instance = instance};
  command.value.rumble.low = low;
  return command;
}

static nx_input_command waveform(uint32_t instance, bool enabled) {
  nx_input_command command = {.kind = NX_INPUT_COMMAND_WAVEFORM_MODE,
                              .instance = instance};
  command.value.enabled = enabled;
  return command;
}

static int test_order_is_kept(void) {
  nx_input_commands commands;
  nx_input_commands_reset(&commands);
  nx_input_command light = {.kind = NX_INPUT_COMMAND_LIGHT, .instance = 1};
  nx_input_command first = rumble(1, 100);
  if (!nx_input_commands_push(&commands, &first) ||
      !nx_input_commands_push(&commands, &light)) {
    return 1;
  }
  nx_input_command out;
  if (!nx_input_commands_pop(&commands, &out) ||
      out.kind != NX_INPUT_COMMAND_RUMBLE ||
      !nx_input_commands_pop(&commands, &out) ||
      out.kind != NX_INPUT_COMMAND_LIGHT ||
      nx_input_commands_pop(&commands, &out)) {
    return 2;
  }
  return 0;
}

static int test_newest_value_replaces_the_pending_one(void) {
  nx_input_commands commands;
  nx_input_commands_reset(&commands);
  nx_input_command first = rumble(1, 100);
  nx_input_command other = rumble(2, 50);
  nx_input_command second = rumble(1, 900);
  nx_input_commands_push(&commands, &first);
  nx_input_commands_push(&commands, &other);
  nx_input_commands_push(&commands, &second);
  if (commands.count != 2) {
    return 10;
  }
  nx_input_command out;
  nx_input_commands_pop(&commands, &out);
  if (out.instance != 1 || out.value.rumble.low != 900) {
    return 11;
  }
  nx_input_commands_pop(&commands, &out);
  if (out.instance != 2 || out.value.rumble.low != 50) {
    return 12;
  }
  return 0;
}

static int test_waveform_changes_are_barriers(void) {
  nx_input_commands commands;
  nx_input_commands_reset(&commands);
  nx_input_command before = rumble(1, 100);
  nx_input_command off = waveform(1, false);
  nx_input_command after = rumble(1, 900);
  nx_input_command on = waveform(1, true);
  nx_input_command again = waveform(1, false);
  nx_input_commands_push(&commands, &before);
  nx_input_commands_push(&commands, &off);
  nx_input_commands_push(&commands, &after);
  nx_input_commands_push(&commands, &on);
  nx_input_commands_push(&commands, &again);
  if (commands.count != 5) {
    return 20;
  }
  nx_input_command out;
  nx_input_commands_pop(&commands, &out);
  if (out.kind != NX_INPUT_COMMAND_RUMBLE || out.value.rumble.low != 100) {
    return 21;
  }
  nx_input_commands_pop(&commands, &out);
  nx_input_commands_pop(&commands, &out);
  if (out.kind != NX_INPUT_COMMAND_RUMBLE || out.value.rumble.low != 900) {
    return 22;
  }
  return 0;
}

static int test_forgetting_a_controller_drops_its_commands(void) {
  nx_input_commands commands;
  nx_input_commands_reset(&commands);
  nx_input_command gone = rumble(7, 1);
  nx_input_command kept = rumble(8, 2);
  nx_input_command gone_light = {.kind = NX_INPUT_COMMAND_LIGHT, .instance = 7};
  nx_input_commands_push(&commands, &gone);
  nx_input_commands_push(&commands, &kept);
  nx_input_commands_push(&commands, &gone_light);
  nx_input_commands_forget(&commands, 7);
  nx_input_command out;
  if (commands.count != 1 || !nx_input_commands_pop(&commands, &out) ||
      out.instance != 8) {
    return 30;
  }
  return 0;
}

static int test_a_full_queue_drops_and_counts(void) {
  nx_input_commands commands;
  nx_input_commands_reset(&commands);
  for (uint32_t index = 0; index < NX_INPUT_COMMAND_CAPACITY; index++) {
    nx_input_command command = rumble(index + 1, 1);
    if (!nx_input_commands_push(&commands, &command)) {
      return 40;
    }
  }
  nx_input_command overflow = rumble(NX_INPUT_COMMAND_CAPACITY + 1, 1);
  if (nx_input_commands_push(&commands, &overflow) || commands.dropped != 1) {
    return 41;
  }
  nx_input_command update = rumble(1, 2);
  if (!nx_input_commands_push(&commands, &update) ||
      commands.count != NX_INPUT_COMMAND_CAPACITY) {
    return 42;
  }
  nx_input_command out;
  nx_input_commands_pop(&commands, &out);
  nx_input_command after = rumble(9999, 3);
  if (!nx_input_commands_push(&commands, &after)) {
    return 43;
  }
  return 0;
}

int main(void) {
  int (*tests[])(void) = {
      test_order_is_kept,
      test_newest_value_replaces_the_pending_one,
      test_waveform_changes_are_barriers,
      test_forgetting_a_controller_drops_its_commands,
      test_a_full_queue_drops_and_counts,
  };
  for (size_t index = 0; index < sizeof tests / sizeof tests[0]; index++) {
    int result = tests[index]();
    if (result) {
      fprintf(stderr, "input commands test failed: %d\n", result);
      return result;
    }
  }
  return 0;
}
