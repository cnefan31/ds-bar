package com.cnefan.ds_bar

import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID

/**
 * 浏览器一键登录：DeepSeek 平台 OAuth（授权码 + PKCE）。
 *
 * 协议来自 DSH 桌面客户端用的 `deepseek-account-platform`，不是公开的第三方 API：
 *   POST /auth-api/v0/dsh/auth_init     {code_challenge, code_challenge_method, state,
 *                                        redirect_uri, locale, login_source}
 *     → biz_data {authorize_url, authorize_id, expires_in}
 *   POST /auth-api/v0/dsh/auth_exchange {code, code_verifier, redirect_uri, device_id,
 *                                        device_model, os_version}
 *     → biz_data {token, authorized_url, user}
 *
 * 平台约束（均已实测）：
 *   - redirect_uri 只接受 http://127.0.0.1:PORT/oauth/callback，自定义 scheme 与外部域
 *     一律 50005 拒绝。所以必须由 [LoopbackServer] 在手机内接回调。
 *   - PKCE 强制 S256。
 *   - auth_exchange 需要 x-client-platform 等头，缺了返回 422。
 *
 * 本对象只做协议，不碰 UI、不碰存储。
 */
object PlatformLogin {

    private const val BASE = "https://platform.deepseek.com"
    private const val INIT_PATH = "/auth-api/v0/dsh/auth_init"
    private const val EXCHANGE_PATH = "/auth-api/v0/dsh/auth_exchange"
    private const val CALLBACK_PATH = "/oauth/callback"

    /** 平台给的授权页有效期是 600 秒，这里不再自行延长。 */
    private const val DEFAULT_EXPIRES_SECONDS = 600

    /** 与 DsRepository 的 UA 保持一致，避免被当成异常客户端。 */
    private const val UA =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/120.0.0.0 Mobile Safari/537.36"

    /**
     * 一次授权的 PKCE 参数，**必须由调用方生成一次并全程复用**。
     *
     * 曾经踩过的坑：这里和 BrowserLogin 各自生成了一份 state/verifier，
     * 发给平台的是 B、本地校验用的是 A，于是每次回调都「状态校验失败」，
     * 且就算 state 侥幸对上 PKCE 也会因为 verifier 不匹配而换不到 token。
     */
    class Pkce private constructor(val verifier: String, val state: String) {
        val challenge: String = challengeOf(verifier)

        companion object {
            fun create(): Pkce = Pkce(newVerifier(), newState())
        }
    }

    class Init(val authorizeUrl: String, val authorizeId: String, val expiresInSeconds: Int)

    class Grant(val token: String, val accountHint: String?)

    class Failure(val code: String, message: String) : Exception(message)

    // ---------- PKCE ----------

    /** 43 字符的 base64url（无 padding），符合 RFC 7636 对 verifier 的要求。 */
    fun newVerifier(): String = base64Url(SecureRandom().let { r ->
        ByteArray(32).also { r.nextBytes(it) }
    })

