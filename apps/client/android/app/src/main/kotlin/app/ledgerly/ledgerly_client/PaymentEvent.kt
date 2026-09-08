package app.ledgerly.ledgerly_client

/**
 * One payment event extracted from a WeChat or Alipay notification.
 *
 * The Kotlin side only persists this struct; the Flutter side decides how
 * to turn it into a ledger transaction (account picking, dedup, classification).
 */
data class PaymentEvent(
    val id: String,
    val platform: String,
    val direction: String,
    val amountMinor: Long,
    val merchant: String?,
    val rawText: String,
    val timestamp: Long,
)
