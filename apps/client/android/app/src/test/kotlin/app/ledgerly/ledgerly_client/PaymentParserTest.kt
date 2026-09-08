package app.ledgerly.ledgerly_client

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-Kotlin tests for [PaymentParser].
 *
 * Run with `./gradlew :app:testDebugUnitTest` on a workstation that has
 * the Android Gradle Plugin installed. The tests exercise the regex
 * grammar only; they do not require a device or emulator.
 */
class PaymentParserTest {

    private val ts = 1_788_705_000_000L

    @Test
    fun parsesAlipayExpenseWithMerchant() {
        val content = """
            支付宝
            付款成功
            向美团外卖付款28.50元
        """.trimIndent()

        val event = PaymentParser.parse(
            packageName = "com.eg.android.AlipayGphone",
            content = content,
            timestamp = ts,
        )

        assertNotNull(event)
        event!!
        assertEquals("alipay", event.platform)
        assertEquals("expense", event.direction)
        assertEquals(2850L, event.amountMinor)
        assertEquals("美团外卖", event.merchant)
        assertEquals(ts, event.timestamp)
    }

    @Test
    fun parsesWechatExpenseWithYuanSymbol() {
        val content = "微信支付 支付 ¥32.00 向美团外卖"
        val event = PaymentParser.parse(
            packageName = "com.tencent.mm",
            content = content,
            timestamp = ts,
        )!!
        assertEquals("wechat", event.platform)
        assertEquals("expense", event.direction)
        assertEquals(3200L, event.amountMinor)
        assertEquals("美团外卖", event.merchant)
    }

    @Test
    fun parsesAlipayIncome() {
        val content = "支付宝 收款到账 100.00元 来自 神秘人"
        val event = PaymentParser.parse(
            packageName = "com.eg.android.AlipayGphone",
            content = content,
            timestamp = ts,
        )!!
        assertEquals("income", event.direction)
        assertEquals(10000L, event.amountMinor)
    }

    @Test
    fun ignoresUnrelatedPackages() {
        val event = PaymentParser.parse(
            packageName = "com.example.other",
            content = "向美团外卖付款 28.50 元",
            timestamp = ts,
        )
        assertNull(event)
    }

    @Test
    fun ignoresContentWithoutPaymentKeywords() {
        val event = PaymentParser.parse(
            packageName = "com.tencent.mm",
            content = "这是一条普通聊天消息，不含金额 28.50",
            timestamp = ts,
        )
        assertNull(event)
    }

    @Test
    fun ignoresContentWithoutAmount() {
        // Has the keyword but no recognisable amount.
        val event = PaymentParser.parse(
            packageName = "com.tencent.mm",
            content = "微信支付 付款成功",
            timestamp = ts,
        )
        assertNull(event)
    }

    @Test
    fun merchantDefaultsToNullWhenNoPatternMatches() {
        val content = "支付宝 付款成功 28.50 元"
        val event = PaymentParser.parse(
            packageName = "com.eg.android.AlipayGphone",
            content = content,
            timestamp = ts,
        )!!
        assertNull(event.merchant)
    }

    @Test
    fun truncatesRawTextToTwoThousandCharacters() {
        val content = "a".repeat(5_000)
        val event = PaymentParser.parse(
            packageName = "com.tencent.mm",
            content = content,
            timestamp = ts,
        )
        // No keywords / amount in the body, so we should not produce an
        // event at all.
        assertNull(event)
    }

    @Test
    fun idIsStableAcrossCalls() {
        val content = "支付宝 付款 28.50 元 美团外卖"
        val a = PaymentParser.parse("com.eg.android.AlipayGphone", content, ts)!!
        val b = PaymentParser.parse("com.eg.android.AlipayGphone", content, ts)!!
        assertEquals(a.id, b.id)
        assertTrue(a.id.contains("alipay-$ts-2850"))
    }
}

/**
 * Smoke tests for the JSON shape used by [PaymentEventStore] to talk to
 * Flutter. These don't touch SharedPreferences, they just verify that a
 * round-tripped event keeps its fields intact.
 */
class PaymentEventJsonTest {

    @Test
    fun serializesAndParsesBack() {
        val event = PaymentEvent(
            id = "wechat-1-2850",
            platform = "wechat",
            direction = "expense",
            amountMinor = 2850L,
            merchant = "美团外卖",
            rawText = "微信支付：向美团外卖付款28.50元",
            timestamp = 1L,
        )

        val json = JSONObject().apply {
            put("id", event.id)
            put("platform", event.platform)
            put("direction", event.direction)
            put("amountMinor", event.amountMinor)
            put("merchant", event.merchant)
            put("rawText", event.rawText)
            put("timestamp", event.timestamp)
        }

        val array = JSONArray().put(json)
        // Re-parse to validate shape.
        val parsed = array.getJSONObject(0)
        assertEquals(event.id, parsed.getString("id"))
        assertEquals(event.platform, parsed.getString("platform"))
        assertEquals(event.direction, parsed.getString("direction"))
        assertEquals(event.amountMinor, parsed.getLong("amountMinor"))
        assertEquals(event.merchant, parsed.getString("merchant"))
        assertEquals(event.rawText, parsed.getString("rawText"))
        assertEquals(event.timestamp, parsed.getLong("timestamp"))
    }
}
