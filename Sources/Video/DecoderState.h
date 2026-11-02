#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
  CNDecoderIdle,
  CNDecoderRunning,
  CNDecoderDraining,
  CNDecoderStopped
} CNDecoderPhase;
typedef struct {
  CNDecoderPhase phase;
  uint64_t generation, nextTicket, tickets[4];
} CNDecoderState;
static inline bool cn_decoder_start(CNDecoderState* s) {
  if (s->phase != CNDecoderIdle && s->phase != CNDecoderStopped) {
    return false;
  }
  s->generation++;
  s->phase = CNDecoderRunning;
  return true;
}
static inline uint64_t cn_decoder_reserve(CNDecoderState* s) {
  if (s->phase != CNDecoderRunning) {
    return 0;
  }
  for (size_t i = 0; i < 4; i++) {
    if (!s->tickets[i]) {
      return s->tickets[i] = ++s->nextTicket;
    }
  }
  return 0;
}
static inline bool cn_decoder_complete(CNDecoderState* s, uint64_t generation,
                                       uint64_t ticket) {
  if (generation != s->generation || !ticket) {
    return false;
  }
  for (size_t i = 0; i < 4; i++) {
    if (s->tickets[i] == ticket) {
      s->tickets[i] = 0;
      return true;
    }
  }
  return false;
}
static inline bool cn_decoder_begin_stop(CNDecoderState* s) {
  if (s->phase != CNDecoderRunning) {
    return false;
  }
  s->phase = CNDecoderDraining;
  return true;
}
static inline bool cn_decoder_finish_stop(CNDecoderState* s) {
  if (s->phase != CNDecoderDraining) {
    return false;
  }
  for (size_t i = 0; i < 4; i++) {
    if (s->tickets[i]) {
      return false;
    }
  }
  s->phase = CNDecoderStopped;
  return true;
}
