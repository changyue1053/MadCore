#include "operation_registry.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    mc_pending p;
    uint64_t drained[MC_PENDING_CAPACITY], tokens[MC_PENDING_CAPACITY];
    mc_pending_init(&p);
    assert(!mc_pending_finish(&p, 0));
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        tokens[i] = mc_pending_begin(&p);
        assert(tokens[i] == i + 1);
    }
    assert(mc_pending_begin(&p) == 0);
    assert(mc_pending_finish(&p, tokens[0]) == 1);
    assert(mc_pending_finish(&p, tokens[0]) == 0);
    uint64_t reused_slot = mc_pending_begin(&p);
    assert(reused_slot > tokens[MC_PENDING_CAPACITY - 1]);
    assert(!mc_pending_finish(&p, tokens[0])); /* stale slot token */
    assert(mc_pending_close(&p, drained) == MC_PENDING_CAPACITY);
    for (size_t i = 0; i < MC_PENDING_CAPACITY; ++i) {
        assert(drained[i] != 0);
        assert(!mc_pending_finish(&p, drained[i]));
        for (size_t j = 0; j < i; ++j) assert(drained[i] != drained[j]);
    }
    assert(!mc_pending_begin(&p));
    assert(mc_pending_close(&p, drained) == 0);

    /* Close at every position among four equivalent terminal contenders. */
    for (int close_at = 0; close_at <= 4; ++close_at) {
        mc_pending_init(&p);
        uint64_t token = mc_pending_begin(&p);
        int terminal_winners = 0;
        size_t shutdown_owners = 0;
        for (int position = 0; position <= 4; ++position) {
            if (position == close_at)
                shutdown_owners += mc_pending_close(&p, drained);
            else
                terminal_winners += mc_pending_finish(&p, token);
        }
        assert(terminal_winners + shutdown_owners == 1);
        assert(mc_pending_close(&p, drained) == 0);
        assert(!mc_pending_finish(&p, token));
        assert(!mc_pending_begin(&p));
    }
    mc_pending_init(&p);
    p.next = UINT64_MAX; /* deterministic exhaustion injection */
    assert(mc_pending_begin(&p) == UINT64_MAX);
    assert(mc_pending_finish(&p, UINT64_MAX));
    assert(!mc_pending_begin(&p)); /* never wrap and alias stale IDs */
    assert(mc_pending_close(&p, drained) == 0);
    puts("Experimental async ownership kernel passed (host only; no NAPI bridge)");
}
