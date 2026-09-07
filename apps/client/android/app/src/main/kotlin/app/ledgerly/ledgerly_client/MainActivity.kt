package app.ledgerly.ledgerly_client

import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_OPEN_SETTINGS -> {
                    startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
                    )
                    result.success(null)
                }
                METHOD_IS_ENABLED -> {
                    val packages =
                        NotificationManagerCompat.getEnabledListenerPackages(this)
                    result.success(packages.contains(packageName))
                }
                METHOD_GET_PENDING -> {
                    result.success(PaymentEventStore.getPendingEvents(this))
                }
                METHOD_CLEAR_PENDING -> {
                    PaymentEventStore.clear(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL = "app.ledgerly.ledgerly_client/payment"
        private const val METHOD_OPEN_SETTINGS = "openNotificationSettings"
        private const val METHOD_IS_ENABLED = "isNotificationAccessEnabled"
        private const val METHOD_GET_PENDING = "getPendingPaymentEvents"
        private const val METHOD_CLEAR_PENDING = "clearPendingPaymentEvents"
    }
}
