#ifndef NX_BRIDGE_LOG_H
#define NX_BRIDGE_LOG_H
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  NX_LOG_ERROR = 0,
  NX_LOG_WARNING = 1,
  NX_LOG_INFO = 2,
  NX_LOG_VERBOSE = 3,
  NX_LOG_DEBUG = 4
} nx_log_severity;

typedef struct nx_bridge_log nx_bridge_log;
nx_bridge_log* nx_bridge_log_create(void);
void nx_bridge_log_destroy(nx_bridge_log* log);
__attribute__((format(printf, 3, 4))) void nx_bridge_log_write(
    nx_bridge_log* log, nx_log_severity severity, const char* format, ...);
bool nx_bridge_log_read(nx_bridge_log* log, int* severity, char* message,
                        size_t capacity);

#ifdef __cplusplus
}
#endif
#endif
