package com.mad.core.net

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URI

/**
 * JVM/Android blocking transport. Uses platform TLS verification unchanged, disables redirects/caches.
 * Platform proxy/cookie/authenticator hooks may apply. This is not an SSRF firewall or cancellable call.
 * Android hosts need INTERNET permission and must call off the main thread.
 */
class UrlConnectionTransport : HttpTransport {
    @Throws(HttpTransportException::class)
    override fun execute(request: HttpRequest, limits: HttpLimits): HttpResponse {
        if (request.url.startsWith("http://") && !limits.allowInsecureHttp) throw HttpTransportException(HttpFailure.InvalidRequest)
        if (request.bodySize > limits.maxRequestBytes) throw HttpTransportException(HttpFailure.RequestTooLarge)
        val uri = try { URI(request.url) } catch (_: Exception) { throw HttpTransportException(HttpFailure.InvalidRequest) }
        if (uri.host.isNullOrEmpty() || uri.rawUserInfo != null || uri.rawFragment != null || uri.port !in -1..65535 || uri.port == 0) {
            throw HttpTransportException(HttpFailure.InvalidRequest)
        }
        var connection: HttpURLConnection? = null
        try {
            val active = uri.toURL().openConnection() as HttpURLConnection
            connection = active
            active.instanceFollowRedirects = false
            active.useCaches = false
            active.allowUserInteraction = false
            active.connectTimeout = limits.connectTimeoutMillis
            active.readTimeout = limits.readTimeoutMillis
            active.requestMethod = request.method.name
            for ((name, value) in request.headers) active.setRequestProperty(name, value)
            if (request.method == HttpMethod.POST || request.method == HttpMethod.PUT) {
                active.doOutput = true
                val body = request.body
                active.setFixedLengthStreamingMode(body.size)
                active.outputStream.use { it.write(body) }
            }
            val status = active.responseCode
            if (status !in 100..599) throw HttpTransportException(HttpFailure.Io)
            val declaredLength = active.getHeaderFieldLong("Content-Length", -1L)
            if (declaredLength > limits.maxResponseBytes) throw HttpTransportException(HttpFailure.ResponseTooLarge)
            val stream = if (status >= 400) active.errorStream else active.inputStream
            val bytes = ByteArrayOutputStream()
            stream?.use {
                val buffer = ByteArray(8192)
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    if (count > limits.maxResponseBytes - bytes.size()) throw HttpTransportException(HttpFailure.ResponseTooLarge)
                    bytes.write(buffer, 0, count)
                }
            }
            val headers = active.headerFields.entries.filter { it.key != null }.associate { it.key to it.value.toList() }
            return HttpResponse(status, headers, bytes.toByteArray())
        } catch (failure: HttpTransportException) {
            throw failure
        } catch (_: SocketTimeoutException) {
            throw HttpTransportException(HttpFailure.Timeout)
        } catch (_: IOException) {
            throw HttpTransportException(HttpFailure.Io)
        } finally {
            connection?.disconnect()
        }
    }
}
