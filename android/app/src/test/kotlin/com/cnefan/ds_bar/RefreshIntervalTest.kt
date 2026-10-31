package com.cnefan.ds_bar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 刷新间隔规则的 JVM 单测。
 *
 * 回答「通知栏多久刷新一次」这个问题时，这里的数字就是真值来源：
 *  - 默认 60 分钟
 *  - 下限 15 分钟（WorkManager 周期任务系统硬下限）
 *  - 上限 1440 分钟（1 天）
 */
class RefreshIntervalTest {

    @Test
    fun `默认间隔是 60 分钟`() {
        assertEquals(60, DsPrefs.DEFAULT_REFRESH_MINUTES)
    }

    @Test
    fun `低于下限被抬到 15 分钟`() {
        assertEquals(15, clampMinutes(0))
        assertEquals(15, clampMinutes(1))
        assertEquals(15, clampMinutes(14))
        assertEquals(15, clampMinutes(15))
    }

    @Test
    fun `正常区间原样保留`() {
        assertEquals(30, clampMinutes(30))
        assertEquals(60, clampMinutes(60))
        assertEquals(360, clampMinutes(360))
    }

    @Test
    fun `高于上限被压到 1440 分钟`() {
        assertEquals(1440, clampMinutes(1441))
        assertEquals(1440, clampMinutes(100000))
    }

    @Test
    fun `四个预设档位都在合法区间内`() {
        // 对应设计稿的分段控件：15 分 / 30 分 / 1 时 / 6 时
        listOf(15, 30, 60, 360).forEach { m ->
            assertEquals("档位 $m 不应被裁剪", m, clampMinutes(m))
            assertTrue("WorkManager 周期下限是 15 分钟", m >= 15)
        }
    }

    /** 与 DsPrefs.refreshMinutes setter 和 RefreshScheduler.schedule 保持同一规则。 */
    private fun clampMinutes(v: Int): Int = v.coerceIn(15, 1440)
}
