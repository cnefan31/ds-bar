package com.cnefan.ds_bar

import android.content.Context
import android.util.Log

/**
 * 浏览器登录编排：串起 PKCE、本地回调服务、换取凭据与持久化。
 *
 * 状态机：idle → waiting(浏览器授权) → exchanging → success | failed
 * 所有状态变更都通过 [Listener] 回调到 Dart 侧，界面据此切四态。
 *
 * 刻意做成「失败可退」：任何一步出错都只置 failed，不动已有凭据，
 * 手动填 userToken 的老路径始终可用。
 */
object BrowserLogin {

    private const val TAG = "DsBarLogin"

    /** 与设计稿一致：等待浏览器的上限取平台给的有效期。 */
    private const val WAIT_TIMEOUT_MS = 600_000

    @Volatile private var state: State = State.Idle

    /**
     * 当前状态快照。失败信息带稳定的 code，便于界面区分「取消 / 超时 / 被拒 / 协议错」。
     */
    sealed class State {
        object Idle : State()
        class Waiting(val authorizeUrl: String, val expiresAt: Long) : State()
        object Exchanging : State()
        class Success(val accountHint: String?) : State()
        class Failed(val code: String, val message: String) : State()
    }

    data class Snapshot(
        val phase: String,
        val authorizeUrl: String?,
        val expiresAt: Long,
        val accountHint: String?,
        val errorCode: String?,
        val errorMessage: String?,
        val loginMethod: String
    )

    private var worker: Thread? = null
    private var listener: Listener? = null
    private var cancelFlag = false

    fun interface Listener {
        fun onState(snapshot: Snapshot)
    }

    fun setListener(l: Listener?) {
        listener = l
    }

    fun snapshot(context: Context): Snapshot {
        val prefs = DsPrefs(context)
        val s = state
        return Snapshot(
            phase = when (s) {
                is State.Idle -> when {
                    prefs.userToken.isNotBlank() -> "succeeded"
                    else -> "idle"
                }
                is State.Waiting -> "waiting"
                is State.Exchanging -> "exchanging"
                is State.Success -> "succeeded"
                is State.Failed -> "failed"
            },
            authorizeUrl = (s as? State.Waiting)?.authorizeUrl,
            expiresAt = (s as? State.Waiting)?.expiresAt ?: 0L,
            accountHint = when (s) {
                is State.Success -> s.accountHint
                else -> prefs.accountHint.ifBlank { null }
            },
            errorCode = (s as? State.Failed)?.code,
            errorMessage = (s as? State.Failed)?.message,
            loginMethod = prefs.loginMethod
        )
    }

    /** 开始一次登录。已在跑则直接返回当前快照，不重复起线程。 */
    fun start(context: Context, onOpenBrowser: (String) -> Unit): Snapshot {
        if (worker?.isAlive == true) return snapshot(context)
        cancelFlag = false
        val app = context.applicationContext
        // 先起前台服务保活：浏览器会被拉到前台，本应用退到后台后可能被系统冻结，
        // 冻结后本地回调服务就不再应答了（真机实测）。
        LoginKeepAliveService.start(app)
        worker = Thread { runAttempt(app, onOpenBrowser) }.also {
            it.isDaemon = true
            it.start()
        }
        return snapshot(context)
    }

    fun cancel(context: Context) {
        cancelFlag = true
        worker?.interrupt()
        worker = null
        LoginKeepAliveService.stop(context)
        setState(context, State.Failed("cancelled", "已取消"))
    }

    private fun runAttempt(context: Context, onOpenBrowser: (String) -> Unit) {
        // 一次授权只生成一份 PKCE，auth_init 发给平台的、本地校验的、auth_exchange 用的
        // 必须是同一份，否则回调必然「状态校验失败」或换不到 token。
        val pkce = PlatformLogin.Pkce.create()
        val deviceId = DsPrefs(context).loginDeviceId

        var port = 0
        var authorizeUrl: String? = null

        try {
            val cb = LoopbackServer().awaitCallback(
                expectedState = pkce.state,
                timeoutMs = WAIT_TIMEOUT_MS,
                onDiagnostic = { msg -> Log.i(TAG, msg) }
            ) { boundPort ->
                port = boundPort
                Log.i(TAG, "loopback listening on 127.0.0.1:$boundPort")
                val init = PlatformLogin.start(boundPort, deviceId, pkce)
                authorizeUrl = init.authorizeUrl
                Log.i(TAG, "auth_init ok, opening browser")
                setState(
                    context,
                    State.Waiting(init.authorizeUrl, PlatformLogin.expiryOf(init, System.currentTimeMillis()))
                )
                onOpenBrowser(init.authorizeUrl)
            }

            if (cancelFlag) {
                setState(context, State.Failed("cancelled", "已取消"))
                return
            }
            if (authorizeUrl == null) {
                setState(context, State.Failed("protocol", "授权未初始化"))
                return
            }
            if (cb.state != pkce.state) {
                setState(context, State.Failed("state_mismatch", "状态校验失败，请重试"))
                return
            }

            setState(context, State.Exchanging)
            val grant = PlatformLogin.exchange(port, cb.code, pkce.verifier, deviceId)
            val prefs = DsPrefs(context)
            prefs.userToken = grant.token
            prefs.loginMethod = DsPrefs.LOGIN_BROWSER
            prefs.accountHint = grant.accountHint.orEmpty()
            // 换到新凭据后，旧缓存里的用量可能属于别的会话，强制下次刷新。
            prefs.lastRefreshAt = 0L
            setState(context, State.Success(grant.accountHint))
            Log.i(TAG, "browser login ok")
        } catch (f: PlatformLogin.Failure) {
            Log.w(TAG, "login failed: ${f.code} ${f.message}")
            setState(context, State.Failed(f.code, f.message ?: "登录失败"))
        } catch (t: Throwable) {
            Log.e(TAG, "login crashed", t)
            setState(context, State.Failed("unexpected", t.message ?: "登录失败"))
        } finally {
            worker = null
            LoginKeepAliveService.stop(context)
        }
    }

    private fun setState(context: Context, s: State) {
        state = s
        runCatching { listener?.onState(snapshot(context)) }
    }

    /** 放弃浏览器登录，清掉登录方式标记（不动 token 本身）。 */
    fun signOut(context: Context) {
        val prefs = DsPrefs(context)
        prefs.userToken = ""
        prefs.loginMethod = DsPrefs.LOGIN_MANUAL
        prefs.accountHint = ""
        prefs.lastRefreshAt = 0L
        setState(context, State.Idle)
    }
}
