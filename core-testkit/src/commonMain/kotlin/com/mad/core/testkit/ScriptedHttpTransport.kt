package com.mad.core.testkit

import com.mad.core.net.*

/**
 * Opt-in test double: FIFO responses/failures, no sockets, sleep, retries or request retention.
 * Owner-thread only. Not a network/TLS simulator and not a production fallback.
 * Valid preflight calls consume one outcome, including oversized responses and scripted failures.
 * Rejected cleartext/oversized requests consume none. callCount counts consumed outcomes.
 */
class ScriptedHttpTransport : HttpTransport {
    private class Outcome(val response: HttpResponse?, val failure: HttpFailure?)
    private val outcomes = ArrayDeque<Outcome>()
    var callCount: Int = 0
        private set
    val pendingCount: Int get() = outcomes.size

    fun enqueueResponse(response: HttpResponse) { outcomes.addLast(Outcome(response, null)) }
    fun enqueueFailure(failure: HttpFailure) { outcomes.addLast(Outcome(null, failure)) }

    @Throws(HttpTransportException::class)
    override fun execute(request: HttpRequest, limits: HttpLimits): HttpResponse {
        if (request.url.startsWith("http://") && !limits.allowInsecureHttp) {
            throw HttpTransportException(HttpFailure.InvalidRequest)
        }
        if (request.bodySize > limits.maxRequestBytes) throw HttpTransportException(HttpFailure.RequestTooLarge)
        check(outcomes.isNotEmpty()) { "No scripted HTTP outcome remains" }
        val outcome = outcomes.removeFirst()
        callCount++
        outcome.failure?.let { throw HttpTransportException(it) }
        val response = checkNotNull(outcome.response)
        if (response.bodySize > limits.maxResponseBytes) throw HttpTransportException(HttpFailure.ResponseTooLarge)
        return response
    }

    @Throws(IllegalStateException::class)
    fun assertExhausted() { check(outcomes.isEmpty()) { "Unused scripted HTTP outcomes remain" } }
    override fun toString(): String = "ScriptedHttpTransport(pending=$pendingCount, calls=$callCount)"
}
