package com.cnefan.ds_bar

import android.content.Context
import android.widget.RemoteViews
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 用 Robolectric 真实 inflate 通知布局。
 *
 * 这条测试的价值：RemoteViews 的布局错误（非白名单控件、API 不支持的属性、
 * 资源 id 失效）在真机上表现为「通知被系统静默丢弃」，应用侧看不到任何异常，
 * 极难定位。这里在 JVM 里直接 inflate，能在提交前就把这类问题拦住。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
class NotificationLayoutInflateTest {

    private fun ctx(): Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `折叠态布局可以真实 inflate`() {
        val rv = RemoteViews(ctx().packageName, R.layout.notification_collapsed)
        val view = rv.apply(ctx(), null)
        assertNotNull("折叠态布局 inflate 结果不应为 null", view)
    }

    @Test
    fun `展开态布局可以真实 inflate`() {
        val rv = RemoteViews(ctx().packageName, R.layout.notification_expanded)
        val view = rv.apply(ctx(), null)
        assertNotNull("展开态布局 inflate 结果不应为 null", view)
    }

    @Test
    fun `浅色两套布局可以真实 inflate`() {
        listOf(
            R.layout.notification_collapsed_light,
            R.layout.notification_expanded_light
        ).forEach { layout ->
            val rv = RemoteViews(ctx().packageName, layout)
            assertNotNull("布局 $layout inflate 失败", rv.apply(ctx(), null))
        }
    }

    @Test
    fun `绑定文本后 inflate 正常`() {
        val c = NotificationText.build(null)
        val rv = RemoteViews(ctx().packageName, R.layout.notification_collapsed).apply {
            setTextViewText(R.id.n_balance, c.title)
            setTextViewText(R.id.n_today, c.text)
        }
        assertNotNull(rv.apply(ctx(), null))
    }

    @Test
    fun `展开态全部字段绑定后 inflate 正常`() {
        val c = NotificationText.build(null)
        val rv = RemoteViews(ctx().packageName, R.layout.notification_expanded).apply {
            setTextViewText(R.id.n_balance, c.title)
            setTextViewText(R.id.n_today, c.text)
            setTextViewText(R.id.n_month_cost, c.monthCost)
            setTextViewText(R.id.n_month_tokens, c.monthTokens)
            setTextViewText(R.id.n_month_requests, c.monthRequests)
            setTextViewText(R.id.n_cache_rate, c.cacheRate)
            setTextViewText(R.id.n_updated, c.updated)
            setViewVisibility(R.id.n_chip, android.view.View.GONE)
        }
        assertNotNull(rv.apply(ctx(), null))
    }

    @Test
    fun `资源 id 必须是有效值而不是 0`() {
        // const val 缓存 R.layout.* 曾导致 id 变成 0，StatusBar 报
        // Resources$NotFoundException: Resource ID #0x0 后丢弃整条通知。
        listOf(
            R.layout.notification_collapsed,
            R.layout.notification_collapsed_light,
            R.layout.notification_expanded,
            R.layout.notification_expanded_light
        ).forEach { id ->
            assert(id != 0) { "布局资源 id 为 0，说明引用方式有问题（不要用 const 缓存 R.*）" }
        }
    }

    @Test
    fun `通知构建后携带两个自定义视图`() {
        val n = BalanceNotification.build(ctx(), null)
        assertNotNull("折叠态自定义视图缺失", n.contentView)
        assertNotNull("展开态自定义视图缺失", n.bigContentView)
        // setStyle(DecoratedCustomViewStyle) 会把模板名写进 extras，用反射读取，
        // 避免依赖 @hide 的 getTemplate()。
        val template = n.extras.getString("android.template")
        assertEquals(
            "必须是 DecoratedCustomViewStyle，否则系统会忽略自定义布局",
            "android.app.Notification\$DecoratedCustomViewStyle",
            template
        )
    }

    @Test
    fun `演示数据快照能构建出带内容的通知`() {
        val demo = DemoData.snapshot()
        val n = BalanceNotification.build(ctx(), demo)
        assertNotNull(n.contentView)
        assertNotNull(n.bigContentView)
        assertEquals("¥42.80", n.extras.getString("android.title"))
    }

    @Test
    fun `空快照也能构建通知不抛异常`() {
        val n = BalanceNotification.build(ctx(), null)
        assertNotNull(n.contentView)
        assertEquals("未同步", n.extras.getString("android.title"))
    }

    @Test
    fun `通知是常驻且不重复提示`() {
        val n = BalanceNotification.build(ctx(), DemoData.snapshot())
        val flags = n.flags
        assert((flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0) {
            "缺少 FLAG_ONGOING_EVENT，通知不会常驻"
        }
        assert((flags and android.app.Notification.FLAG_ONLY_ALERT_ONCE) != 0) {
            "缺少 FLAG_ONLY_ALERT_ONCE，刷新时会反复打扰"
        }
    }

    @Test
    fun `折叠态与展开态挂的是不同布局`() {
        val n = BalanceNotification.build(ctx(), DemoData.snapshot())
        val collapsedId = n.contentView.layoutId
        val expandedId = n.bigContentView.layoutId
        assert(collapsedId != 0 && expandedId != 0) { "布局 id 不能为 0" }
        assert(collapsedId != expandedId) { "折叠与展开应是两套布局" }
    }
}
