#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT OSStatus CNCreateAnnexBSample(const uint8_t *bytes, size_t length, id owner,
                                                CMVideoFormatDescriptionRef format, CMTime pts,
                                                CMSampleBufferRef _Nullable *_Nonnull sampleOut);
FOUNDATION_EXPORT OSStatus
CNCreateAnnexBFormat(const uint8_t *bytes, size_t length, BOOL hevc,
                     CMVideoFormatDescriptionRef _Nullable *_Nonnull formatOut);
FOUNDATION_EXPORT NSData *_Nullable CNCopyAnnexBParameterSets(const uint8_t *bytes, size_t length,
                                                              BOOL hevc);
FOUNDATION_EXPORT BOOL CNAnnexBHasPicture(const uint8_t *bytes, size_t length, BOOL hevc);
NS_ASSUME_NONNULL_END
