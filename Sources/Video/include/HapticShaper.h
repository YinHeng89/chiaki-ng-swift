#ifndef CN_HAPTIC_SHAPER_H
#define CN_HAPTIC_SHAPER_H

#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

enum {
  CNHapticShaperSampleRate = 3000,
  CNHapticShaperMaxPoints = 16,
  CNHapticShaperSliceFrames = 3,
};

typedef enum {
  CNHapticCrossingUnknown = 0,
  CNHapticCrossingNegative = 1,
  CNHapticCrossingPositive = 2,
} CNHapticCrossing;

typedef struct {
  float gate;
  float intensityExponent;
  float rearm;
  float continuousScale;
  float transientBoost;
  float transientSharpness;
  float sharpnessBias;
  float release;
  float slowRate;
  float hysteresis;
  float hysteresisFloor;
  float frequencyRate;
  float sharpnessRate;
  float lowFrequency;
  float frequencyOctaves;
  float transientFloor;
  float transientRatio;
  float transientMargin;
  uint32_t transientRefractory;
  uint32_t longestHalfPeriod;
  float holdFraction;
  float holdLimit;
} CNHapticShaperTuning;

typedef struct {
  CNHapticShaperTuning tuning;
  float envelope;
  float slowEnvelope;
  float frequency;
  float sharpness;
  uint32_t holdSamples;
  uint32_t refractorySamples;
  uint32_t samplesSinceCrossing;
  CNHapticCrossing crossing;
} CNHapticShaperState;

typedef struct {
  float time;
  float intensity;
  float sharpness;
} CNHapticShaperPoint;

typedef struct {
  float time;
  float intensity;
  float sharpness;
} CNHapticShaperTransient;

typedef struct {
  float duration;
  size_t pointCount;
  CNHapticShaperPoint points[CNHapticShaperMaxPoints];
  size_t transientCount;
  CNHapticShaperTransient transient;
} CNHapticShaperBlock;

typedef enum {
  CNHapticScheduleContinue = 0,
  CNHapticScheduleRestart = 1,
  CNHapticScheduleDrop = 2,
} CNHapticScheduleAction;

typedef struct {
  CNHapticScheduleAction action;
  double start;
  double duration;
} CNHapticScheduleDecision;

CNHapticShaperTuning CNHapticShaperDefaultTuning(void);
void CNHapticShaperReset(CNHapticShaperState* state);
void CNHapticShaperResetWithTuning(CNHapticShaperState* state,
                                   const CNHapticShaperTuning* tuning);
float CNHapticShaperIntensity(float amplitude);
float CNHapticShaperContinuousIntensity(float amplitude);
float CNHapticShaperSharpness(float frequency);
void CNHapticShaperAnalyze(CNHapticShaperState* state,
                           const int16_t* interleaved, size_t frames,
                           size_t channel, float gain,
                           CNHapticShaperBlock* block);
CNHapticScheduleDecision CNHapticScheduleBlock(double continuation, double now,
                                               double duration);

#ifdef __cplusplus
}
#endif
#endif
