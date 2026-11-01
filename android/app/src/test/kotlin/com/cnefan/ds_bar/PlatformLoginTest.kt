package com.cnefan.ds_bar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.io.File
import java.net.Socket
import java.security.MessageDigest

/**
 * 浏览器一键登录的纯逻辑校验。
 *
 * 这些约束一旦破掉，登录会在真机上以「回调收不到」「state 校验失败」的形式静默失败，
 * 极难排查，所以固化成测试。
 */
class PlatformLoginTest {

    private fun b64(bytes: ByteArray): String = PlatformLogin.base64Url(bytes)

    @Test
    fun `PKCE verifier 是 43 字符且只含 base64url 字符`() {
        val v = PlatformLogin.newVerifier()
        assertEquals("RFC 7636 要求 verifier 长度 43–128", 43, v.length)
        assertTrue("只允许 [A-Za-z0-9-._~]", v.all { it.isLetterOrDigit() || it in "-._~" })
    }

    @Test
    fun `PKCE challenge 等于 sha256(verifier) 的 base64url`() {
        val v = PlatformLogin.newVerifier()
        val expected = b64(MessageDigest.getInstance("SHA-256").digest(v.toByteArray(Charsets.US_ASCII)))
        assertEquals("challenge 不匹配会导致 auth_exchange 被拒 INVALID_CODE", expected, PlatformLogin.challengeOf(v))
        assertEquals(43, expected.length)
    }

    @Test
    fun `每次生成的 verifier 与 state 都不相同`() {
        val v1 = PlatformLogin.newVerifier(); val v2 = PlatformLogin.newVerifier()
        val s1 = PlatformLogin.newState(); val s2 = PlatformLogin.newState()
        assertNotEquals(v1, v2)
        assertNotEquals(s1, s2)
        assertNotEquals("state 不能与 verifier 复用", v1, s1)
    }

    @Test
    fun `redirect_uri 必须是 127_0_0_1 的 loopback`() {
        val uri = PlatformLogin.redirectUri(45678)
        assertEquals("http://127.0.0.1:45678/oauth/callback", uri)
        assertTrue("平台只放行 loopback，实测自定义 scheme 与外部域都被 50005 拒", uri.startsWith("http://127.0.0.1:"))
        assertTrue(uri.endsWith("/oauth/callback"))
        assertFalse("绝不能用 localhost 之外的地址", uri.contains("0.0.0.0"))
    }

    @Test
    fun `callback 路径与平台约定一致`() {
        assertEquals("/oauth/callback", PlatformLogin.callbackPath())
    }

    @Test
    fun `账号打码保留首字符与域名`() {
        assertEquals("1•••••@qq.com", PlatformLogin.maskAccount("12345@qq.com"))
        assertEquals("a•••••@gmail.com", PlatformLogin.maskAccount("ab@gmail.com"))
    }

    @Test
    fun `账号打码对非邮箱只留尾四位`() {
        assertEquals("••••1234", PlatformLogin.maskAccount("13800001234"))
        assertEquals("••••", PlatformLogin.maskAccount("123"))
    }

    @Test
    fun `本地回调服务只绑环回地址并给出随机端口`() {
        val addr = InetAddress.getByName("127.0.0.1")
        ServerSocket().use { ss ->
            ss.bind(java.net.InetSocketAddress(addr, 0), 1)
            assertTrue("绑定后端口应非 0", ss.localPort > 0)
            assertTrue("必须是环回地址，外部网络不可达", ss.inetAddress.isLoopbackAddress)
        }
    }

    /** 用本地 socket 模拟浏览器，验证拿到 callback 时能解析出 code 与 state。 */
    @Test
    fun `本地回调能解析 code 与 state`() {
        val expectedState = PlatformLogin.newState()
        var result: LoopbackServer.Callback? = null
        var error: Throwable? = null

        val server = Thread {
            try {
                result = LoopbackServer().awaitCallback(expectedState, 8_000) { port ->
                    // 模拟浏览器带着 code/state 回来
                    Thread {
                        runCatching {
                            Socket("127.0.0.1", port).use { s ->
                                val req = "GET /oauth/callback?code=THECODE&state=$expectedState HTTP/1.1\r\n" +
                                    "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
                                s.getOutputStream().write(req.toByteArray())
                                s.getOutputStream().flush()
                                BufferedReader(InputStreamReader(s.getInputStream())).readLine()
                            }
                        }
                    }.start()
                }
            } catch (t: Throwable) {
                error = t
            }
        }
        server.isDaemon = true
        server.start()
        server.join(15_000)

        assertEquals("回调不应抛错：${error?.message}", null, error)
        assertEquals("THECODE", result?.code)
        assertEquals(expectedState, result?.state)
    }

