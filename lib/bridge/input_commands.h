#ifndef NX_INPUT_COMMANDS_H
#define NX_INPUT_COMMANDS_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define NX_INPUT_COMMAND_CAPACITY 256
typedef enum {
  NX_INPUT_COMMAND_RUMBLE = 1,
  NX_INPUT_COMMAND_DUALSENSE_RUMBLE,
  NX_INPUT_COMMAND_SWITCH_RUMBLE,
  NX_INPUT_COMMAND_TRIGGERS,
  NX_INPUT_COMMAND_MIC_LIGHT,
  NX_INPUT_COMMAND_SPEAKER,
  NX_INPUT_COMMAND_LIGHT,
  NX_INPUT_COMMAND_DEFAULT_LIGHT,
  NX_INPUT_COMMAND_PLAYER,
  NX_INPUT_COMMAND_MOTION,
  NX_INPUT_COMMAND_WAVEFORM_MODE,
  NX_INPUT_COMMAND_RESET_FEEDBACK
} nx_input_command_kind;
typedef struct {
  nx_input_command_kind kind;
  uint32_t instance;
  union {
    struct {
      uint16_t low, high;
      uint32_t duration;
    } rumble;
    struct {
      uint8_t left, right, trigger_intensity, haptic_intensity;
    } dualsense;
    float amplitude[2];
    struct {
      uint8_t effects[22];
      uint8_t trigger_intensity, haptic_intensity;
    } triggers;
    bool enabled;
    uint32_t rgb;
    int player;
  } value;
} nx_input_command;
typedef struct {
  nx_input_command items[NX_INPUT_COMMAND_CAPACITY];
  size_t head;
  size_t count;
  uint64_t dropped;
} nx_input_commands;
void nx_input_commands_reset(nx_input_commands* commands);
bool nx_input_commands_push(nx_input_commands* commands,
                            const nx_input_command* command);
bool nx_input_commands_pop(nx_input_commands* commands,
                           nx_input_command* command);
void nx_input_commands_forget(nx_input_commands* commands, uint32_t instance);
#ifdef __cplusplus
}
#endif
#endif
