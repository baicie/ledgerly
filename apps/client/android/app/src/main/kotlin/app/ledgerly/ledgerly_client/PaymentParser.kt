package app.ledgerly.ledgerly_client

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Best-effort regex parser for WeChat and Alipay notification bodies.
 *
 * The matcher returns a structured [PaymentParseResult] so the listener
 * can either forward the event into the regular pending queue (success)
 * or capture the raw text into the unparsed queue (failure) for later
 * diagnosis from inside the app.
 *
 * We never throw from this code path: a malformed notification should
 * not crash the listener and break capture for future notifications.
 */
object PaymentParser {

    private const val PLATFORM_WECHAT = "wechat"
    private const val PLATFORM_ALIPAY = "alipay"

    private const val DIRECTION_EXPENSE = "expense"
    private const val DIRECTION_INCOME = "income"

    private val AMOUNT_PATTERNS = listOf(
        Regex("""[¥￥]\s*(\d+(?:\.\d{1,2})?)"""),
        Regex("""(\d+(?:\.\d{1,2})?)\s*元"""),
    )

    private val EXPENSE_KEYWORDS = listOf(
        "付款", "支付成功", "支付", "消费", "扣款", "支出", "已支付",
    )
    private val INCOME_KEYWORDS = listOf(
        "收款", "到账", "转入", "入账", "已收款",
    )

    private val MERCHANT_PATTERNS = listOf(
        Regex("""(?:商家|商户|付款方|收款方)[：:]\s*(.+)"""),
        Regex("""(?:向|付款给|收款来自)\s*(.+?)\s*(?:付款|支付|收款|转账)"""),
        Regex("""(.+?)\s*(?:收款|向你付款)"""),
    )

    /**
     * Parse the notification body. Returns a structured result that the
     * caller routes to either the pending queue (success) or the
     * unparsed queue (failure).
     */
    fun parse(
        packageName: String,
        content: String,
        timestamp: Long,
    ): PaymentParseResult {
        val platform = when (packageName) {
            "com.tencent.mm" -> PLATFORM_WECHAT
            "com.eg.android.AlipayGphone" -> PLATFORM_ALIPAY
            else -> return PaymentParseResult.UnsupportedPlatform(
                packageName = packageName,
            )
        }

        if (content.isBlank()) {
            return PaymentParseResult.BlankContent(platform = platform)
        }

        val direction = when {
            INCOME_KEYWORDS.any { content.contains(it) } &&
                EXPENSE_KEYWORDS.none { content.contains(it) } -> DIRECTION_INCOME
            EXPENSE_KEYWORDS.any { content.contains(it) } -> DIRECTION_EXPENSE
            else -> return PaymentParseResult.NoDirectionKeyword(
                platform = platform,
                contentPreview = content.take(120),
            )
        }

        val amount = findAmount(content)
        if (amount == null) {
            return PaymentParseResult.NoAmount(
                platform = platform,
                direction = direction,
                contentPreview = content.take(120),
            )
        }
        if (!amount.isFinite() || amount <= 0.0) {
            return PaymentParseResult.NonPositiveAmount(
                platform = platform,
                direction = direction,
                amount = amount,
            )
        }

        val amountMinor = BigDecimal.valueOf(amount).multiply(BigDecimal(100))
            .setScale(0, RoundingMode.HALF_UP)
            .toLong()
        if (amountMinor <= 0L) {
            return PaymentParseResult.NonPositiveAmount(
                platform = platform,
                direction = direction,
                amount = amount,
            )
        }

        val merchant = findMerchant(content)

        return PaymentParseResult.Parsed(
            PaymentEvent(
                id = "$platform-$timestamp-$amountMinor",
                platform = platform,
                direction = direction,
                amountMinor = amountMinor,
                merchant = merchant,
                rawText = content.take(2000),
                timestamp = timestamp,
            ),
        )
    }

    private fun findAmount(text: String): Double? {
        for (regex in AMOUNT_PATTERNS) {
            val match = regex.find(text) ?: continue
            val value = match.groupValues[1].toDoubleOrNull() ?: continue
            if (value.isFinite() && value > 0.0) return value
        }
        return null
    }

    private fun findMerchant(text: String): String? {
        for (regex in MERCHANT_PATTERNS) {
            val match = regex.find(text) ?: continue
            val raw = match.groupValues[1].trim()
            if (raw.isNotEmpty()) {
                return raw.take(50)
            }
        }
        return null
    }
}

/**
 * Structured outcome of [PaymentParser.parse].
 *
 * The success branch carries a fully-built [PaymentEvent]; every failure
 * branch carries a stable [reason] tag plus whatever diagnostics are
 * useful when triaging the issue inside the Flutter UI.
 *
 * Adding a new failure reason? Update [reasonTag] and bump the case in
 * [PaymentParserTest]'s coverage so the parser and the UI never drift.
 */
sealed class PaymentParseResult {
    abstract val platform: String?
    abstract val reasonTag: String

    data class Parsed(val event: PaymentEvent) : PaymentParseResult() {
        override val platform: String? get() = event.platform
        override val reasonTag: String get() = "parsed"
    }

    /** Notification arrived from an app we do not handle. Dropped. */
    data class UnsupportedPlatform(
        override val platform: String?,
        val packageName: String,
    ) : PaymentParseResult() {
        override val reasonTag: String get() = "unsupported_platform"
    }

    /** Notification body is empty after we joined title/text/bigText. */
    data class BlankContent(
        override val platform: String?,
    ) : PaymentParseResult() {
        override val reasonTag: String get() = "blank_content"
    }

    /** Body had no expense / income keyword we recognise. */
    data class NoDirectionKeyword(
        override val platform: String?,
        val contentPreview: String,
    ) : PaymentParseResult() {
        override val reasonTag: String get() = "no_direction_keyword"
    }

    /** Body looked like a payment but no amount matched. */
    data class NoAmount(
        override val platform: String?,
        val direction: String,
        val contentPreview: String,
    ) : PaymentParseResult() {
        override val reasonTag: String get() = "no_amount"
    }

    /** Amount was zero or negative after parsing. */
    data class NonPositiveAmount(
        override val platform: String?,
        val direction: String,
        val amount: Double,
    ) : PaymentParseResult() {
        override val reasonTag: String get() = "non_positive_amount"
    }
}
