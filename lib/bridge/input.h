#ifndef NX_INPUT_H
#define NX_INPUT_H
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum {
  NX_INPUT_FAMILY_GENERIC = 0,
  NX_INPUT_FAMILY_PLAYSTATION = 1,
  NX_INPUT_FAMILY_XBOX = 2,
  NX_INPUT_FAMILY_NINTENDO = 3
};
typedef struct {
  uint32_t instance;
  uint16_t vendor, product;
  int connection;
  int family;
  bool rumble, rgb, gyro, accel, touchpad, waveform, triggers, hd_rumble;
  char name[128], serial[128], guid[64];
} nx_input_device;
enum {
  NX_INPUT_EVENT_BUTTON = 1,
  NX_INPUT_EVENT_AXIS = 2,
  NX_INPUT_EVENT_REMOVED = 3,
  NX_INPUT_EVENT_ADDED = 4,
  NX_INPUT_EVENT_SENSOR = 5,
  NX_INPUT_EVENT_TOUCH_DOWN = 6,
  NX_INPUT_EVENT_TOUCH_MOTION = 7,
  NX_INPUT_EVENT_TOUCH_UP = 8,
  NX_INPUT_EVENT_TRIGGER_STATE = 9
};
enum { NX_INPUT_SENSOR_ACCEL = 1, NX_INPUT_SENSOR_GYRO = 2 };
typedef struct {
  uint32_t instance;
  int kind, control, value;
  float data[3];
  uint64_t timestamp_us;
} nx_input_event;
bool nx_input_init(void);
void nx_input_quit(void);
bool nx_input_settle(uint32_t timeout_ms);
typedef void (*nx_input_listener)(const nx_input_event* events, int count,
                                  void* context);
void nx_input_set_listener(nx_input_listener listener, void* context);
int nx_input_devices(nx_input_device* devices, int capacity);
int nx_input_events(nx_input_event* events, int capacity);
int nx_input_touch_fingers(uint32_t instance, nx_input_event* events,
                           int capacity);
bool nx_input_motion(uint32_t instance, bool enabled);
bool nx_input_rumble(uint32_t instance, uint16_t low, uint16_t high,
                     uint32_t duration);
bool nx_input_waveform_mode(uint32_t instance, bool enabled);
bool nx_input_waveform(uint32_t instance, const uint8_t* pcm, int size,
                       float gain);
bool nx_input_triggers(uint32_t instance, const uint8_t effects[22],
                       uint8_t trigger_intensity, uint8_t haptic_intensity);
bool nx_input_dualsense_rumble(uint32_t instance, uint8_t left, uint8_t right,
                               uint8_t trigger_intensity,
                               uint8_t haptic_intensity);
bool nx_input_switch_rumble(uint32_t instance, const float amplitude[2]);
bool nx_input_mic_light(uint32_t instance, bool lit);
bool nx_input_dualsense_speaker(uint32_t instance, bool enabled);
void nx_input_reset_feedback(uint32_t instance);
bool nx_input_light(uint32_t instance, uint32_t rgb);
bool nx_input_player(uint32_t instance, int player);
int nx_input_player_index(uint32_t instance);
uint64_t nx_input_now_us(void);
bool nx_input_default_light(uint32_t instance);
#ifdef __cplusplus
}
#endif
#endif
