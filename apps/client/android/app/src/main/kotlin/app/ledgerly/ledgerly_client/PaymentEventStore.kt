package app.ledgerly.ledgerly_client

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Stores payment events captured while the Flutter engine was offline so
 * that they can be flushed into the ledger the next time the app opens.
 *
 * Backed by SharedPreferences to avoid introducing Room alongside Drift in
 * the first version.
 */
object PaymentEventStore {
    private const val PREF_NAME = "ledgerly_payment_events"
    private const val KEY_EVENTS = "pending_events"
    private const val MAX_QUEUED = 200

    fun save(context: Context, event: PaymentEvent) {
        val preferences = context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
        val array = JSONArray(preferences.getString(KEY_EVENTS, "[]") ?: "[]")

        if (alreadyPresent(array, event.id)) return

        array.put(event.toJson())

        // Bound the queue so it cannot grow forever if the user never opens the app.
        val trimmed = JSONArray()
        val start = maxOf(0, array.length() - MAX_QUEUED)
        for (i in start until array.length()) {
            trimmed.put(array.get(i))
        }

        preferences.edit()
            .putString(KEY_EVENTS, trimmed.toString())
            .apply()
    }

    fun getPendingEvents(context: Context): String {
        val preferences = context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
        return preferences.getString(KEY_EVENTS, "[]") ?: "[]"
    }

    fun clear(context: Context) {
        context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
            .edit()
            .remove(KEY_EVENTS)
            .apply()
    }

    private fun alreadyPresent(array: JSONArray, id: String): Boolean {
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (obj.optString("id") == id) return true
        }
        return false
    }

    private fun PaymentEvent.toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("platform", platform)
        put("direction", direction)
        put("amountMinor", amountMinor)
        put("merchant", merchant ?: JSONObject.NULL)
        put("rawText", rawText)
        put("timestamp", timestamp)
    }
}
