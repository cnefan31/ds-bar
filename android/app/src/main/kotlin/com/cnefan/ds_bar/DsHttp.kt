package com.cnefan.ds_bar

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

class DsException(val code: String, message: String, val status: Int = 0) : Exception(message)

object DsHttp {

    class Response(val status: Int, val body: ByteArray) {
        val text: String get() = String(body, Charsets.UTF_8)
    }

    fun get(
        url: String,
        headers: Map<String, String> = emptyMap(),
        timeoutMs: Int = 15_000,
        maxBytes: Int = 16 * 1024 * 1024
    ): Response {
        val conn = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (t: Throwable) {
            throw DsException(ERR_FETCH_FAILED, "请求地址无效")
        }
        try {
            conn.requestMethod = "GET"
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.instanceFollowRedirects = true
            conn.setRequestProperty("Accept", "application/json, text/csv, */*")
            headers.forEach { (k, v) -> if (v.isNotBlank()) conn.setRequestProperty(k, v) }
            val status = conn.responseCode
            val stream: InputStream? = if (status in 200..299) conn.inputStream else conn.errorStream
            val bytes = stream?.use { readCapped(it, maxBytes) } ?: ByteArray(0)
            return Response(status, bytes)
        } catch (t: DsException) {
            throw t
        } catch (t: java.net.SocketTimeoutException) {
            throw DsException(ERR_TIMEOUT, "请求超时")
        } catch (t: Throwable) {
            throw DsException(ERR_FETCH_FAILED, t.message ?: "网络请求失败")
        } finally {
            conn.disconnect()
        }
    }

    private fun readCapped(input: InputStream, maxBytes: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val n = input.read(buf)
            if (n <= 0) break
            total += n
            if (total > maxBytes) throw DsException(ERR_INVALID_RESPONSE, "响应过大")
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    const val ERR_TIMEOUT = "timeout"
    const val ERR_FETCH_FAILED = "fetch_failed"
    const val ERR_INVALID_RESPONSE = "invalid_response"
    const val ERR_AUTH_FAILED = "auth_failed"
    const val ERR_MISSING_CREDENTIAL = "missing_credential"
    const val ERR_PLATFORM_AUTH = "platform_auth"
    const val ERR_PLATFORM_RATE_LIMITED = "platform_rate_limited"
    const val ERR_PLATFORM_FAILED = "platform_failed"
}