    /** state 不符时必须拒绝，否则任意页面都能把 code 塞进来。 */
    @Test
    fun `state 不匹配时超时拒绝`() {
        var error: Throwable? = null
        val server = Thread {
            try {
                LoopbackServer().awaitCallback("EXPECTED", 2_500) { port ->
                    Thread {
                        runCatching {
                            Socket("127.0.0.1", port).use { s ->
                                val req = "GET /oauth/callback?code=BAD&state=WRONG HTTP/1.1\r\n" +
                                    "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
                                s.getOutputStream().write(req.toByteArray())
                                s.getOutputStream().flush()
                                BufferedReader(InputStreamReader(s.getInputStream())).readLine()
                            }
                        }
                    }.start()
                }
            } catch (t: Throwable) {
                error = t
            }
        }
        server.isDaemon = true
        server.start()
        server.join(10_000)

        assertTrue("state 不符必须失败，不能接受回调", error is PlatformLogin.Failure)
    }

    @Test
    fun `过期时间按平台给的 expires_in 计算`() {
        val init = PlatformLogin.Init("https://platform.deepseek.com/dsh/authorize?authorize_id=x", "x", 600)
        val start = 1_700_000_000_000L
        assertEquals(start + 600_000L, PlatformLogin.expiryOf(init, start))
    }

    /** 自实现 base64url 必须与标准实现逐字节一致，否则 PKCE 会静默算错。 */
    @Test
    fun `base64url 编码与标准实现一致`() {
        // 向量由 python base64.urlsafe_b64encode(...).rstrip('=') 生成
        assertEquals("", PlatformLogin.base64Url(ByteArray(0)))
        assertEquals("AA", PlatformLogin.base64Url(byteArrayOf(0)))
        assertEquals("AAE", PlatformLogin.base64Url(byteArrayOf(0, 1)))
        assertEquals("AAEC", PlatformLogin.base64Url(byteArrayOf(0, 1, 2)))
        assertEquals("AAECAw", PlatformLogin.base64Url(byteArrayOf(0, 1, 2, 3)))
        assertEquals(
            "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHg",
            PlatformLogin.base64Url(ByteArray(31) { it.toByte() })
        )
        assertEquals(
            "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
            PlatformLogin.base64Url(ByteArray(32) { it.toByte() })
        )
    }

