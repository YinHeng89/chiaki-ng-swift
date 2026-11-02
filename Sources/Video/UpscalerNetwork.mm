#import "UpscalerNetwork.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <optional>

NS_ASSUME_NONNULL_BEGIN

@interface CNConvolutionWeights : NSObject <MPSCNNConvolutionDataSource>
- (instancetype)initWithInputChannels:(NSUInteger)inputChannels
                       outputChannels:(NSUInteger)outputChannels
                           kernelSize:(NSUInteger)kernelSize
                              weights:(NSData *)weights
                                 bias:(NSData *)bias;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END

@implementation CNConvolutionWeights {
  MPSCNNConvolutionDescriptor *_descriptor;
  NSData *_weights;
  NSData *_bias;
}

- (instancetype)initWithInputChannels:(NSUInteger)inputChannels
                       outputChannels:(NSUInteger)outputChannels
                           kernelSize:(NSUInteger)kernelSize
                              weights:(NSData *)weights
                                 bias:(NSData *)bias {
  self = [super init];
  if (!self) {
    return nil;
  }
  _descriptor =
      [MPSCNNConvolutionDescriptor cnnConvolutionDescriptorWithKernelWidth:kernelSize
                                                              kernelHeight:kernelSize
                                                      inputFeatureChannels:inputChannels
                                                     outputFeatureChannels:outputChannels];
  _weights = weights;
  _bias = bias;
  return self;
}

- (MPSDataType)dataType {
  return MPSDataTypeFloat16;
}

- (MPSCNNConvolutionDescriptor *)descriptor {
  return _descriptor;
}

- (void *)weights {
  return const_cast<void *>(_weights.bytes);
}

- (float *)biasTerms {
  return static_cast<float *>(const_cast<void *>(_bias.bytes));
}

- (BOOL)load {
  return YES;
}

- (void)purge {
}

- (NSString *)label {
  return @"FSRCNNX16";
}

- (id)copyWithZone:(NSZone *)zone {
  return self;
}

@end

@implementation CNUpscalerNetwork {
  NSData *_data;
  NSUInteger _offset;
}

+ (nullable MPSNNGraph *)graphOnDevice:(id<MTLDevice>)device weights:(NSData *)weights {
  return [[[CNUpscalerNetwork alloc] initWithData:weights] graphOnDevice:device];
}

- (instancetype)initWithData:(NSData *)data {
  self = [super init];
  if (self) {
    _data = data;
  }
  return self;
}

- (BOOL)readMagic {
  constexpr std::array<std::uint8_t, 7> magic{'F', 'S', 'X', '1', '6', 0, 1};
  if (_data.length < magic.size() || std::memcmp(_data.bytes, magic.data(), magic.size()) != 0) {
    return NO;
  }
  _offset = magic.size();
  return YES;
}

- (std::optional<std::uint32_t>)next {
  std::uint32_t value = 0;
  if (_offset + sizeof value > _data.length) {
    return std::nullopt;
  }
  [_data getBytes:&value range:NSMakeRange(_offset, sizeof value)];
  _offset += sizeof value;
  return value;
}

- (nullable NSData *)take:(NSUInteger)length {
  if (_offset + length > _data.length) {
    return nil;
  }
  NSData *slice = [_data subdataWithRange:NSMakeRange(_offset, length)];
  _offset += length;
  return slice;
}

- (nullable MPSNNGraph *)graphOnDevice:(id<MTLDevice>)device {
  constexpr std::uint32_t layers = 7;
  if (![self readMagic] || [self next] != layers) {
    return nil;
  }
  MPSNNImageNode *current = [MPSNNImageNode nodeWithHandle:nil];
  MPSNNImageNode *feature = nil;
  NSMutableArray<MPSNNFilterNode *> *nodes = [NSMutableArray array];
  for (std::uint32_t layer = 0; layer < layers; layer++) {
    const auto inputChannels = [self next];
    const auto outputChannels = [self next];
    const auto kernelSize = [self next];
    const auto residual = [self next];
    const auto weightCount = [self next];
    const auto slopeCount = [self next];
    if (!inputChannels || !outputChannels || !kernelSize || !residual || !weightCount ||
        !slopeCount) {
      return nil;
    }
    NSData *weights = [self take:*weightCount * sizeof(std::uint16_t)];
    NSData *bias = [self take:*outputChannels * sizeof(float)];
    NSData *slopes = [self take:*slopeCount * sizeof(float)];
    if (!weights || !bias || !slopes) {
      return nil;
    }
    CNConvolutionWeights *parameters =
        [[CNConvolutionWeights alloc] initWithInputChannels:*inputChannels
                                             outputChannels:*outputChannels
                                                 kernelSize:*kernelSize
                                                    weights:weights
                                                       bias:bias];
    MPSCNNConvolutionNode *convolution = [MPSCNNConvolutionNode nodeWithSource:current
                                                                       weights:parameters];
    [nodes addObject:convolution];
    convolution.paddingPolicy = [MPSNNDefaultPadding
        paddingWithMethod:MPSNNPaddingMethodSizeSame | MPSNNPaddingMethodAlignCentered];
    current = convolution.resultImage;
    if (*residual != 0) {
      MPSNNAdditionNode *addition = [MPSNNAdditionNode nodeWithLeftSource:current
                                                              rightSource:feature];
      [nodes addObject:addition];
      current = addition.resultImage;
    }
    if (*slopeCount != 0) {
      MPSCNNNeuronPReLUNode *prelu = [MPSCNNNeuronPReLUNode nodeWithSource:current aData:slopes];
      [nodes addObject:prelu];
      current = prelu.resultImage;
    }
    if (layer == 0) {
      feature = current;
    }
  }
  if (_offset != _data.length) {
    return nil;
  }
  return [[MPSNNGraph alloc] initWithDevice:device resultImage:current resultImageIsNeeded:YES];
}

@end
