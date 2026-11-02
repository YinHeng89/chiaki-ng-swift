#import "AnnexBSample.h"
#include <stdint.h>
#include <stdlib.h>
#import "StatusCodes.h"

enum { CNAnnexBMaxBytes = 32 * 1024 * 1024, CNAnnexBMaxParameterSets = 16 };

typedef struct {
  const uint8_t *bytes;
  uint32_t size;
} NAL;
typedef struct {
  NAL *items;
  size_t count;
} NALList;
static size_t prefix(const uint8_t *p, size_t n) {
  if (n >= 4 && !p[0] && !p[1] && !p[2] && p[3] == 1) {
    return 4;
  }
  if (n >= 3 && !p[0] && !p[1] && p[2] == 1) {
    return 3;
  }
  return 0;
}
static OSStatus split(const uint8_t *p, size_t n, NALList *list) {
  list->items = NULL;
  list->count = 0;
  if (!p || !n || n > CNAnnexBMaxBytes || !prefix(p, n)) {
    return CNStatusInvalidParameter;
  }
  list->items = malloc((n / 4 + 1) * sizeof *list->items);
  if (!list->items) {
    return CNStatusOutOfMemory;
  }
  size_t start = 0;
  while (start < n) {
    size_t pre = prefix(p + start, n - start), end = start + pre;
    while (end < n && !prefix(p + end, n - end)) {
      end++;
    }
    size_t payloadEnd = end;

    while (payloadEnd > start + pre && p[payloadEnd - 1] == 0) {
      payloadEnd--;
    }
    if (!pre || payloadEnd == start + pre) {
      free(list->items);
      list->items = NULL;
      list->count = 0;
      return CNStatusInvalidParameter;
    }
    list->items[list->count++] = (NAL){p + start + pre, (uint32_t)(payloadEnd - start - pre)};
    start = end;
  }
  return noErr;
}
static unsigned nalType(NAL nal, BOOL hevc) {
  return hevc ? (nal.bytes[0] >> 1) & 63 : nal.bytes[0] & 31;
}
static int parameterSetIndex(NAL nal, BOOL hevc) {
  if (hevc && nal.size < 2) {
    return -1;
  }
  unsigned type = nalType(nal, hevc);
  if (hevc) {
    return type >= 32 && type <= 34 ? (int)type - 32 : -1;
  }
  return type == 7 ? 0 : type == 8 ? 1 : -1;
}
static BOOL isPicture(NAL nal, BOOL hevc) {
  unsigned type = nalType(nal, hevc);
  return hevc ? type <= 31 : type >= 1 && type <= 5;
}
OSStatus CNCreateAnnexBFormat(const uint8_t *bytes, size_t length, BOOL hevc,
                              CMVideoFormatDescriptionRef *out) {
  if (!out) {
    return CNStatusInvalidParameter;
  }
  *out = NULL;
  NALList nals;
  OSStatus status = split(bytes, length, &nals);
  if (status) {
    return status;
  }
  const uint8_t *sets[CNAnnexBMaxParameterSets] = {0};
  size_t sizes[CNAnnexBMaxParameterSets] = {0};
  size_t count = 0, kinds[3] = {0};
  for (int order = 0; order < 3 && !status; order++) {
    for (size_t i = 0; i < nals.count; i++) {
      if (parameterSetIndex(nals.items[i], hevc) != order) {
        continue;
      }
      if (count == CNAnnexBMaxParameterSets) {
        status = CNStatusInvalidParameter;
        break;
      }
      sets[count] = nals.items[i].bytes;
      sizes[count++] = nals.items[i].size;
      kinds[order]++;
    }
  }
  free(nals.items);
  if (status || !kinds[0] || !kinds[1] || (hevc && !kinds[2])) {
    return CNStatusInvalidParameter;
  }
  return hevc ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(NULL, count, sets, sizes, 4,
                                                                    NULL, out)
              : CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, count, sets, sizes, 4,
                                                                    out);
}
NSData *CNCopyAnnexBParameterSets(const uint8_t *bytes, size_t length, BOOL hevc) {
  NALList nals;
  if (split(bytes, length, &nals)) {
    return nil;
  }
  NSMutableData *sets = nil;
  static const uint8_t start[] = {0, 0, 0, 1};
  for (size_t i = 0; i < nals.count; i++) {
    if (parameterSetIndex(nals.items[i], hevc) < 0) {
      continue;
    }
    if (!sets) {
      sets = [NSMutableData data];
    }
    [sets appendBytes:start length:sizeof start];
    [sets appendBytes:nals.items[i].bytes length:nals.items[i].size];
  }
  free(nals.items);
  return sets;
}
BOOL CNAnnexBHasPicture(const uint8_t *bytes, size_t length, BOOL hevc) {
  NALList nals;
  if (split(bytes, length, &nals)) {
    return NO;
  }
  BOOL picture = NO;
  for (size_t i = 0; i < nals.count && !picture; i++) {
    picture = isPicture(nals.items[i], hevc);
  }
  free(nals.items);
  return picture;
}

