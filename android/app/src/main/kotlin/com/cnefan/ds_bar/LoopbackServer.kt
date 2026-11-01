package com.cnefan.ds_bar

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder

/**
 * 只绑 127.0.0.1 的一次性 HTTP 服务，用来接 OAuth 回调。
 *
 * 为什么需要它：平台的 redirect_uri 只接受 http://127.0.0.1:PORT/oauth/callback
 * （自定义 scheme 与外部域都会被 50005 拒绝，已实测），所以只能由 App 自己应答。
 *
 * 安全边界：
 *  - 只 bind 环回地址，不监听 0.0.0.0，外部网络无法访问；
 *  - 端口由系统随机分配（bind 0），不写死；
 *  - 只处理一个请求，回完即关，不常驻；
 *  - state 必须与本次授权生成的一致，否则拒绝（防回调劫持）；
 *  - 带超时，避免浏览器没回来时线程永久阻塞。
 *
 * 实现刻意不引 HTTP 框架：只需读一行请求行 + 回一段固定 HTML，约 100 行足够，
 * 体积实测仅 +3.6KB dex（java.net 本来就在包里）。
 */
class LoopbackServer {

    class Callback(val code: String, val state: String)

    /** [onPort] 在绑定成功后立刻回调实际端口，调用方据此生成 redirect_uri。 */
    fun awaitCallback(
        expectedState: String,
        timeoutMs: Int,
        onPort: (Int) -> Unit
    ): Callback {
        val bindAddr = InetAddress.getByName("127.0.0.1")
        ServerSocket().use { server ->
            server.reuseAddress = true
            server.bind(InetSocketAddress(bindAddr, 0), 1)
            server.soTimeout = timeoutMs
            onPort(server.localPort)

            val deadline = System.currentTimeMillis() + timeoutMs
            // 浏览器可能先打一次 /favicon.ico 或空请求，循环到拿到合法回调或超时。
            while (System.currentTimeMillis() < deadline) {
                val socket = try {
                    server.accept()
                } catch (t: java.net.SocketTimeoutException) {
                    break
                }
                socket.use { s ->
                    s.soTimeout = 5_000
                    val result = handle(s, expectedState)
                    if (result != null) return result
                }
            }
        }
        throw PlatformLogin.Failure("timeout", "等待浏览器授权超时")
    }

    /** 处理单个连接；拿到合法回调返回 Callback，否则回 400 并返回 null 继续等。 */
    private fun handle(socket: Socket, expectedState: String): Callback? {
        val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.ISO_8859_1))
        val requestLine = reader.readLine() ?: return null
        // 把请求头读完，但只需要请求行里的目标路径。
        var line: String?
        do {
            line = reader.readLine()
        } while (!line.isNullOrEmpty())

        val parts = requestLine.split(' ')
        if (parts.size < 2 || parts[0] != "GET") {
            respond(socket, 405, page("方法不支持", false))
            return null
        }
        val target = parts[1]
        val path = target.substringBefore('?')
        if (path != PlatformLogin.callbackPath()) {
            respond(socket, 404, page("页面不存在", false))
            return null
        }

        val params = parseQuery(target.substringAfter('?', ""))
        // 平台拒绝授权时会带 error
        val error = params["error"]
        if (!error.isNullOrEmpty()) {
            respond(socket, 200, page("授权被取消", false))
            throw PlatformLogin.Failure("denied", "授权被取消：$error")
        }
        val code = params["code"]
        val state = params["state"]
        if (code.isNullOrEmpty() || state.isNullOrEmpty()) {
            respond(socket, 400, page("回调缺少参数", false))
            return null
        }
        // 逐字节定长比较，避免早退泄露 state 前缀。
        if (!constantTimeEquals(state, expectedState)) {
            respond(socket, 400, page("状态校验失败", false))
            return null
        }
        respond(socket, 200, page("已授权，可以回到 App", true))
        return Callback(code, state)
    }

    private fun respond(socket: Socket, status: Int, html: String) {
        val body = html.toByteArray(Charsets.UTF_8)
        val head = buildString {
            append("HTTP/1.1 ").append(status).append(' ')
            append(if (status == 200) "OK" else "Bad Request").append("\r\n")
            append("Content-Type: text/html; charset=utf-8\r\n")
            append("Content-Length: ").append(body.size).append("\r\n")
            append("Cache-Control: no-store\r\n")
            append("Connection: close\r\n\r\n")
        }
        runCatching {
            socket.getOutputStream().apply {
                write(head.toByteArray(Charsets.ISO_8859_1))
                write(body)
                flush()
            }
        }
    }

    /** 与 App 主题一致的深色提示页，用户授权后会看到这一屏。 */
    private fun page(title: String, ok: Boolean): String {
        val accent = if (ok) "#27A644" else "#D9A03A"
        val mark = if (ok) "&#10003;" else "&#8226;"
        return """<!DOCTYPE html><html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ds-bar</title></head>
<body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:#010102;color:#F7F8F8;font-family:-apple-system,'PingFang SC',sans-serif">
<div style="text-align:center;padding:32px">
<div style="width:56px;height:56px;border-radius:50%;margin:0 auto 18px;
background:rgba(255,255,255,.04);border:1px solid #23252A;display:flex;
align-items:center;justify-content:center;font-size:24px;color:$accent">$mark</div>
<div style="font-size:17px;font-weight:600;letter-spacing:-.2px">$title</div>
<div style="font-size:12.5px;color:#8A8F98;margin-top:8px">${
            if (ok) "可以直接关掉这个页面" else "回到 App 可重试或改用手动填写"
        }</div></div></body></html>"""
    }

    private fun parseQuery(query: String): Map<String, String> {
        if (query.isEmpty()) return emptyMap()
        return query.split('&').mapNotNull { pair ->
            if (pair.isEmpty()) return@mapNotNull null
            val k = pair.substringBefore('=')
            val v = pair.substringAfter('=', "")
            if (k.isEmpty()) null
            else URLDecoder.decode(k, "UTF-8") to URLDecoder.decode(v, "UTF-8")
        }.toMap()
    }

    private fun constantTimeEquals(a: String, b: String): Boolean {
        val x = a.toByteArray(Charsets.UTF_8)
        val y = b.toByteArray(Charsets.UTF_8)
        if (x.size != y.size) return false
        var diff = 0
        for (i in x.indices) diff = diff or (x[i].toInt() xor y[i].toInt())
        return diff == 0
    }
}
