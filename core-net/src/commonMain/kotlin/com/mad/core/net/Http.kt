package com.mad.core.net

enum class HttpMethod { GET, POST, PUT, DELETE }
enum class HttpFailure { InvalidRequest, Timeout, Io, ResponseTooLarge, RequestTooLarge }

/** Deliberately excludes URL, headers, payload and underlying exception messages. */
class HttpTransportException(val failure: HttpFailure) : Exception("HTTP transport failure: $failure")

class HttpRequest @Throws(IllegalArgumentException::class) constructor(
    val url: String,
    val method: HttpMethod = HttpMethod.GET,
    headers: Map<String, String> = emptyMap(),
    body: ByteArray = byteArrayOf(),
) {
    private val headerValues: Map<String, String> = headers.toMap()
    val headers: Map<String, String> get() = headerValues.toMap()
    private val payload = body.copyOf()
    val body: ByteArray get() = payload.copyOf()
    val bodySize: Int get() = payload.size
    init {
        require(url.startsWith("https://") || url.startsWith("http://")) { "HTTP(S) URL required" }
        require(url.none { it <= ' ' || it == '\\' } && '#' !in url) { "Invalid URL characters" }
        val authority = url.substringAfter("://").substringBefore('/').substringBefore('?')
        require(authority.isNotEmpty() && '@' !in authority) { "Host required; URL user-info forbidden" }
        require((method != HttpMethod.GET && method != HttpMethod.DELETE) || payload.isEmpty()) { "GET/DELETE request body is unsupported" }
        require(this.headers.keys.map { it.lowercase() }.distinct().size == this.headers.size) { "Duplicate header name" }
        for ((name, value) in this.headers) {
            require(name.isNotEmpty() && name.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' }) { "Invalid header name" }
            require(value.none { it < ' ' || it == '\u007f' }) { "Invalid header value" }
            require(name.lowercase() !in setOf("host", "content-length", "transfer-encoding", "connection")) { "Transport-owned header" }
        }
    }
    override fun toString(): String = "HttpRequest(method=$method, bodySize=$bodySize)"
}

class HttpResponse @Throws(IllegalArgumentException::class) constructor(
    val status: Int,
    headers: Map<String, List<String>>,
    body: ByteArray,
) {
    private val headerValues: Map<String, List<String>> = headers.mapValues { it.value.toList() }
    val headers: Map<String, List<String>> get() = headerValues.mapValues { it.value.toList() }
    private val payload = body.copyOf()
    val body: ByteArray get() = payload.copyOf()
    val bodySize: Int get() = payload.size
    init { require(status in 100..599) { "Invalid HTTP status" } }
    override fun toString(): String = "HttpResponse(status=$status, bodySize=$bodySize)"
}

/** Socket connect/read inactivity limits, NOT an end-to-end deadline or a DNS/write timeout. */
class HttpLimits @Throws(IllegalArgumentException::class) constructor(
    val connectTimeoutMillis: Int = 10_000,
    val readTimeoutMillis: Int = 10_000,
    val maxResponseBytes: Int = 1_048_576,
    val maxRequestBytes: Int = 1_048_576,
    val allowInsecureHttp: Boolean = false,
) {
    init {
        require(connectTimeoutMillis > 0 && readTimeoutMillis > 0) { "Timeouts must be positive" }
        require(maxResponseBytes in 1..16_777_216 && maxRequestBytes in 1..16_777_216) { "Body limits must be 1 byte to 16 MiB" }
    }
}

/** Blocking host adapter. Must enforce limits and disable redirects; invoke off UI threads. */
interface HttpTransport {
    @Throws(HttpTransportException::class)
    fun execute(request: HttpRequest, limits: HttpLimits): HttpResponse
}

/** No implicit authentication, retry policy, logging, remote configuration or global singleton. */
class HttpClient(private val transport: HttpTransport, private val limits: HttpLimits = HttpLimits()) {
    @Throws(HttpTransportException::class)
    fun execute(request: HttpRequest): HttpResponse {
        if (request.url.startsWith("http://") && !limits.allowInsecureHttp) throw HttpTransportException(HttpFailure.InvalidRequest)
        if (request.bodySize > limits.maxRequestBytes) throw HttpTransportException(HttpFailure.RequestTooLarge)
        val response = transport.execute(request, limits)
        if (response.bodySize > limits.maxResponseBytes) throw HttpTransportException(HttpFailure.ResponseTooLarge)
        return response
    }
}
