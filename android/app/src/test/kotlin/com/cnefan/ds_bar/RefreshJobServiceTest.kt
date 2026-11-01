package com.cnefan.ds_bar

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 定时刷新的实现约束。
 *
 * 背景：这一层最初用 WorkManager，它会连带引入 Room、SQLite 与
 * kotlinx-coroutines，dex 多出约 450KB，而项目只用得上「定期、有网、重启后有效」。
 * 换成平台 JobScheduler 后依赖归零。这些约束靠人工记不住，固化成回归测试：
 * 一旦有人把 WorkManager 加回来，或把 JobService 从 manifest 摘掉，这里会先红。
 */
class RefreshJobServiceTest {

    private fun moduleDir(): File {
        var d = File(System.getProperty("user.dir") ?: ".")
        repeat(6) {
            if (File(d, "src/main/AndroidManifest.xml").exists()) return d
            d = d.parentFile ?: return@repeat
        }
        return File(System.getProperty("user.dir") ?: ".")
    }

    private fun manifestText(): String =
        File(moduleDir(), "src/main/AndroidManifest.xml").readText()

    private fun gradleText(): String =
        File(moduleDir(), "build.gradle.kts").readText()

    @Test
    fun `manifest 里注册了 JobService 且声明 BIND_JOB_SERVICE 权限`() {
        val m = manifestText()
        assertTrue(
            "缺 RefreshJobService 注册，JobScheduler 将无法拉起刷新",
            m.contains("com.cnefan.ds_bar.RefreshJobService") || m.contains(".RefreshJobService")
        )
        assertTrue(
            "JobService 必须声明 BIND_JOB_SERVICE 权限",
            m.contains("android.permission.BIND_JOB_SERVICE")
        )
    }

    @Test
    fun `不再依赖 WorkManager 与 Room`() {
        val g = gradleText()
        assertFalse(
            "work-runtime 会带入 Room/SQLite/coroutines，约 450KB dex",
            g.contains("androidx.work:work-runtime")
        )
        assertFalse(
            "core-ktx 已被平台 API 取代，不应再引入",
            g.contains("androidx.core:core-ktx")
        )
        val proguard = File(moduleDir(), "proguard-rules.pro").readText()
        assertFalse(
            "proguard 里不应再有 WorkManager 相关规则",
            proguard.contains("androidx.work")
        )
    }

    @Test
    fun `JobService 的类名与 manifest 声明一致`() {
        val src = File(moduleDir(), "src/main/kotlin/com/cnefan/ds_bar/RefreshJobService.kt")
        assertTrue("RefreshJobService.kt 应存在", src.exists())
        val t = src.readText()
        assertTrue("类名必须是 RefreshJobService", t.contains("class RefreshJobService"))
        assertTrue("必须继承平台 JobService", t.contains(": JobService()"))
        assertTrue(
            "onStartJob 返回 true 后必须显式 jobFinished，否则系统会一直认为任务在跑",
            t.contains("jobFinished(")
        )
        assertTrue("周期任务需要 setPersisted 才能在重启后存活", t.contains("setPersisted(true)"))
        assertTrue("应限制为有网时才跑", t.contains("setRequiredNetworkType"))
    }

    @Test
    fun `周期下限仍为 15 分钟`() {
        val t = File(moduleDir(), "src/main/kotlin/com/cnefan/ds_bar/RefreshJobService.kt").readText()
        assertTrue(
            "JobScheduler 周期下限是 15 分钟（setPeriodic 对更短间隔会抛异常）",
            t.contains("coerceIn(15, 1440)")
        )
    }

    @Test
    fun `proguard 不对 io_flutter 用宽泛 keep`() {
        val pg = File(moduleDir(), "proguard-rules.pro").readText()
        val ruleLines = pg.lines().filterNot { it.trim().startsWith("#") }
        assertFalse(
            "宽泛 -keep class io.flutter.** { *; } 会让 485 个类全部免裁剪，dex 多出约 452KB；" +
                "官方 flutter_proguard_rules.pro 已覆盖真正的反射需求",
            ruleLines.any { it.contains("-keep class io.flutter.**") }
        )
        assertTrue(
            "嵌入层按类名反射，必须保留类名（可裁剪成员）",
            pg.contains("-keepnames class io.flutter.**")
        )
        assertTrue("仍需压制 io.flutter 的 dontwarn", pg.contains("-dontwarn io.flutter.**"))
    }
}
