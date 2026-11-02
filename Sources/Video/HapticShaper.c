#include "HapticShaper.h"

#include <math.h>
#include <string.h>

CNHapticShaperTuning CNHapticShaperDefaultTuning(void) {
  return (CNHapticShaperTuning){
      .gate = 0.03f,
      .intensityExponent = 0.7f,
      .rearm = 0.9f,
      .continuousScale = 0.7f,
      .transientBoost = 0.8f,
      .transientSharpness = 0.7f,
      .sharpnessBias = 0.11f,
      .release = 0.45f,
      .slowRate = 1.0f / 60.0f,
      .hysteresis = 0.12f,
      .hysteresisFloor = 0.0015f,
      .frequencyRate = 0.7f,
      .sharpnessRate = 0.8f,
      .lowFrequency = 40.0f,
      .frequencyOctaves = 3.14f,
      .transientFloor = 0.03f,
      .transientRatio = 1.4f,
      .transientMargin = 0.01f,
      .transientRefractory = 90,
      .longestHalfPeriod = 75,
      .holdFraction = 0.5f,
      .holdLimit = 60.0f,
  };
}

static const float CNHapticInitialFrequency = 150.0f;
static const double CNHapticMinimumLead = 0.004;
static const double CNHapticTargetLead = 0.006;
static const double CNHapticMaximumLead = 0.030;

static float CNHapticClamp(float value, float lower, float upper) {
  return fmaxf(lower, fminf(upper, value));
}

static float CNHapticTunedSharpness(const CNHapticShaperTuning* t,
                                    float frequency);

void CNHapticShaperResetWithTuning(CNHapticShaperState* state,
                                   const CNHapticShaperTuning* tuning) {
  memset(state, 0, sizeof *state);
  state->tuning = *tuning;
  state->frequency = CNHapticInitialFrequency;
  state->sharpness =
      CNHapticTunedSharpness(&state->tuning, CNHapticInitialFrequency);
  state->crossing = CNHapticCrossingUnknown;
}

void CNHapticShaperReset(CNHapticShaperState* state) {
  CNHapticShaperTuning tuning = CNHapticShaperDefaultTuning();
  CNHapticShaperResetWithTuning(state, &tuning);
}

static float CNHapticTunedIntensity(const CNHapticShaperTuning* t,
                                    float amplitude) {
  if (!(amplitude >= t->gate)) {
    return 0;
  }
  return CNHapticClamp(powf(amplitude, t->intensityExponent), 0, 1);
}

static float CNHapticTunedContinuous(const CNHapticShaperTuning* t,
                                     float amplitude) {
  return CNHapticTunedIntensity(t, amplitude) * t->continuousScale;
}

static float CNHapticTunedSharpness(const CNHapticShaperTuning* t,
                                    float frequency) {
  if (!(frequency > t->lowFrequency)) {
    return 0;
  }
  return CNHapticClamp(
      log2f(frequency / t->lowFrequency) / t->frequencyOctaves +
          t->sharpnessBias,
      0, 1);
}

float CNHapticShaperIntensity(float amplitude) {
  CNHapticShaperTuning tuning = CNHapticShaperDefaultTuning();
  return CNHapticTunedIntensity(&tuning, amplitude);
}

float CNHapticShaperContinuousIntensity(float amplitude) {
  CNHapticShaperTuning tuning = CNHapticShaperDefaultTuning();
  return CNHapticTunedContinuous(&tuning, amplitude);
}

float CNHapticShaperSharpness(float frequency) {
  CNHapticShaperTuning tuning = CNHapticShaperDefaultTuning();
  return CNHapticTunedSharpness(&tuning, frequency);
}

static void CNHapticTrackCrossing(CNHapticShaperState* state, float sample) {
  const CNHapticShaperTuning* t = &state->tuning;
  float threshold = fmaxf(state->envelope * t->hysteresis, t->hysteresisFloor);
  CNHapticCrossing next = state->crossing;
  if (sample > threshold) {
    next = CNHapticCrossingPositive;
  } else if (sample < -threshold) {
    next = CNHapticCrossingNegative;
  }
  if (state->samplesSinceCrossing < UINT32_MAX) {
    state->samplesSinceCrossing++;
  }
  if (next == state->crossing) {
    return;
  }
  CNHapticCrossing previous = state->crossing;
  state->crossing = next;
  uint32_t interval = state->samplesSinceCrossing;
  state->samplesSinceCrossing = 0;
  if (previous == CNHapticCrossingUnknown || interval > t->longestHalfPeriod) {
    return;
  }
  float measured = (float)CNHapticShaperSampleRate / (2.0f * (float)interval);
  state->frequency += t->frequencyRate * (measured - state->frequency);
}