static void releaseOwner(void *owner, void *data, size_t size) { CFRelease(owner); }
static void releaseLengths(void *owner, void *data, size_t size) { free(data); }
OSStatus CNCreateAnnexBSample(const uint8_t *bytes, size_t length, id owner,
                              CMVideoFormatDescriptionRef format, CMTime pts,
                              CMSampleBufferRef *out) {
  if (!out) {
    return CNStatusInvalidParameter;
  }
  *out = NULL;
  if (!owner || !format) {
    return CNStatusInvalidParameter;
  }
  NALList nals;
  OSStatus status = split(bytes, length, &nals);
  if (status) {
    return status;
  }
  size_t framingLength = nals.count * 4;
  uint8_t *lengths = malloc(framingLength);
  if (!lengths) {
    free(nals.items);
    return CNStatusOutOfMemory;
  }
  for (size_t i = 0; i < nals.count; i++) {
    uint32_t size = nals.items[i].size;
    lengths[i * 4] = size >> 24;
    lengths[i * 4 + 1] = size >> 16;
    lengths[i * 4 + 2] = size >> 8;
    lengths[i * 4 + 3] = size;
  }
  CMBlockBufferRef framing = NULL;
  CMBlockBufferCustomBlockSource framingSource = {.version = kCMBlockBufferCustomBlockSourceVersion,
                                                  .FreeBlock = releaseLengths,
                                                  .refCon = lengths};
  status = CMBlockBufferCreateWithMemoryBlock(NULL, lengths, framingLength, kCFAllocatorNull,
                                              &framingSource, 0, framingLength, 0, &framing);
  if (status) {
    free(lengths);
    free(nals.items);
    return status;
  }
  CMBlockBufferRef block = NULL;
  status = CMBlockBufferCreateEmpty(NULL, (uint32_t)(nals.count * 2), 0, &block);
  size_t total = 0;
  for (size_t i = 0; !status && i < nals.count; i++) {
    uint32_t size = nals.items[i].size;
    status = CMBlockBufferAppendBufferReference(block, framing, i * 4, 4, 0);
    if (status) {
      break;
    }
    CFTypeRef retained = CFRetain((__bridge CFTypeRef)owner);
    CMBlockBufferCustomBlockSource payload = {.version = kCMBlockBufferCustomBlockSourceVersion,
                                              .FreeBlock = releaseOwner,
                                              .refCon = (void *)retained};
    status = CMBlockBufferAppendMemoryBlock(block, (void *)nals.items[i].bytes, size,
                                            kCFAllocatorNull, &payload, 0, size, 0);
    if (status) {
      CFRelease(retained);
      break;
    }
    char *pointer = NULL;
    size_t contiguous = 0;
    status = CMBlockBufferGetDataPointer(block, total + 4, &contiguous, NULL, &pointer);
    if (status || pointer != (char *)nals.items[i].bytes || contiguous < size) {
      status = CNStatusInvalidParameter;
      break;
    }
    total += 4 + size;
  }
  CFRelease(framing);
  free(nals.items);
  if (!status) {
    CMSampleTimingInfo timing = {kCMTimeInvalid, pts, kCMTimeInvalid};
    status = CMSampleBufferCreateReady(NULL, block, format, 1, 1, &timing, 1, &total, out);
  }
  if (block) {
    CFRelease(block);
  }
  return status;
}
