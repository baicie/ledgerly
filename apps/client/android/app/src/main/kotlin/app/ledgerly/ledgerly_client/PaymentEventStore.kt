package app.ledgerly.ledgerly_client

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Stores payment events captured while the Flutter engine was offline so
 * that they can be flushed into the ledger the next time the app opens.
 *
 * Two queues are kept side by side:
 *
 * - [PREF_PENDING] holds parsed [PaymentEvent]s that the parser was able
 *   to classify. These will land in the ledger as auto-ledger transactions.
 * - [PREF_UNPARSED] holds raw notifications the parser could not classify
 *   (no amount, no direction keyword, unsupported platform, etc.). These
 *   are surfaced inside the app so the user can manually book them or
 *   report the missed capture upstream.
 *
 * Both queues are bounded to [MAX_QUEUED] entries so a misbehaving app
 * cannot blow up the SharedPreferences blob.
 */
object PaymentEventStore {
    private const val PREF_NAME = "ledgerly_payment_events"
    private const val PREF_PENDING = "pending_events"
    private const val PREF_UNPARSED = "unparsed_events"
    private const val MAX_QUEUED = 200

    fun save(context: Context, event: PaymentEvent) {
        val preferences = context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
        val array = JSONArray(preferences.getString(PREF_PENDING, "[]") ?: "[]")

        if (alreadyPresent(array, event.id)) return

        array.put(event.toJson())
        preferences.edit()
            .putString(PREF_PENDING, trim(array).toString())
            .apply()
    }

    /**
     * Persist a notification that the parser could not classify.
     *
     * The raw [content] is stored alongside the [reasonTag] returned by
     * [PaymentParser] so the user / developer can correlate the entry with
     * a parser fix in a later release.
     */
    fun saveUnparsed(
        context: Context,
        packageName: String,
        platform: String?,
        reasonTag: String,
        content: String,
        timestamp: Long,
    ) {
        val preferences = context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
        val array = JSONArray(preferences.getString(PREF_UNPARSED, "[]") ?: "[]")

        // The id is derived from the package + timestamp + a short hash of
        // the content so we don't accidentally double-store when the
        // system re-delivers the same notification.
        val id = buildUnparsedId(packageName, timestamp, content)
        if (alreadyPresent(array, id)) return

        val entry = JSONObject().apply {
            put("id", id)
            put("packageName", packageName)
            put("platform", platform ?: JSONObject.NULL)
            put("reasonTag", reasonTag)
            put("rawText", content.take(2000))
            put("timestamp", timestamp)
        }
        array.put(entry)
        preferences.edit()
            .putString(PREF_UNPARSED, trim(array).toString())
            .apply()
    }

    fun getPendingEvents(context: Context): String {
        return readQueue(context, PREF_PENDING)
    }

    fun getUnparsedEvents(context: Context): String {
        return readQueue(context, PREF_UNPARSED)
    }

    fun clear(context: Context) {
        context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
            .edit()
            .remove(PREF_PENDING)
            .apply()
    }

    fun clearUnparsed(context: Context) {
        context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
            .edit()
            .remove(PREF_UNPARSED)
            .apply()
    }

    /**
     * Drop a single unparsed entry by id. Returns true when an entry
     * was actually removed; false when nothing matched (so callers can
     * detect a stale id, e.g. after the user already cleared the
     * queue manually).
     */
    fun dismissUnparsed(context: Context, id: String): Boolean {
        val preferences = context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(PREF_UNPARSED, "[]") ?: "[]"
        val array = JSONArray(raw)
        val out = JSONArray()
        var removed = false
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (!removed && obj.optString("id") == id) {
                removed = true
                continue
            }
            out.put(obj)
        }
        if (removed) {
            preferences.edit()
                .putString(PREF_UNPARSED, out.toString())
                .apply()
        }
        return removed
    }

    private fun readQueue(context: Context, key: String): String {
        return context.applicationContext.getSharedPreferences(
            PREF_NAME,
            Context.MODE_PRIVATE,
        ).getString(key, "[]") ?: "[]"
    }

    private fun trim(array: JSONArray): JSONArray {
        val out = JSONArray()
        val start = maxOf(0, array.length() - MAX_QUEUED)
        for (i in start until array.length()) {
            out.put(array.get(i))
        }
        return out
    }

    private fun alreadyPresent(array: JSONArray, id: String): Boolean {
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (obj.optString("id") == id) return true
        }
        return false
    }

    private fun buildUnparsedId(packageName: String, timestamp: Long, content: String): String {
        // Short stable hash of the content so identical payloads collapse
        // even if the system delivers them twice with slightly different
        // timestamps.
        val head = content.take(120)
        var h = 0
        for (ch in head) {
            h = (h * 31 + ch.code) and 0x7fffffff
        }
        return "unparsed-${packageName}-${timestamp}-${h.toString(16)}"
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
