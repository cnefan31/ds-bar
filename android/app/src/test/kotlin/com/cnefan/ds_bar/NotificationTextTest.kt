package com.cnefan.ds_bar

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 通知文案的 JVM 单测。纯函数，不经真机即可验证。
 *
 * 这些断言直接对应设计稿批准的语义：
 *  - 标题只放余额，不出现「余额」二字
 *  - 拿不到余额时用占位符，绝不写「余额不足」
 *  - 今日支出用真减号，不用红色语义
 *  - 演示数据、错误状态都以胶囊式短语出现在展开文本
 */
class NotificationTextTest {

    private fun snapshot(
        balance: Double? = 42.8,
        available: Boolean = true,
        todayCost: Double = 0.71,
        todayTokens: Long = 486_000,
        todayReq: Long = 128,
        monthCost: Double = 18.43,
        monthTokens: Long = 12_480_000,
        monthReq: Long = 3_640,
        hit: Long = 8_900_000,
        miss: Long = 2_180_000,
        demo: Boolean = false,
        balanceErrorCode: String? = null,
        usageErrorCode: String? = null,
        fetchedAt: Long = 1_793_470_000_000
    ): JSONObject {
        val root = JSONObject()
            .put("version", 1)
            .put("fetchedAt", fetchedAt)
            .put("currency", "CNY")
            .put("demo", demo)

        if (balance != null) {
            root.put(
                "balance", JSONObject()
                    .put("isAvailable", available)
                    .put("infos", org.json.JSONArray().put(
                        JSONObject()
                            .put("currency", "CNY")
                            .put("totalBalance", balance)
                            .put("grantedBalance", 2.8)
                            .put("toppedUpBalance", 40.0)
                    ))
            )
        }
        if (balanceErrorCode != null) {
            root.put("balanceError", JSONObject().put("code", balanceErrorCode).put("message", "x"))
        }
        if (usageErrorCode != null) {
            root.put("usageError", JSONObject().put("code", usageErrorCode).put("message", "x"))
        } else {
            root.put(
                "usage", JSONObject()
                    .put("year", 2026).put("month", 10).put("currency", "CNY")
                    .put("today", JSONObject()
                        .put("cost", todayCost).put("tokens", todayTokens).put("requests", todayReq))
                    .put("monthTotal", JSONObject()
                        .put("cost", monthCost).put("tokens", monthTokens)
                        .put("requests", monthReq).put("cacheHit", hit).put("cacheMiss", miss)
                        .put("output", 1_400_000))
            )
        }
        return root
    }

    @Test
    fun `标题只放余额符号与数字，不含余额二字`() {
        val c = NotificationText.build(snapshot())
        assertEquals("¥42.80", c.title)
        assertFalse("标题不应出现「余额」二字", c.title.contains("余额"))
        assertFalse(c.title.contains("DeepSeek"))
    }

    @Test
    fun `正文放今日支出与 token，用真减号`() {
        val c = NotificationText.build(snapshot())
        assertTrue(c.text.startsWith("今日 "))
        assertTrue("应用 U+2212 真减号", c.text.contains("\u2212"))
        assertFalse("不应用 ASCII 连字符", c.text.contains("-¥"))
        assertTrue(c.text.contains("486.0K"))
    }

    @Test
    fun `展开文本含四项指标与更新时间`() {
        val c = NotificationText.build(snapshot())
        assertTrue(c.big.contains("本月 ¥18.43"))
        assertTrue(c.big.contains("12.48M tokens"))
        assertTrue(c.big.contains("3,640 次"))
        assertTrue(c.big.contains("命中 80.3%"))
        assertTrue(c.big.contains("更新"))
    }

    @Test
    fun `拿不到余额时用占位符，绝不写余额不足`() {
        val c = NotificationText.build(
            snapshot(balance = null, balanceErrorCode = "missing_credential", usageErrorCode = null)
        )
        assertEquals(Fmt.DASH, c.title)
        assertFalse("未配置不等于余额不足", c.big.contains("余额不足"))
        assertEquals("未配置 API Key", c.statusHint)
    }

    @Test
    fun `有余额但接口标记不可用时才写余额不足`() {
        val c = NotificationText.build(snapshot(available = false))
        assertTrue(c.big.contains("余额不足"))
    }

    @Test
    fun `userToken 过期时正文改述原因，不显示 0 元`() {
        val c = NotificationText.build(snapshot(usageErrorCode = "platform_auth"))
        assertEquals("userToken 已过期", c.text)
        assertFalse("不应把缺失显示成 0", c.text.contains("0.00"))
        assertEquals("userToken 已过期", c.statusHint)
    }

    @Test
    fun `演示数据在展开文本中标注`() {
        val c = NotificationText.build(snapshot(demo = true))
        assertTrue(c.big.contains("演示数据"))
    }

    @Test
    fun `未同步时给出可操作提示`() {
        val c = NotificationText.build(null)
        assertEquals("未同步", c.title)
        assertTrue(c.big.contains("点按打开"))
        assertEquals("尚未同步", c.statusHint)
    }

    @Test
    fun `充值赠送出现在展开文本`() {
        val c = NotificationText.build(snapshot())
        assertTrue("实际: " + c.big, c.big.contains("充 ¥40.00"))
        assertTrue("实际: " + c.big, c.big.contains("赠 ¥2.80"))
    }

    @Test
    fun `USD 账户用美元符号`() {
        val s = snapshot()
        s.put("currency", "USD")
        val c = NotificationText.build(s)
        assertTrue(c.title.startsWith("$"))
    }

    @Test
    fun `传入时间优先于快照时间`() {
        val c = NotificationText.build(snapshot(fetchedAt = 0L), nowMillis = 1_793_470_000_000)
        assertTrue(c.big.contains("更新"))
    }

    @Test
    fun `无缓存命中数据时不显示命中率`() {
        val c = NotificationText.build(snapshot(hit = 0, miss = 0))
        assertFalse(c.big.contains("命中 "))
    }

    @Test
    fun `演示数据完整渲染成可读的展开文本`() {
        val c = NotificationText.build(snapshot(demo = true))
        // 标题只有金额
        assertEquals("¥42.80", c.title)
        // 正文是今日支出
        assertTrue(c.text.startsWith("今日 "))
        // 展开四段齐全
        assertTrue(c.big.contains("本月 ¥18.43"))
        assertTrue(c.big.contains("12.48M tokens"))
        assertTrue(c.big.contains("3,640 次"))
        assertTrue(c.big.contains("命中"))
        assertTrue(c.big.contains("演示数据"))
        assertTrue(c.big.contains("更新"))
        // 打印实际输出，便于人工核对排版
        println("=== 演示数据通知 ===")
        println("title: " + c.title)
        println("text : " + c.text)
        println("big  :")
        println(c.big)
    }
}