    fun challengeOf(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII))
        return base64Url(digest)
    }

    fun newState(): String = base64Url(SecureRandom().let { r ->
        ByteArray(32).also { r.nextBytes(it) }
    })

    /** 设备标识：稳定 UUID，只用于 auth_exchange，不含任何个人信息。 */
    fun newDeviceId(): String = UUID.randomUUID().toString()

    fun callbackPath(): String = CALLBACK_PATH

    fun redirectUri(port: Int): String = "http://127.0.0.1:$port$CALLBACK_PATH"

    /**
     * base64url 无 padding 编码。
     *
     * 不用 android.util.Base64：它在 JVM 单测里是未实现桩（not mocked），
     * 会把 PKCE 的校验挪出可测范围。也不用 java.util.Base64：那是 API 26+，
     * 本项目 minSdk 24。自己实现 20 行，两个问题都没有。
     */
    internal fun base64Url(bytes: ByteArray): String {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        val sb = StringBuilder((bytes.size * 4 + 2) / 3)
        var i = 0
        while (i + 2 < bytes.size) {
            val n = ((bytes[i].toInt() and 0xFF) shl 16) or
                ((bytes[i + 1].toInt() and 0xFF) shl 8) or
                (bytes[i + 2].toInt() and 0xFF)
            sb.append(alphabet[(n ushr 18) and 0x3F])
            sb.append(alphabet[(n ushr 12) and 0x3F])
            sb.append(alphabet[(n ushr 6) and 0x3F])
            sb.append(alphabet[n and 0x3F])
            i += 3
        }
        when (bytes.size - i) {
            1 -> {
                val n = (bytes[i].toInt() and 0xFF) shl 16
                sb.append(alphabet[(n ushr 18) and 0x3F])
                sb.append(alphabet[(n ushr 12) and 0x3F])
            }
            2 -> {
                val n = ((bytes[i].toInt() and 0xFF) shl 16) or
                    ((bytes[i + 1].toInt() and 0xFF) shl 8)
                sb.append(alphabet[(n ushr 18) and 0x3F])
                sb.append(alphabet[(n ushr 12) and 0x3F])
                sb.append(alphabet[(n ushr 6) and 0x3F])
            }
        }
        return sb.toString()
    }

    // ---------- 请求 ----------

    /** 单独抽出请求体，便于单测断言「发给平台的 state 就是本地等待的那个」。 */
    internal fun buildInitBody(port: Int, pkce: Pkce): JSONObject = JSONObject()
        .put("code_challenge", pkce.challenge)
        .put("code_challenge_method", "S256")
        .put("state", pkce.state)
        .put("redirect_uri", redirectUri(port))
        .put("locale", "zh_CN")
        .put("login_source", "desktop")

    fun start(port: Int, deviceId: String, pkce: Pkce): Init {
        val body = buildInitBody(port, pkce)

        val res = DsHttp.postJson(
            "$BASE$INIT_PATH",
            body.toString(),
            clientHeaders(),
            20_000
        )
        val biz = unwrap(res, "授权发起")
        val url = biz.optString("authorize_url")
        if (url.isBlank()) throw Failure("protocol", "授权地址为空")
        // 只允许跳到 platform.deepseek.com，防止响应被篡改成外部域。
        if (!url.startsWith("$BASE/dsh/")) throw Failure("protocol", "授权地址不属于平台域")
        return Init(
            authorizeUrl = url,
            authorizeId = biz.optString("authorize_id"),
            expiresInSeconds = biz.optInt("expires_in", DEFAULT_EXPIRES_SECONDS)
        )
    }

    /**
     * 用回调拿到的 code 换 token。
     *
     * @param accountHint 如果平台返回了 user 信息，尽力取出邮箱/手机号，用于界面显示打码账号；
     *                    拿不到就返回 null，绝不编造。
     */
    fun exchange(port: Int, code: String, verifier: String, deviceId: String): Grant {
        val body = JSONObject()
            .put("code", code)
            .put("code_verifier", verifier)
            .put("redirect_uri", redirectUri(port))
            .put("device_id", deviceId)
            .put("device_model", deviceModel())
            .put("os_version", android.os.Build.VERSION.RELEASE ?: "unknown")

        val res = DsHttp.postJson(
            "$BASE$EXCHANGE_PATH",
            body.toString(),
            clientHeaders(),
            25_000
        )
        val biz = unwrap(res, "换取凭据")
        val token = biz.optString("token")
        if (token.isBlank()) throw Failure("protocol", "平台未返回 token")
        return Grant(token, accountHintOf(biz.opt("user")))
    }

    private fun clientHeaders(): Map<String, String> = mapOf(
        "User-Agent" to UA,
        "x-client-platform" to "web",
        "x-client-version" to "1.0.0",
        "x-client-locale" to "zh_CN",
        "x-client-timezone-offset" to "28800",
        "Referer" to "https://platform.deepseek.com/",
        "Origin" to "https://platform.deepseek.com"
    )

    /**
     * 平台统一信封：{code, msg, data:{biz_code, biz_msg, biz_data}}。
     * code != 0 或 biz_code != 0 都算失败，错误码保留原文便于排查。
     */
    private fun unwrap(res: DsHttp.Response, what: String): JSONObject {
        if (res.status == 429) throw Failure("rate_limited", "请求过于频繁，稍后再试")
        if (res.status !in 200..299) throw Failure("http_${res.status}", "${what}失败（HTTP ${res.status}）")
        val json = runCatching { JSONObject(res.text) }.getOrElse {
            throw Failure("protocol", "${what}返回非 JSON")
        }
        val code = json.optInt("code", -1)
        if (code != 0) {
            throw Failure("api_$code", "${what}被拒绝：${json.optString("msg").ifBlank { "code=$code" }}")
        }
        val data = json.optJSONObject("data") ?: throw Failure("protocol", "${what}缺少 data")
        val bizCode = data.optInt("biz_code", -1)
        if (bizCode != 0) {
            throw Failure("biz_$bizCode", "${what}失败：${data.optString("biz_msg").ifBlank { "biz_code=$bizCode" }}")
        }
        return data.optJSONObject("biz_data") ?: throw Failure("protocol", "${what}缺少 biz_data")
    }

    /** 尽力从 user 对象里找邮箱或手机号，找不到返回 null。 */
    private fun accountHintOf(user: Any?): String? {
        val obj = user as? JSONObject ?: return null
        val candidates = listOf("email", "phone_number", "phone", "mobile", "name", "username")
        for (key in candidates) {
            val v = obj.optString(key).trim()
            if (v.isNotEmpty()) return maskAccount(v)
        }
        return null
    }

    /** 邮箱保留首字符与域名，其余打码；其它形式只留尾 4 位。 */
    fun maskAccount(raw: String): String {
        val at = raw.indexOf('@')
        if (at > 0) {
            val head = raw.substring(0, 1)
            val domain = raw.substring(at)
            return head + "•••••" + domain
        }
        return if (raw.length <= 4) "••••" else "••••" + raw.takeLast(4)
    }

    private fun deviceModel(): String {
        val m = android.os.Build.MODEL ?: "android"
        return m.replace(' ', '-')
    }

    /** 供 UI 显示倒计时用。 */
    fun expiryOf(init: Init, startedAt: Long): Long =
        startedAt + init.expiresInSeconds * 1000L
}
