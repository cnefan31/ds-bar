package com.cnefan.ds_bar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.regex.Pattern

/**
 * 通知布局的 RemoteViews 合规性检查。
 *
 * 背景：RemoteViews 只允许有限的控件白名单，用错控件（例如 `<View>`）时，
 * 部分 OEM（实测 EMUI）会**静默丢弃整条通知**，日志里只在系统侧留一行
 * remove，应用侧无任何异常。这种失败极难排查，因此固化成回归测试。
 *
 * 同时校验：两套布局的控件 id 必须一致，否则深浅色切换会绑定失败。
 */
class NotificationLayoutTest {

    /** RemoteViews 官方白名单里我们用到的部分。加控件必须同时更新这里。 */
    private val allowed = setOf(
        "LinearLayout",
        "RelativeLayout",
        "FrameLayout",
        "TextView",
        "ImageView",
        "Button",
        "Chronometer",
        "ProgressBar",
        "ViewFlipper",
        "ListView",
        "GridView",
        "StackView",
        "AdapterViewFlipper",
        "ViewStub"
    )

    private fun layoutFiles(): List<File> {
        // Gradle 单测的 working dir 是模块目录，故从 app 目录向上定位 res/layout
        val candidates = listOf(
            File("src/main/res/layout"),
            File("app/src/main/res/layout"),
            File("../app/src/main/res/layout")
        )
        val dir = candidates.firstOrNull { it.isDirectory }
            ?: error("找不到 res/layout，候选目录均不存在：" + candidates.joinToString())
        return dir.listFiles { f -> f.name.startsWith("notification_") && f.name.endsWith(".xml") }
            ?.sortedBy { it.name }
            .orEmpty()
    }

    /** 去掉 XML 注释，避免把注释里的示例标签误判为控件。 */
    private fun stripComments(xml: String): String =
        xml.replace(Regex("<!--.*?-->", RegexOption.DOT_MATCHES_ALL), "")

    @Test
    fun `通知布局全部存在`() {
        val names = layoutFiles().map { it.name }.toSet()
        assertEquals(
            "四套布局缺一不可：折叠/展开 × 深/浅",
            setOf(
                "notification_collapsed.xml",
                "notification_collapsed_light.xml",
                "notification_expanded.xml",
                "notification_expanded_light.xml"
            ),
            names
        )
    }

    @Test
    fun `布局只使用 RemoteViews 白名单控件`() {
        layoutFiles().forEach { file ->
            val body = stripComments(file.readText())
            val tags = Regex("<([A-Za-z][A-Za-z0-9._]*)")
                .findAll(body)
                .map { it.groupValues[1] }
                .filterNot { it.startsWith("?") }
                .toSet()
            val illegal = tags - allowed
            assertTrue(
                "${file.name} 用了白名单外的控件：$illegal。"
                    + "这类控件会让 OEM 静默丢弃整条通知，请改用 ImageView 等白名单控件。",
                illegal.isEmpty()
            )
        }
    }

    @Test
    fun `布局禁止直接使用 View 标签`() {
        // <View> 是 RemoteViews 里最容易误用的一个：做分隔线时很自然就想写它。
        layoutFiles().forEach { file ->
            val body = stripComments(file.readText())
            assertTrue(
                "${file.name} 使用了 <View> 标签，RemoteViews 不支持，会导致通知被丢弃。",
                !Regex("<View[\\s/>]").containsMatchIn(body)
            )
        }
    }

    @Test
    fun `深浅两套布局的控件 id 完全一致`() {
        val pairs = listOf(
            "notification_collapsed.xml" to "notification_collapsed_light.xml",
            "notification_expanded.xml" to "notification_expanded_light.xml"
        )
        val files = layoutFiles().associateBy { it.name }
        pairs.forEach { (darkName, lightName) ->
            val dark = idsOf(files[darkName]!!)
            val light = idsOf(files[lightName]!!)
            assertEquals(
                "$darkName 与 $lightName 的控件 id 必须一致，否则深浅色切换会绑定失败",
                dark,
                light
            )
        }
    }

    private fun idsOf(file: File): Set<String> =
        Regex("@\\+id/([A-Za-z0-9_]+)")
            .findAll(stripComments(file.readText()))
            .map { it.groupValues[1] }
            .toSet()

    @Test
    fun `绑定代码引用的 id 都存在于布局中`() {
        // 折叠态布局里应含绑定代码会用到的 id。
        val collapsed = idsOf(layoutFiles().first { it.name == "notification_collapsed.xml" })
        listOf("n_balance", "n_today", "n_flag").forEach { id ->
            assertTrue("折叠态布局缺少 $id", collapsed.contains(id))
        }
        val expanded = idsOf(layoutFiles().first { it.name == "notification_expanded.xml" })
        listOf(
            "n_balance", "n_today", "n_month_cost", "n_month_tokens",
            "n_month_requests", "n_cache_rate", "n_updated", "n_chip"
        ).forEach { id ->
            assertTrue("展开态布局缺少 $id", expanded.contains(id))
        }
    }
}
