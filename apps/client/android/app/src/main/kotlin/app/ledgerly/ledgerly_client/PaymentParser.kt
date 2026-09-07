package app.ledgerly.ledgerly_client

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Best-effort regex parser for WeChat and Alipay notification bodies.
 *
 * The matcher returns null when it cannot confidently identify a payment,
 * so the listener can drop noisy updates instead of polluting the queue.
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

    fun parse(
        packageName: String,
        content: String,
        timestamp: Long,
    ): PaymentEvent? {
        val platform = when (packageName) {
            "com.tencent.mm" -> PLATFORM_WECHAT
            "com.eg.android.AlipayGphone" -> PLATFORM_ALIPAY
            else -> return null
        }

        if (content.isBlank()) return null

        val direction = when {
            INCOME_KEYWORDS.any { content.contains(it) } &&
                EXPENSE_KEYWORDS.none { content.contains(it) } -> DIRECTION_INCOME
            EXPENSE_KEYWORDS.any { content.contains(it) } -> DIRECTION_EXPENSE
            else -> return null
        }

        val amount = findAmount(content) ?: return null
        if (amount <= 0.0) return null

        val amountMinor = BigDecimal.valueOf(amount).multiply(BigDecimal(100))
            .setScale(0, RoundingMode.HALF_UP)
            .toLong()
        if (amountMinor <= 0L) return null

        val merchant = findMerchant(content)

        return PaymentEvent(
            id = "$platform-$timestamp-$amountMinor",
            platform = platform,
            direction = direction,
            amountMinor = amountMinor,
            merchant = merchant,
            rawText = content.take(2000),
            timestamp = timestamp,
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
