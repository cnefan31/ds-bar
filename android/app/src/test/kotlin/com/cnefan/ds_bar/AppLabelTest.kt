package com.cnefan.ds_bar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 应用名回归测试。
 *
 * 发布名与包名是两件事：包名 `com.cnefan.ds_bar` 一经发布不可改（会变成另一个 App），
 * 桌面与通知栏显示的名字由 manifest 的 application android:label 决定。
 * 这里把两者钉住，避免误把 label 改成包名或占位符。
 */
class AppLabelTest {

    private fun moduleDir(): File {
        var d = File(System.getProperty("user.dir") ?: ".")
        repeat(6) {
            if (File(d, "src/main/AndroidManifest.xml").exists()) return d
            d = d.parentFile ?: return@repeat
        }
        return File(System.getProperty("user.dir") ?: ".")
    }

    private fun manifest(): String =
        File(moduleDir(), "src/main/AndroidManifest.xml").readText()

    @Test
    fun `应用显示名是 ds-bar`() {
        val m = manifest()
        assertTrue(
            "application 标签应声明 android:label=\"ds-bar\"",
            m.contains("android:label=\"ds-bar\"")
        )
        // 磁贴的 label 是模块名，与 App 名不同，不能一起改。
        assertTrue(
            "磁贴 label 应保持「DeepSeek 余额」，它是面板里的模块名",
            m.contains("android:label=\"DeepSeek 余额\"")
        )
    }

    @Test
    fun `包名保持 com_cnefan_ds_bar`() {
        val g = File(moduleDir(), "build.gradle.kts").readText()
        assertTrue(
            "applicationId 一经发布不可更改，改了就是另一个 App",
            g.contains("applicationId = \"com.cnefan.ds_bar\"")
        )
        assertEquals(
            "Flutter 侧 MaterialApp 标题应与 App 名一致",
            true,
            File(moduleDir(), "../../lib/main.dart").readText().contains("title: 'ds-bar'")
        )
    }
}
