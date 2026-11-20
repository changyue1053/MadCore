#ifndef MADCORE_EXPERIMENTAL_OPERATION_REGISTRY_H
#define MADCORE_EXPERIMENTAL_OPERATION_REGISTRY_H
#include <stdint.h>
#include <stddef.h>

/* Contract kernel only. No NAPI/Kotlin handles, threads, payloads or callbacks.
 * Host must serialize EVERY call on one owner thread. Tokens are routing IDs,
 * not security capabilities. Never reuse a registry instance across environments.
 */
#define MC_PENDING_CAPACITY 16

typedef struct {
    uint64_t next;
    uint64_t active[MC_PENDING_CAPACITY];
    int closed;
} mc_pending;

static inline void mc_pending_init(mc_pending *p) {
    p->next = 1;
    p->closed = 0;
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) p->active[i] = 0;
}

/* Zero means rejected: closed, exhausted IDs, or capacity. No ownership taken.
 * On success the caller must attach bounded request/reference ownership before
 * dispatch. If dispatch fails, finish() rolls back exactly that operation.
 */
static inline uint64_t mc_pending_begin(mc_pending *p) {
    if (p->closed || p->next == 0) return 0;
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        if (p->active[i] == 0) {
            uint64_t token = p->next;
            p->next = token == UINT64_MAX ? 0 : token + 1;
            p->active[i] = token;
            return token;
        }
    }
    return 0;
}

/* Completion/cancel/timeout/dispatch failure all compete for this transition.
 * Winner removes ownership before any caller cleanup or completion callback.
 * Losers must not release references or deliver a second result.
 */
static inline int mc_pending_finish(mc_pending *p, uint64_t token) {
    if (token == 0) return 0;
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        if (p->active[i] == token) {
            p->active[i] = 0;
            return 1;
        }
    }
    return 0;
}

/* Caller provides capacity-sized output. Detach everything and close BEFORE
 * caller cleanup. It owns returned tokens and must cancel/release each once.
 * No callbacks run here; late/reentrant finishes cannot reclaim them.
 */
static inline size_t mc_pending_close(mc_pending *p, uint64_t out[MC_PENDING_CAPACITY]) {
    p->closed = 1;
    size_t count = 0;
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        if (p->active[i]) out[count++] = p->active[i];
        p->active[i] = 0;
    }
    return count;
}
#endif
