@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlinx.cinterop.BetaInteropApi::class)

package com.mad.core.net

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.convert
import kotlinx.cinterop.usePinned
import platform.Foundation.*
import platform.darwin.*

/**
 * Blocking iOS adapter: call off the main thread. An ephemeral session is created per call.
 * No redirects, cookie storage, credential storage, cache, or custom TLS trust overrides.
 * NSURLSession has a single inactivity timeout; the shorter of connect/read limits is used.
 * [callTimeoutMillis] additionally bounds the total wait and cancels the underlying task.
 */
class IosUrlSessionTransport @Throws(IllegalArgumentException::class) constructor(
    private val callTimeoutMillis: Int = 30_000,
) : HttpTransport {
    init { require(callTimeoutMillis > 0) { "Total call timeout must be positive" } }

    @Throws(HttpTransportException::class)
    override fun execute(request: HttpRequest, limits: HttpLimits): HttpResponse {
        if (NSThread.isMainThread) throw HttpTransportException(HttpFailure.InvalidRequest)
        if (request.url.startsWith("http://") && !limits.allowInsecureHttp) throw HttpTransportException(HttpFailure.InvalidRequest)
        if (request.bodySize > limits.maxRequestBytes) throw HttpTransportException(HttpFailure.RequestTooLarge)
        val url = NSURL.URLWithString(request.url) ?: throw HttpTransportException(HttpFailure.InvalidRequest)
        if (url.host.isNullOrEmpty() || url.user != null || url.password != null || url.fragment != null) throw HttpTransportException(HttpFailure.InvalidRequest)
        val port = url.port?.longLongValue
        if (port != null && port !in 1L..65535L) throw HttpTransportException(HttpFailure.InvalidRequest)
        val idle = minOf(limits.connectTimeoutMillis, limits.readTimeoutMillis) / 1000.0
        val native = NSMutableURLRequest.requestWithURL(url).apply {
            setHTTPMethod(request.method.name)
            setTimeoutInterval(idle)
            setCachePolicy(NSURLRequestReloadIgnoringLocalCacheData)
            request.headers.forEach { (name, value) -> setValue(value, forHTTPHeaderField = name) }
            if (request.method == HttpMethod.POST) {
                val bytes = request.body
                setHTTPBody(if (bytes.isEmpty()) NSData() else bytes.usePinned {
                    NSData.create(bytes = it.addressOf(0), length = bytes.size.convert())
                })
            }
        }
        val configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration().apply {
            timeoutIntervalForRequest = idle
            timeoutIntervalForResource = callTimeoutMillis / 1000.0
            HTTPShouldSetCookies = false
            HTTPCookieStorage = null
            URLCredentialStorage = null
            URLCache = null
            requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData
        }
        val delegate = ResponseCollector(limits.maxResponseBytes)
        val queue = NSOperationQueue().apply { maxConcurrentOperationCount = 1 }
        val session = NSURLSession.sessionWithConfiguration(configuration, delegate, queue)
        val task = session.dataTaskWithRequest(native)
        try {
            task.resume()
            val deadline = dispatch_time(DISPATCH_TIME_NOW, callTimeoutMillis.toLong() * 1_000_000L)
            if (dispatch_semaphore_wait(delegate.done, deadline) != 0L) {
                delegate.timeout()
                task.cancel()
            }
            return delegate.result()
        } finally {
            session.invalidateAndCancel()
        }
    }
}

private class ResponseCollector(private val maxBytes: Int) : NSObject(), NSURLSessionDataDelegateProtocol {
    val done = dispatch_semaphore_create(0)
    private val lock = NSLock()
    private var finished = false
    private var failure: HttpFailure? = null
    private var response: NSHTTPURLResponse? = null
    private val data = NSMutableData()

    fun timeout() {
        lock.lock()
        try { if (!finished) { failure = failure ?: HttpFailure.Timeout; finished = true } } finally { lock.unlock() }
    }

    @Throws(HttpTransportException::class)
    fun result(): HttpResponse {
        lock.lock()
        try {
            failure?.let { throw HttpTransportException(it) }
            val http = response ?: throw HttpTransportException(HttpFailure.Io)
            val bytes = ByteArray(data.length.toInt())
            if (bytes.isNotEmpty()) bytes.usePinned { data.getBytes(it.addressOf(0), data.length) }
            val headers = http.allHeaderFields.entries.associate { it.key.toString() to listOf(it.value.toString()) }
            return HttpResponse(http.statusCode.toInt(), headers, bytes)
        } finally { lock.unlock() }
    }

    override fun URLSession(session: NSURLSession, task: NSURLSessionTask,
        willPerformHTTPRedirection: NSHTTPURLResponse, newRequest: NSURLRequest,
        completionHandler: (NSURLRequest?) -> Unit) { completionHandler(null) }

    override fun URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask,
        didReceiveResponse: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Unit) {
        var allow = true
        lock.lock()
        try {
            if (finished) allow = false
            else if (didReceiveResponse !is NSHTTPURLResponse || didReceiveResponse.statusCode !in 100L..599L) {
                failure = HttpFailure.Io; allow = false
            } else if (didReceiveResponse.expectedContentLength > maxBytes) {
                failure = HttpFailure.ResponseTooLarge; allow = false
            } else response = didReceiveResponse
        } finally { lock.unlock() }
        completionHandler(if (allow) NSURLSessionResponseAllow else NSURLSessionResponseCancel)
    }

    override fun URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData: NSData) {
        var cancel = false
        lock.lock()
        try {
            if (!finished && failure == null) {
                if (didReceiveData.length > maxBytes.toULong() - data.length) {
                    failure = HttpFailure.ResponseTooLarge; cancel = true
                } else data.appendData(didReceiveData)
            }
        } finally { lock.unlock() }
        if (cancel) dataTask.cancel()
    }

    override fun URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError: NSError?) {
        lock.lock()
        try {
            if (!finished) {
                if (failure == null && didCompleteWithError != null) failure =
                    if (didCompleteWithError.domain == NSURLErrorDomain && didCompleteWithError.code == NSURLErrorTimedOut) HttpFailure.Timeout else HttpFailure.Io
                finished = true
                dispatch_semaphore_signal(done)
            }
        } finally { lock.unlock() }
    }
}
