#include "reference_dispatch.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int retain_fail, queue_fail, callback_fail, reenter;
    int retained, released, delivered, queued;
    mc_dispatch *owner;
} fake_host;

static int retain(void *ctx, void *input, void **out) {
    fake_host *h = ctx;
    if (h->retain_fail) return 0;
    int *ref = malloc(sizeof *ref);
    assert(ref != NULL);
    *ref = *(int *)input;
    *out = ref;
    h->retained++;
    return 1;
}
static void release(void *ctx, void *ref) {
    fake_host *h = ctx;
    assert(ref != NULL);
    h->released++;
    free(ref);
}
static int enqueue(void *ctx, uint64_t token) {
    fake_host *h = ctx;
    assert(token != 0);
    if (h->queue_fail) return 0;
    h->queued++;
    return 1;
}
static int complete(void *ctx, void *ref, int result) {
    fake_host *h = ctx;
    assert(*(int *)ref == 42);
    assert(result == 0 || result == 1);
    h->delivered++;
    if (h->reenter) mc_dispatch_close(h->owner);
    return !h->callback_fail;
}
static void setup(mc_dispatch *d, fake_host *h) {
    *h = (fake_host){0};
    h->owner = d;
    mc_dispatch_init(d, (mc_dispatch_ops){h, retain, release, enqueue, complete});
}
int main(void) {
    mc_dispatch d;
    fake_host h;
    int input = 42;
    setup(&d, &h);
    h.retain_fail = 1;
    assert(!mc_dispatch_submit(&d, &input));
    assert(h.retained == 0 && h.queued == 0);
    h.retain_fail = 0; h.queue_fail = 1;
    assert(!mc_dispatch_submit(&d, &input));
    assert(h.retained == 1 && h.released == 1 && h.delivered == 0);
    h.queue_fail = 0;
    uint64_t token = mc_dispatch_submit(&d, &input);
    assert(token);
    h.callback_fail = 1;
    assert(mc_dispatch_finish(&d, token, 0));
    assert(!mc_dispatch_finish(&d, token, 1));
    assert(h.delivered == 1 && h.retained == h.released);

    setup(&d, &h);
    token = mc_dispatch_submit(&d, &input);
    for (int i = 1; i < MC_PENDING_CAPACITY; ++i) assert(mc_dispatch_submit(&d, &input));
    assert(!mc_dispatch_submit(&d, &input));
    assert(h.retained == MC_PENDING_CAPACITY); /* rejected before retain */
    h.reenter = 1;
    assert(mc_dispatch_finish(&d, token, 1)); /* callback closes remaining owners */
    assert(h.delivered == 1 && h.retained == h.released);
    assert(!mc_dispatch_finish(&d, token, 0));
    assert(!mc_dispatch_submit(&d, &input));
    mc_dispatch_close(&d);
    assert(h.retained == h.released);
    /* Queue accepts but delivers nothing: explicit host timeout wins; a late
     * completion cannot double-release. No real timer or platform queue implied. */
    setup(&d, &h);
    token = mc_dispatch_submit(&d, &input);
    assert(token && h.queued == 1 && h.delivered == 0);
    assert(mc_dispatch_finish(&d, token, 1));
    assert(!mc_dispatch_finish(&d, token, 0));
    assert(h.retained == h.released && h.delivered == 1);
    setup(&d, &h);
    token = mc_dispatch_submit(&d, &input);
    mc_dispatch_close(&d); /* accepted work with missing callback on shutdown */
    assert(!mc_dispatch_finish(&d, token, 0));
    assert(h.retained == h.released && h.delivered == 0);
    puts("Abstract reference/dispatch error injection passed; not NAPI execution");
}
