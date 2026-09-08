package app.ledgerly.ledgerly_client

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Captures WeChat and Alipay payment notifications.
 *
 * The system only delivers notifications while this service is bound, which
 * requires the user to enable notification-listener access in Settings.
 * We persist immediately so that payments received while Flutter is offline
 * still end up in the ledger on next open.
 */
class PayNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName
        if (!isPaymentPackage(packageName)) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getString(Notification.EXTRA_TITLE).orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()

        val content = listOf(title, text, bigText)
            .filter { it.isNotBlank() }
            .distinct()
            .joinToString("\n")
        if (content.isBlank()) return

        Log.d(
            TAG,
            """
            package=$packageName
            title=$title
            text=$text
            bigText=$bigText
            """.trimIndent(),
        )

        val event = PaymentParser.parse(
            packageName = packageName,
            content = content,
            timestamp = sbn.postTime,
        ) ?: return

        PaymentEventStore.save(this, event)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Notifications may be auto-cancelled by WeChat / Alipay shortly after
        // arrival. We do not act on removals here.
    }

    private fun isPaymentPackage(packageName: String): Boolean {
        return packageName == WECHAT_PACKAGE || packageName == ALIPAY_PACKAGE
    }

    companion object {
        private const val TAG = "LedgerlyPay"
        const val WECHAT_PACKAGE = "com.tencent.mm"
        const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
    }
}
