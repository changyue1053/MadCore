#ifndef MC_COPIED_HTTP_H
#define MC_COPIED_HTTP_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Experimental copied GET mailbox. No Kotlin references, NAPI, platform work or
 * drain evidence. Mutex serializes lookup/copy/close. Caller buffers must remain
 * readable/writable for the duration of each call; never retained. All output
 * pointers must be distinct, and output buffers must not overlap them.
 * IDs are positive process-lifetime monotonic int32 values, never recycled.
 * close/consume invalidate IDs; subsequent lookup returns NOT_FOUND.
 * Hard limits: 4 sessions, 8 unconsumed operations/session, URL 2048 bytes,
 * response 65536 bytes. URL bytes are nonempty ASCII HTTP(S) with no credentials,
 * fragments, whitespace or backslashes; stronger endpoint policy belongs to host.
 * This API is GET-only. URL output is length-delimited, NOT NUL-terminated.
 */
enum { MC_HTTP_INVALID_ARGUMENT=-1, MC_HTTP_NOT_FOUND=-2, MC_HTTP_CAPACITY=-3,
       MC_HTTP_ID_EXHAUSTED=-4, MC_HTTP_BUFFER_TOO_SMALL=-5 };
enum { MC_HTTP_PENDING=1, MC_HTTP_RESPONSE=2, MC_HTTP_FAILURE=3, MC_HTTP_CANCELLED=4 };
enum { MC_HTTP_ERROR_IO=1, MC_HTTP_ERROR_TIMEOUT=2, MC_HTTP_ERROR_TOO_LARGE=3 };
int32_t mc_http_open(void);
int32_t mc_http_close(int32_t session);
int32_t mc_http_begin(int32_t session,const uint8_t *url,int32_t length,int32_t max_response);
/* 1 dispatched, 0 no queued pending request, negative error. Too-small writes
 * required length but does not dispatch; out_op/out_limit are 0 until successful; out_limit is per-operation cap. */
int32_t mc_http_next_request(int32_t session,int32_t *out_op,uint8_t *url,int32_t capacity,int32_t *out_length,int32_t *out_limit);
int32_t mc_http_state(int32_t session,int32_t operation);
/* Terminal publication may only win once. Complete requires
 * a dispatched operation; fail/cancel may terminate queued operations. Late calls
 * return 0 until consumed/closed, then NOT_FOUND. TooLarge is a terminal FAILURE.
 */
int32_t mc_http_complete(int32_t session,int32_t operation,int32_t status,const uint8_t *body,int32_t length);
int32_t mc_http_fail(int32_t session,int32_t operation,int32_t error);
int32_t mc_http_cancel(int32_t session,int32_t operation);
/* 1 ready (and optionally consumed), 0 pending, negative error. Metadata outputs
 * always required. Body may be NULL iff capacity==0. On BUFFER_TOO_SMALL metadata
 * includes required body length and the result remains ready/unconsumed.
 * Cancellation remains visible until consumed; no reactivation is possible.
 */
int32_t mc_http_poll(int32_t session,int32_t operation,int32_t *state,int32_t *status,int32_t *error,
                     uint8_t *body,int32_t capacity,int32_t *length,int32_t consume);
#ifdef __cplusplus
}
#endif
#endif