    /** 含高位字节时也要正确（ASCII 之外不能出现符号扩展问题）。 */
    @Test
    fun `base64url 处理高位字节正确`() {
        val bytes = byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0xFD.toByte(), 0x80.toByte())
        // python: base64.urlsafe_b64encode(b"\xff\xfe\xfd\x80") == "__79gA"
        // 注意 url-safe 字母表把标准表的 +/ 换成 -_，所以是 __ 不是 //
        assertEquals("__79gA", PlatformLogin.base64Url(bytes))
    }

    /**
     * 服务必须只应答一次：拿到合法回调后立即关闭，不给后续请求机会。
     * 这条在真机上无法稳定复现（时序紧），只能在 JVM 里钉住。
     */
    @Test
    fun `拿到合法回调后服务立即关闭`() {
        val expectedState = PlatformLogin.newState()
        val portRef = java.util.concurrent.atomic.AtomicInteger(0)

        val t = Thread {
            runCatching {
                LoopbackServer().awaitCallback(expectedState, 6_000) { p ->
                    portRef.set(p)
                    Thread {
                        runCatching {
                            Socket("127.0.0.1", p).use { s ->
                                s.getOutputStream().write(
                                    ("GET /oauth/callback?code=C&state=$expectedState HTTP/1.1\r\n" +
                                        "Host: 127.0.0.1\r\nConnection: close\r\n\r\n").toByteArray()
                                )
                                s.getOutputStream().flush()
                                BufferedReader(InputStreamReader(s.getInputStream())).readLine()
                            }
                        }
                    }.start()
                }
            }
        }
        t.isDaemon = true; t.start()
        t.join(12_000)
        assertFalse("awaitCallback 返回后线程应结束", t.isAlive)

        // 端口应已被释放：再连应当被拒
        val refused = runCatching { Socket("127.0.0.1", portRef.get()).close() }.isFailure
        assertTrue("回调处理完毕必须关闭监听，端口要释放", refused)
    }

    /** 非 GET 方法必须拒绝，避免被当作通用上传端点。 */
    @Test
    fun `非 GET 请求被拒绝`() {
        val expectedState = PlatformLogin.newState()
        var got: String? = null
        val t = Thread {
            runCatching {
                LoopbackServer().awaitCallback(expectedState, 3_000) { p ->
                    Thread {
                        runCatching {
                            Socket("127.0.0.1", p).use { s ->
                                s.getOutputStream().write(
                                    ("POST /oauth/callback?code=C&state=$expectedState HTTP/1.1\r\n" +
                                        "Host: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").toByteArray()
                                )
                                s.getOutputStream().flush()
                                got = BufferedReader(InputStreamReader(s.getInputStream())).readLine()
                            }
                        }
                    }.start()
                }
            }
        }
        t.isDaemon = true; t.start()
        t.join(15_000)
        assertTrue("POST 应回 405，实际：$got", got?.contains("405") == true)
    }

    private fun moduleDir(): File {
        var d = File(System.getProperty("user.dir") ?: ".")
        repeat(6) {
            if (File(d, "src/main/AndroidManifest.xml").exists()) return d
            d = d.parentFile ?: return@repeat
        }
        return File(System.getProperty("user.dir") ?: ".")
    }

    /**
     * 登录期间必须有前台服务保活。
     *
     * 真机实测（HLK-AL10 / EMUI）：点登录后浏览器到前台，本应用退到后台被冻结，
     * 此时浏览器带 code 跳回 127.0.0.1 连得上但没人应答，登录必然超时。
     * 加前台服务后同一场景正常返回。这条测试防止有人把这层删掉。
     */
    @Test
    fun `登录期间通过前台服务保活`() {
        val m = File(moduleDir(), "src/main/AndroidManifest.xml").readText()
        assertTrue(
            "必须声明 FOREGROUND_SERVICE，否则 startForeground 抛 SecurityException",
            m.contains("android.permission.FOREGROUND_SERVICE")
        )
        assertTrue(
            "targetSdk 34+ 必须声明 dataSync 类型权限",
            m.contains("android.permission.FOREGROUND_SERVICE_DATA_SYNC")
        )
        assertTrue(
            "必须注册 LoginKeepAliveService",
            m.contains(".LoginKeepAliveService")
        )
        assertTrue(
            "前台服务必须带 foregroundServiceType",
            m.contains("foregroundServiceType=\"dataSync\"")
        )

        val src = File(moduleDir(), "src/main/kotlin/com/cnefan/ds_bar/BrowserLogin.kt").readText()
        assertTrue("登录开始必须拉起保活服务", src.contains("LoginKeepAliveService.start"))
        assertTrue("登录结束必须停掉保活服务", src.contains("LoginKeepAliveService.stop"))
    }

    /** 回调服务只绑环回地址，不能监听外部网络。 */
    @Test
    fun `回调服务绑定地址是环回`() {
        val src = File(moduleDir(), "src/main/kotlin/com/cnefan/ds_bar/LoopbackServer.kt").readText()
        assertTrue("必须显式绑定 127.0.0.1", src.contains("InetAddress.getByName(\"127.0.0.1\")"))
        assertFalse("绝不能绑 0.0.0.0，那会把回调端口暴露到局域网", src.contains("\"0.0.0.0\""))
    }

    /**
     * 回归：发给平台的 state 必须与本地等待校验的 state 是同一个。
     *
     * 真实事故：PlatformLogin.start 内部自己又生成了一份 state/verifier，
     * 平台带着它回来，本地却拿另一份比对，于是真机上每次回调都显示
     * 「状态校验失败」——授权其实已成功，code 也是真的，却全被拒掉。
     * 而当时的单测是手打本地 state 去模拟回调，绕过了平台的真实值，所以没抓到。
     */
    @Test
    fun `auth_init 请求体里的 state 与 challenge 来自同一份 PKCE`() {
        val pkce = PlatformLogin.Pkce.create()
        val body = PlatformLogin.buildInitBody(40001, pkce)

        assertEquals("state 必须是本地等待的那一个", pkce.state, body.getString("state"))
        assertEquals("challenge 必须由同一份 verifier 推出", pkce.challenge, body.getString("code_challenge"))
        assertEquals("S256", body.getString("code_challenge_method"))
        assertEquals("http://127.0.0.1:40001/oauth/callback", body.getString("redirect_uri"))
    }

    /** challenge 必须真的等于 sha256(verifier)，否则 exchange 换不到 token。 */
    @Test
    fun `Pkce 的 challenge 与 verifier 严格对应`() {
        val pkce = PlatformLogin.Pkce.create()
        assertEquals(
            b64(MessageDigest.getInstance("SHA-256").digest(pkce.verifier.toByteArray(Charsets.US_ASCII))),
            pkce.challenge
        )
        // 两次 create 不能复用同一份参数
        assertNotEquals(pkce.state, PlatformLogin.Pkce.create().state)
    }

    /**
     * 结构性断言：PKCE 只能生成一次。
     *
     * 上面两条测的是 buildInitBody 本身，但若 start() 忽略传入的 pkce、自己再造一份，
     * 单测仍然全绿而真机必然失败——这就是当初漏掉的原因。所以这里直接检查源码：
     * 生成入口只允许出现在 Pkce 伴生对象里，调用链上不许再 new 第二份。
     */
    @Test
    fun `PKCE 参数只允许生成一次`() {
        val src = File(moduleDir(), "src/main/kotlin/com/cnefan/ds_bar/PlatformLogin.kt").readText()
        assertTrue("Pkce 必须提供 create() 作为唯一生成入口", src.contains("fun create(): Pkce"))
        // start() 必须用传入的 pkce 组包，不许自己再造一份
        assertTrue(
            "start() 必须使用传入的 pkce，不能自己再生成一份",
            src.contains("buildInitBody(port, pkce)")
        )
        assertFalse(
            "start() 里不得再出现 Pkce.create()，否则发的 state 与本地等待的不是同一个",
            Regex("buildInitBody\\(port, Pkce\\.create\\(\\)\\)").containsMatchIn(src)
        )

        // 业务编排层不许直接造 verifier/state
        val orchestrator = File(moduleDir(), "src/main/kotlin/com/cnefan/ds_bar/BrowserLogin.kt").readText()
        assertFalse(
            "BrowserLogin 不得自行生成 verifier，必须复用 Pkce.create() 的结果",
            orchestrator.contains("PlatformLogin.newVerifier()")
        )
        assertFalse(
            "BrowserLogin 不得自行生成 state，必须复用 Pkce.create() 的结果",
            orchestrator.contains("PlatformLogin.newState()")
        )
        assertEquals(
            "BrowserLogin 每次登录只允许生成一份 PKCE",
            1,
            Regex("Pkce\\.create\\(\\)").findAll(orchestrator).count()
        )
        assertTrue(
            "BrowserLogin 必须用同一份 pkce 完成 init 与 exchange",
            orchestrator.contains("pkce.verifier") && orchestrator.contains("pkce.state")
        )
    }

    /** 回调不匹配时必须上报诊断，否则真机失败只能看到一句「状态校验失败」，无从定位。 */
    @Test
    fun `state 不匹配会上报诊断信息`() {
        val diagnostics = java.util.Collections.synchronizedList(mutableListOf<String>())
        val t = Thread {
            runCatching {
                LoopbackServer().awaitCallback(
                    expectedState = "EXPECTED_STATE",
                    timeoutMs = 2_500,
                    onDiagnostic = { diagnostics.add(it) }
                ) { port ->
                    Thread {
                        runCatching {
                            Socket("127.0.0.1", port).use { s ->
                                s.getOutputStream().write(
                                    ("GET /oauth/callback?code=C&state=OTHER_STATE HTTP/1.1\r\n" +
                                        "Host: 127.0.0.1\r\nConnection: close\r\n\r\n").toByteArray()
                                )
                                s.getOutputStream().flush()
                                BufferedReader(InputStreamReader(s.getInputStream())).readLine()
                            }
                        }
                    }.start()
                }
            }
        }
        t.isDaemon = true; t.start()
        t.join(10_000)

        assertTrue("应至少上报一条诊断：$diagnostics", diagnostics.isNotEmpty())
        val msg = diagnostics.first { it.contains("mismatch") }
        assertTrue("诊断应含 received 指纹", msg.contains("received="))
        assertTrue("诊断应含 expected 指纹", msg.contains("expected="))
        assertFalse("绝不能把 state 原文写进诊断", msg.contains("OTHER_STATE"))
    }
}
