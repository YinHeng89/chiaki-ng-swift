#include <assert.h>
#include <stdio.h>

#include "DecoderState.h"
int main(void) {
  CNDecoderState s = {0};
  assert(!cn_decoder_reserve(&s));
  assert(cn_decoder_start(&s));
  assert(!cn_decoder_start(&s));
  uint64_t generation = s.generation, tickets[4];
  for (int i = 0; i < 4; i++) {
    tickets[i] = cn_decoder_reserve(&s);
    assert(tickets[i]);
  }
  assert(!cn_decoder_reserve(&s));
  assert(!cn_decoder_complete(&s, generation + 1, tickets[0]));
  assert(cn_decoder_complete(&s, generation, tickets[2]));
  assert(!cn_decoder_complete(&s, generation, tickets[2]));
  uint64_t replacement = cn_decoder_reserve(&s);
  assert(replacement);
  assert(cn_decoder_begin_stop(&s));
  assert(!cn_decoder_reserve(&s));
  assert(!cn_decoder_start(&s));
  assert(!cn_decoder_finish_stop(&s));
  for (int i = 0; i < 4; i++) {
    if (i != 2) {
      assert(cn_decoder_complete(&s, generation, tickets[i]));
    }
  }
  assert(cn_decoder_complete(&s, generation, replacement));
  assert(cn_decoder_finish_stop(&s));
  assert(cn_decoder_start(&s));
  uint64_t newTicket = cn_decoder_reserve(&s);
  assert(!cn_decoder_complete(&s, generation, newTicket));
  assert(!cn_decoder_complete(&s, s.generation, tickets[0]));
  assert(cn_decoder_complete(&s, s.generation, newTicket));
  assert(cn_decoder_begin_stop(&s));
  assert(cn_decoder_finish_stop(&s));
  puts(
      "PASS: bounded decoder FSM, overload, draining, restart, stale/duplicate "
      "completions");
}
