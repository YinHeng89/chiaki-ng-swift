#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CNToneMapSource) {
  CNToneMapSourceNone,
  CNToneMapSourceStream,
  CNToneMapSourceDefault,
};

typedef struct {
  NSUInteger submitted;
  NSUInteger completed;
  NSUInteger rejected;
  NSUInteger noDrawable;
  NSUInteger generatedDrops;
  NSUInteger replacedFrames;
  NSUInteger idleTicks;
  NSUInteger deadlineMisses;
  NSInteger gpuError;
  BOOL spatialUpscaling;
  BOOL advancedSpatial;
  BOOL advancedBudgetFallback;
  NSUInteger sourceWidth;
  NSUInteger sourceHeight;
  NSUInteger outputWidth;
  NSUInteger outputHeight;
  BOOL tenBit;
  BOOL pq;
  BOOL bt2020;
  BOOL layerHDR;
  CNToneMapSource toneMapSource;
  double contentPeakNits;
  double gpuMilliseconds;
  NSInteger presentationFrameRate;
  NSInteger diagnosticMode;
  double width;
  double height;
  BOOL attached;
  NSInteger displayMaximumFPS;
  double displayMaximumEDR;
  double displayPotentialEDR;
  NSUInteger lightMeasurements;
  double lightSeconds;
  double lightPeakNits;
  double lightAverageNits;
  double lightAbovePercent;
  double maxCLL;
  double maxFALL;
  double sessionAbovePercent;
  double sessionNearWhitePercent;
  double markerNits;
  BOOL markerFollowsPointer;
  BOOL markerVisible;
} CNSurfaceStatistics;
