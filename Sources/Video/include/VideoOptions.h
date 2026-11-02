#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CNVideoUpscaler) {
  CNVideoUpscalerDisabled = 0,
  CNVideoUpscalerMetalFX = 1,
  CNVideoUpscalerAdvancedSpatial = 2
};

typedef NS_ENUM(NSInteger, CNVideoDiagnosticMode) {
  CNVideoDiagnosticModeOff = 0,
  CNVideoDiagnosticModeHDRHeatmap = 1,
  CNVideoDiagnosticModeHighlightClipping = 2
};