static void CNHapticTrackEnvelope(CNHapticShaperState* state, float magnitude) {
  const CNHapticShaperTuning* t = &state->tuning;
  if (magnitude >= state->envelope * t->rearm) {
    state->envelope = fmaxf(state->envelope, magnitude);
    float period =
        (float)CNHapticShaperSampleRate / fmaxf(state->frequency, 1.0f);
    state->holdSamples =
        (uint32_t)CNHapticClamp(period * t->holdFraction, 1.0f, t->holdLimit);
  } else if (state->holdSamples > 0) {
    state->holdSamples--;
  } else {
    state->envelope = fmaxf(state->envelope * t->release, magnitude);
  }
  state->slowEnvelope += t->slowRate * (state->envelope - state->slowEnvelope);
}

void CNHapticShaperAnalyze(CNHapticShaperState* state,
                           const int16_t* interleaved, size_t frames,
                           size_t channel, float gain,
                           CNHapticShaperBlock* block) {
  const CNHapticShaperTuning* t = &state->tuning;
  memset(block, 0, sizeof *block);
  if (!interleaved || frames == 0 || channel > 1) {
    return;
  }
  size_t slices =
      (frames + CNHapticShaperSliceFrames - 1) / CNHapticShaperSliceFrames;
  if (slices > CNHapticShaperMaxPoints - 1) {
    slices = CNHapticShaperMaxPoints - 1;
  }
  float safeGain = isfinite(gain) ? fmaxf(gain, 0) : 0;
  float intensity = 0;
  for (size_t slice = 0; slice < slices; slice++) {
    size_t first = slice * frames / slices;
    size_t last = (slice + 1) * frames / slices;
    float peak = 0;
    for (size_t frame = first; frame < last; frame++) {
      float sample = (float)interleaved[frame * 2 + channel] / 32768.0f;
      float previousSlow = state->slowEnvelope;
      CNHapticTrackEnvelope(state, fabsf(sample));
      CNHapticTrackCrossing(state, sample);
      peak = fmaxf(peak, state->envelope);
      if (state->refractorySamples > 0) {
        state->refractorySamples--;
        continue;
      }
      float level = state->envelope * safeGain;
      if (block->transientCount == 0 && level >= t->transientFloor &&
          state->envelope >
              previousSlow * t->transientRatio + t->transientMargin) {
        block->transientCount = 1;
        block->transient.time = (float)frame / (float)CNHapticShaperSampleRate;
        block->transient.intensity = CNHapticClamp(
            CNHapticTunedIntensity(t, level) * t->transientBoost, 0, 1);
        block->transient.sharpness =
            fmaxf(state->sharpness, t->transientSharpness);
        state->refractorySamples = t->transientRefractory;
      }
    }
    float target = CNHapticTunedSharpness(t, state->frequency);
    state->sharpness += t->sharpnessRate * (target - state->sharpness);
    intensity = CNHapticTunedContinuous(t, peak * safeGain);
    block->points[slice] = (CNHapticShaperPoint){
        .time = (float)first / (float)CNHapticShaperSampleRate,
        .intensity = intensity,
        .sharpness = state->sharpness,
    };
  }
  block->duration = (float)frames / (float)CNHapticShaperSampleRate;
  block->points[slices] = (CNHapticShaperPoint){
      .time = block->duration,
      .intensity = intensity,
      .sharpness = state->sharpness,
  };
  block->pointCount = slices + 1;
}

CNHapticScheduleDecision CNHapticScheduleBlock(double continuation, double now,
                                               double duration) {
  double safeDuration = isfinite(duration) && duration > 0 ? duration : 0;
  if (!isfinite(continuation) || !isfinite(now) ||
      continuation < now + CNHapticMinimumLead) {
    return (CNHapticScheduleDecision){
        .action = CNHapticScheduleRestart,
        .start = now + CNHapticMinimumLead,
        .duration = safeDuration,
    };
  }
  double lead = continuation - now;
  if (lead > CNHapticMaximumLead) {
    return (CNHapticScheduleDecision){
        .action = CNHapticScheduleDrop,
        .start = continuation,
        .duration = 0,
    };
  }
  double shrink = 0;
  if (lead > CNHapticTargetLead) {
    shrink = fmin((lead - CNHapticTargetLead) * 0.5, safeDuration * 0.25);
  }
  return (CNHapticScheduleDecision){
      .action = CNHapticScheduleContinue,
      .start = continuation,
      .duration = safeDuration - shrink,
  };
}
