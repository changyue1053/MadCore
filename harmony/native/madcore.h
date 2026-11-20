#ifndef MADCORE_C_ABI_H
#define MADCORE_C_ABI_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int32_t madcore_abi_version(void);
int64_t madcore_epoch_millis(void);
/* Readable buffer required; copied during call, never retained. Length 1..65536. */
int32_t madcore_json_object_valid(const int8_t *bytes, int32_t length);
#ifdef __cplusplus
}
#endif
#endif
