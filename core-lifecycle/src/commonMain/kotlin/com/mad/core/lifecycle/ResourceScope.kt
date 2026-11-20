package com.mad.core.lifecycle

/** Synchronous resource cleanup. Implementations must not block indefinitely. */
fun interface CloseableResource {
    @Throws(Throwable::class)
    fun close()
}

class ScopeClosedException : IllegalStateException("Resource scope is closed")

/** Counts only; never retains resource names, values or exception diagnostics. */
class CloseReport internal constructor(val attempted: Int, val failed: Int)

/** Detach transfers ownership back to the caller WITHOUT closing the resource. */
class ResourceRegistration internal constructor(private val detachAction: () -> Boolean) {
    fun detach(): Boolean = detachAction()
}

/**
 * Thread-confined resource ownership. The host must serialize register/detach/close calls.
 * No scheduling, cancellation, suspend functions, platform lifecycle hooks or global singleton.
 * Closing marks the scope closed first, detaches all ownership, then attempts cleanup in LIFO order.
 * Ordinary Exceptions are counted and isolated. Non-Exception Throwables are rethrown AFTER the
 * cleanup batch, so fatal failures are never silently swallowed. No transaction/rollback promise.
 */
class ResourceScope {
    private class Entry(var resource: CloseableResource?)
    private val entries = mutableListOf<Entry>()
    var isClosed: Boolean = false
        private set

    /** Each registration is distinct: registering the same instance twice closes it twice. */
    @Throws(ScopeClosedException::class)
    fun register(resource: CloseableResource): ResourceRegistration {
        if (isClosed) throw ScopeClosedException() // rejected resource stays caller-owned
        val entry = Entry(resource)
        entries.add(entry)
        return ResourceRegistration {
            if (entry.resource == null) {
                false
            } else {
                entry.resource = null
                entries.remove(entry)
                true
            }
        }
    }

    /** Idempotent and reentrant: subsequent closes return an empty report. */
    @Throws(Throwable::class)
    fun close(): CloseReport {
        if (isClosed) return CloseReport(0, 0)
        isClosed = true
        val pending = entries.mapNotNull { entry ->
            entry.resource.also { entry.resource = null }
        }
        entries.clear()
        var failed = 0
        var fatal: Throwable? = null
        for (resource in pending.asReversed()) {
            try {
                resource.close()
            } catch (failure: Throwable) {
                failed++
                if (failure !is Exception && fatal == null) fatal = failure
            }
        }
        fatal?.let { throw it }
        return CloseReport(pending.size, failed)
    }

    override fun toString(): String = "ResourceScope(isClosed=$isClosed)"
}
