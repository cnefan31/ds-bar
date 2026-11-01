package com.cnefan.ds_bar

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 平台鉴权头必须随登录方式切换。
 *
 * 真实事故：浏览器登录拿到的账号 grant 被当成网页 userToken 用
 * `Authorization: Bearer` 发出，平台返回 **HTTP 200 + {"code":40003,
 * "msg":"Authorization Failed (invalid token)"}**。
 * 状态码是 200，只看状态码的检查会认为一切正常，实际余额、用量、
 * Key 列表全是空的——表现就是「登录成功但没有数据」。
 *
 * 平台内部接口（usage / get_user_summary / get_api_keys）认的是
 * `x-dsh-auth-token`；手动粘贴的网页 userToken 认的才是 Bearer。
 * 这两条都不能再退回去。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
class PlatformAuthHeaderTest {

    private fun headersFor(method: String): Map<String, String> {
        val ctx = ApplicationProvider.getApplicationContext<android.content.Context>()
        val p = DsPrefs(ctx)
        p.userToken = "TEST_TOKEN"
        p.cookie = ""
        p.loginMethod = method
        return DsRepository(ctx).platformHeaders()
    }

    @Test
    fun `浏览器登录必须使用 x-dsh-auth-token`() {
        val h = headersFor(DsPrefs.LOGIN_BROWSER)
        assertEquals("TEST_TOKEN", h["x-dsh-auth-token"])
        assertNull(
            "浏览器 grant 不能用 Bearer，否则平台回 200+40003，数据全空",
            h["Authorization"]
        )
    }

    @Test
    fun `手动粘贴的 userToken 仍使用 Bearer`() {
        val h = headersFor(DsPrefs.LOGIN_MANUAL)
        assertEquals("Bearer TEST_TOKEN", h["Authorization"])
        assertNull("网页 userToken 不应带 dsh 头", h["x-dsh-auth-token"])
    }

    @Test
    fun `两种方式都必须带平台身份头`() {
        for (method in listOf(DsPrefs.LOGIN_BROWSER, DsPrefs.LOGIN_MANUAL)) {
            val h = headersFor(method)
            assertEquals("web", h["x-client-platform"])
            assertEquals("zh_CN", h["x-client-locale"])
            assertNotNull("缺 x-client-version 会被平台拒绝", h["x-client-version"])
            assertNotNull("必须有 User-Agent", h["User-Agent"])
        }
    }

    @Test
    fun `默认登录方式是手动`() {
        val ctx = ApplicationProvider.getApplicationContext<android.content.Context>()
        assertEquals(DsPrefs.LOGIN_MANUAL, DsPrefs(ctx).loginMethod)
    }

    @Test
    fun `两种鉴权头不会同时出现`() {
        for (method in listOf(DsPrefs.LOGIN_BROWSER, DsPrefs.LOGIN_MANUAL)) {
            val h = headersFor(method)
            assertFalse(
                "同时带 Bearer 与 dsh 头会让平台判定混乱",
                h.containsKey("Authorization") && h.containsKey("x-dsh-auth-token")
            )
        }
    }
}
