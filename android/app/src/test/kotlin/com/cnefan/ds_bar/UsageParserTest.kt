package com.cnefan.ds_bar

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * UsageParser 纯函数单测：JSON 汇总 / CSV 解析 / 聚合。
 * 依赖 android.jar 里的 org.json，用 Robolectric 之外的方式跑不了，
 * 因此仅在 JVM 侧验证不依赖 Android API 的解析逻辑（splitCsvLine / normalizeDate）。
 */
class UsageParserTest {

    @Test
    fun splitCsvLine_handlesQuotesAndCommas() {
        val line = "2026-10-01,\"my,key\",deepseek-chat,output_tokens,100,0.000002"
        val parts = UsageParser.splitCsvLine(line)
        assertEquals(6, parts.size)
        assertEquals("2026-10-01", parts[0])
        assertEquals("my,key", parts[1])
        assertEquals("deepseek-chat", parts[2])
        assertEquals("output_tokens", parts[3])
        assertEquals("100", parts[4])
    }

    @Test
    fun splitCsvLine_handlesEscapedQuotes() {
        val parts = UsageParser.splitCsvLine("\"a\"\"b\",c")
        assertEquals(2, parts.size)
        assertEquals("a\"b", parts[0])
        assertEquals("c", parts[1])
    }

    @Test
    fun normalizeDate_convertsCompactForm() {
        assertEquals("2026-10-01", UsageParser.normalizeDate("20261001"))
        assertEquals("2026-10-01", UsageParser.normalizeDate("2026-10-01"))
        assertEquals("", UsageParser.normalizeDate(""))
    }

    @Test
    fun parseIntOrZero_handlesDirtyInput() {
        assertEquals(0L, UsageParser.parseIntOrZero(null))
        assertEquals(123L, UsageParser.parseIntOrZero("123"))
        assertEquals(0L, UsageParser.parseIntOrZero("abc"))
        assertEquals(7L, UsageParser.parseIntOrZero(7))
    }

    @Test
    fun parseDoubleOrZero_handlesDirtyInput() {
        assertEquals(0.0, UsageParser.parseDoubleOrZero(null), 1e-9)
        assertEquals(1.5, UsageParser.parseDoubleOrZero("1.5"), 1e-9)
        assertEquals(0.0, UsageParser.parseDoubleOrZero("x"), 1e-9)
    }

    @Test
    fun round6_truncatesToSixDecimals() {
        assertEquals(1.234568, round6(1.23456789), 1e-9)
    }

    @Test
    fun usageBucket_accumulatesTokenTypes() {
        val b = UsageBucket()
        b.addTokens("request_count", 3, 0.0)
        b.addTokens("input_cache_hit_tokens", 100, 0.0000001)
        b.addTokens("input_cache_miss_tokens", 50, 0.000001)
        b.addTokens("output_tokens", 25, 0.000002)
        assertEquals(175L, b.tokens)
        assertEquals(3L, b.requests)
        assertEquals(100L, b.cacheHit)
        assertEquals(50L, b.cacheMiss)
        assertEquals(25L, b.output)
        assertTrue(b.cost > 0)
    }

    @Test
    fun usageBucket_ignoresUnknownType() {
        val b = UsageBucket()
        b.addTokens("something_new", 999, 1.0)
        assertEquals(0L, b.tokens)
        assertEquals(0.0, b.cost, 1e-9)
    }

    @Test
    fun fmt_moneyBranches() {
        assertEquals("0.00", Fmt.money(0.0))
        assertEquals("42.80", Fmt.money(42.8))
        assertEquals("123.4", Fmt.money(123.44))
        assertEquals("1,234.5", Fmt.money(1234.5))
        assertEquals("\u22121,234.5", Fmt.money(-1234.5)) // U+2212 真减号
        assertEquals("12,346", Fmt.money(12345.67))
    }

    @Test
    fun fmt_tokensBranches() {
        assertEquals("999", Fmt.tokens(999))
        assertEquals("1.0K", Fmt.tokens(1000))
        assertEquals("1.23M", Fmt.tokens(1234567))
        assertEquals("1.23B", Fmt.tokens(1234567890))
    }

    @Test
    fun utf8Masking_neverLeaksFullKey() {
        val entry = ApiKeyEntry("id", "prod", "sk-abcdefghijklmnopqrstuvwxyz")
        assertTrue(entry.masked.contains("…"))
        assertTrue(!entry.masked.contains("abcdefghij"))
    }

    @Test
    fun snapshotJson_isParseableAfterRoundTrip() {
        val json = JSONObject().put("version", 1).put("currency", "CNY")
        assertEquals("CNY", JSONObject(json.toString()).getString("currency"))
    }

    @Test
    fun fmt_moneyCompact_keepsOneDecimal() {
        assertEquals("42.8", Fmt.moneyCompact(42.8))
        assertEquals("0.0", Fmt.moneyCompact(0.0))
        assertEquals("1,234.5", Fmt.moneyCompact(1234.5))
        assertEquals("12,346", Fmt.moneyCompact(12345.6))
    }

    @Test
    fun fmt_spent_usesRealMinusAndNeverNegative() {
        // U+2212 真减号，不是 ASCII '-'
        assertEquals("\u22120.71", Fmt.spent(0.71))
        assertEquals("0.00", Fmt.spent(0.0))
        assertEquals("0.00", Fmt.spent(-5.0))
        assertEquals("0.00", Fmt.spent(Double.NaN))
    }

    @Test
    fun fmt_spentBare_omitsCurrencySymbol() {
        assertEquals("\u22120.71", Fmt.spentBare(0.71))
        assertEquals("0.00", Fmt.spentBare(0.0))
        assertTrue(!Fmt.spentBare(1.5).contains("¥"))
    }

    @Test
    fun fmt_percent_handlesMissingRatio() {
        assertEquals("76.4%", Fmt.percent(0.764))
        assertEquals("\u2014", Fmt.percent(null))
        assertEquals("0.0%", Fmt.percent(0.0))
    }

    @Test
    fun fmt_cacheHitRate_returnsNullWithoutInput() {
        assertEquals(0.8, Fmt.cacheHitRate(80, 20)!!, 1e-9)
        assertEquals(null, Fmt.cacheHitRate(0, 0))
        assertEquals(1.0, Fmt.cacheHitRate(5, 0)!!, 1e-9)
    }

    @Test
    fun fmt_count_usesGrouping() {
        assertEquals("3,640", Fmt.count(3640))
        assertEquals("0", Fmt.count(0))
        assertEquals("1,234,567", Fmt.count(1234567))
    }

    @Test
    fun fmt_currencySymbol_defaultsToCny() {
        assertEquals("¥", Fmt.currencySymbol(null))
        assertEquals("¥", Fmt.currencySymbol("CNY"))
        assertEquals("$", Fmt.currencySymbol("USD"))
    }
}
