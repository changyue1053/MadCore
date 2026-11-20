#ifndef MADCORE_EXPERIMENTAL_REFERENCE_DISPATCH_H
#define MADCORE_EXPERIMENTAL_REFERENCE_DISPATCH_H
#include "operation_registry.h"

/* Abstract host adapter, NOT a NAPI implementation. All functions run on the
 * registry owner thread. enqueue must never complete inline and must not retain
 * work on failure. release must not throw/reenter; complete may reenter.
 * A queued token contains no borrowed pointer. Late token delivery is harmless
 * only while the owning dispatcher still exists: shutdown must join/drain the
 * real scheduler before freeing it. That integration is not implemented here.
 */
typedef struct {
    void *context;
    int (*retain)(void *, void *, void **);
    void (*release)(void *, void *);
    int (*enqueue)(void *, uint64_t);
    int (*complete)(void *, void *, int);
} mc_dispatch_ops;

typedef struct {
    mc_pending pending;
    mc_dispatch_ops ops;
    uint64_t tokens[MC_PENDING_CAPACITY];
    void *references[MC_PENDING_CAPACITY];
} mc_dispatch;

static inline void mc_dispatch_init(mc_dispatch *d, mc_dispatch_ops ops) {
    mc_pending_init(&d->pending);
    d->ops = ops;
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        d->tokens[i] = 0;
        d->references[i] = NULL;
    }
}

static inline void *mc_dispatch_detach(mc_dispatch *d, uint64_t token) {
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        if (d->tokens[i] == token) {
            void *ref = d->references[i];
            d->tokens[i] = 0;
            d->references[i] = NULL;
            return ref;
        }
    }
    return NULL;
}

/* 0 rejects without borrowing caller ownership; successful retain is balanced
 * on enqueue failure. retain failure must leave no reference allocated. */
static inline uint64_t mc_dispatch_submit(mc_dispatch *d, void *input) {
    uint64_t token = mc_pending_begin(&d->pending);
    if (!token) return 0;
    void *ref = NULL;
    if (!d->ops.retain(d->ops.context, input, &ref)) {
        (void)mc_pending_finish(&d->pending, token);
        return 0;
    }
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        if (d->tokens[i] == 0) {
            d->tokens[i] = token;
            d->references[i] = ref;
            break;
        }
    }
    if (!d->ops.enqueue(d->ops.context, token)) {
        (void)mc_pending_finish(&d->pending, token);
        d->ops.release(d->ops.context, mc_dispatch_detach(d, token));
        return 0;
    }
    return token;
}

/* Returns 1 if this terminal event won, regardless of user callback failure.
 * Callback failure is isolated; owned reference is always released afterward.
 * Detaching first prevents reentrant close/finish from double-releasing it. */
static inline int mc_dispatch_finish(mc_dispatch *d, uint64_t token, int result) {
    if (!mc_pending_finish(&d->pending, token)) return 0;
    void *ref = mc_dispatch_detach(d, token);
    (void)d->ops.complete(d->ops.context, ref, result);
    d->ops.release(d->ops.context, ref);
    return 1;
}

static inline void mc_dispatch_close(mc_dispatch *d) {
    uint64_t drained[MC_PENDING_CAPACITY];
    size_t count = mc_pending_close(&d->pending, drained);
    for (size_t i = 0; i < count; ++i)
        d->ops.release(d->ops.context, mc_dispatch_detach(d, drained[i]));
}
#endif
