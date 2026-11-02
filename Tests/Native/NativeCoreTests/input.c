#include "input.h"

#include <SDL3/SDL.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int test_motion_and_touch(SDL_Joystick* joystick, SDL_JoystickID id,
                                 nx_input_event* events) {
  if (nx_input_motion(0, true) || !nx_input_motion(id, true) ||
      !nx_input_settle(1000)) {
    return 29;
  }
  const float accel[3] = {0, SDL_STANDARD_GRAVITY, 0};
  const float gyro[3] = {0.5f, -0.25f, 1};
  if (!SDL_SendJoystickVirtualSensorData(joystick, SDL_SENSOR_ACCEL, 4000000,
                                         accel, 3) ||
      !SDL_SendJoystickVirtualSensorData(joystick, SDL_SENSOR_GYRO, 4000000,
                                         gyro, 3) ||
      !SDL_SetJoystickVirtualTouchpad(joystick, 0, 1, true, 0.25f, 0.75f, 1)) {
    return 30;
  }
  nx_input_settle(1000);
  SDL_SetJoystickVirtualTouchpad(joystick, 0, 1, true, 0.5f, 0.5f, 1);
  nx_input_settle(1000);
  nx_input_event resting[4];
  if (nx_input_touch_fingers(id, resting, 4) != 1 ||
      resting[0].kind != NX_INPUT_EVENT_TOUCH_DOWN || resting[0].control != 1 ||
      resting[0].value != 0 || resting[0].data[0] != 0.5f ||
      nx_input_touch_fingers(0, resting, 4) ||
      nx_input_touch_fingers(id, NULL, 4)) {
    return 35;
  }
  SDL_SetJoystickVirtualTouchpad(joystick, 0, 1, false, 0.5f, 0.5f, 0);
  nx_input_settle(1000);
  int count = nx_input_events(events, 128);
  bool accel_seen = false, gyro_seen = false, down = false, moved = false,
       up = false;
  for (int index = 0; index < count; index++) {
    const nx_input_event* event = &events[index];
    if (event->instance != id) {
      continue;
    }
    if (event->kind == NX_INPUT_EVENT_SENSOR &&
        event->control == NX_INPUT_SENSOR_ACCEL) {
      accel_seen =
          fabsf(event->data[1] - 1) < 0.001f && event->timestamp_us == 4000;
    } else if (event->kind == NX_INPUT_EVENT_SENSOR &&
               event->control == NX_INPUT_SENSOR_GYRO) {
      gyro_seen = event->data[0] == 0.5f && event->data[1] == -0.25f &&
                  event->data[2] == 1;
    } else if (event->kind == NX_INPUT_EVENT_TOUCH_DOWN) {
      down = event->control == 1 && event->value == 0 &&
             event->data[0] == 0.25f && event->data[1] == 0.75f;
    } else if (event->kind == NX_INPUT_EVENT_TOUCH_MOTION) {
      moved = down && event->data[0] == 0.5f;
    } else if (event->kind == NX_INPUT_EVENT_TOUCH_UP) {
      up = moved && event->control == 1;
    }
  }
  if (!accel_seen || !gyro_seen) {
    return 31;
  }
  if (!down || !moved || !up) {
    return 32;
  }
  if (nx_input_touch_fingers(id, resting, 4)) {
    return 36;
  }
  if (!nx_input_motion(id, false) || !nx_input_settle(1000) ||
      !SDL_SendJoystickVirtualSensorData(joystick, SDL_SENSOR_GYRO, 8000000,
                                         gyro, 3)) {
    return 33;
  }
  nx_input_settle(1000);
  count = nx_input_events(events, 128);
  for (int index = 0; index < count; index++) {
    if (events[index].instance == id &&
        events[index].kind == NX_INPUT_EVENT_SENSOR) {
      return 34;
    }
  }
  return 0;
}
static uint32_t virtual_light;
static int virtual_light_calls;
static bool record_virtual_light(void* user, Uint8 red, Uint8 green,
                                 Uint8 blue) {
  (void)user;
  virtual_light = ((uint32_t)red << 16) | ((uint32_t)green << 8) | blue;
  virtual_light_calls++;
  return true;
}
static int virtual_player = -2;
static void record_virtual_player(void* user, int player) {
  (void)user;
  virtual_player = player;
}
static int test_lights(SDL_JoystickID id) {
  if (!nx_input_light(id, 0x2050ff) || !nx_input_settle(1000) ||
      virtual_light != 0x2050ff || virtual_light_calls != 1) {
    return 30;
  }
  if (nx_input_light(id, 0x1000000) || virtual_light_calls != 1 ||
      nx_input_light(0, 0xffffff)) {
    return 31;
  }
  if (!nx_input_player(id, 2) || !nx_input_settle(1000) ||
      virtual_player != 2 ||
      SDL_GetGamepadPlayerIndex(SDL_GetGamepadFromID(id)) != 2) {
    return 32;
  }
  if (nx_input_player_index(id) != 2 || nx_input_player_index(0) != -1 ||
      nx_input_default_light(id) || virtual_light_calls != 1) {
    return 34;
  }
  if (nx_input_player(id, 8) || nx_input_player(id, -2) ||
      !nx_input_player(id, -1) || !nx_input_settle(1000) ||
      virtual_player != -1) {
    return 33;
  }
  return 0;
}
int main(void) {
  if (!nx_input_init() || !nx_input_settle(5000)) {
    return 1;
  }
  SDL_VirtualJoystickDesc description;
  SDL_INIT_INTERFACE(&description);
  description.type = SDL_JOYSTICK_TYPE_GAMEPAD;
  description.naxes = SDL_GAMEPAD_AXIS_COUNT;
  description.nbuttons = SDL_GAMEPAD_BUTTON_COUNT;
  description.button_mask = (1u << SDL_GAMEPAD_BUTTON_COUNT) - 1;
  description.axis_mask = (1u << SDL_GAMEPAD_AXIS_COUNT) - 1;
  description.name = "Synthetic input test";
  SDL_VirtualJoystickTouchpadDesc touchpads[1] = {{.nfingers = 2}};
  SDL_VirtualJoystickSensorDesc sensors[2] = {{SDL_SENSOR_ACCEL, 250},
                                              {SDL_SENSOR_GYRO, 250}};
  description.ntouchpads = 1;
  description.touchpads = touchpads;
  description.nsensors = 2;
  description.sensors = sensors;
  description.SetLED = record_virtual_light;
  description.SetPlayerIndex = record_virtual_player;
  SDL_JoystickID id = SDL_AttachVirtualJoystick(&description);
  if (!id || !nx_input_settle(5000)) {
    return 2;
  }
  nx_input_device devices[32];
  int count = nx_input_devices(devices, 32);
  bool found = false;
  for (int index = 0; index < count; index++) {
    found |= devices[index].instance == id && devices[index].gyro &&
             devices[index].accel && devices[index].touchpad;
  }
  if (nx_input_waveform_mode(id, true) ||
      nx_input_triggers(id, (const uint8_t[22]){0}, 1, 1) ||
      nx_input_dualsense_rumble(id, 1, 1, 1, 1) ||
      nx_input_mic_light(id, true)) {
    return 25;
  }
  if (!found) {
    return 3;
  }
  int light_result = test_lights(id);
  if (light_result) {
    return light_result;
  }
  SDL_Joystick* joystick = SDL_OpenJoystick(id);
  nx_input_event events[128];
  count = nx_input_events(events, 128);
  bool added = false;
  for (int index = 0; index < count; index++) {
    added |= events[index].instance == id && events[index].kind == 4;
  }
  if (!added) {
    return 26;
  }
  if (!SDL_SetJoystickVirtualButton(joystick, SDL_GAMEPAD_BUTTON_SOUTH, true)) {
    return 4;
  }
  nx_input_settle(1000);
  SDL_SetJoystickVirtualButton(joystick, SDL_GAMEPAD_BUTTON_SOUTH, false);
  nx_input_settle(1000);
  count = nx_input_events(events, 128);
  int edges = 0;
  for (int index = 0; index < count; index++) {
    if (events[index].instance == id && events[index].kind == 1 &&
        events[index].control == SDL_GAMEPAD_BUTTON_SOUTH) {
      if (events[index].value != (edges == 0)) {
        return 5;
      }
      edges++;
    }
  }
  int motion_result = test_motion_and_touch(joystick, id, events);
  if (motion_result) {
    return motion_result;
  }
  SDL_CloseJoystick(joystick);
  SDL_DetachVirtualJoystick(id);
  nx_input_settle(1000);
  count = nx_input_events(events, 128);
  bool removed = false;
  for (int index = 0; index < count; index++) {
    removed |= events[index].instance == id && events[index].kind == 3;
  }
  nx_input_quit();
  SDL_Quit();
  if (edges != 2 || !removed) {
    return 6;
  }
  puts(
      "PASS: SDL3 virtual input on the input thread, motion sensors, touchpad "
      "fingers, light bar and "
      "player LED and unsupported "
      "feedback rejection");
  return 0;
}
