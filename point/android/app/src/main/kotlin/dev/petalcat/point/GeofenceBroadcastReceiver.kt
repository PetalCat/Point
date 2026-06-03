package dev.petalcat.point

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import org.json.JSONArray
import org.json.JSONObject

/**
 * Receives OS geofence transitions. Events are persisted to SharedPreferences
 * immediately (P1-11) so they survive process death between the broadcast and
 * the Flutter UI subscribing. The in-memory sink is only a fast path; the
 * durable queue is the source of truth.
 */
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val PREFS = "geofence_events"
        private const val KEY_QUEUE = "pending_exits"

        /** Set by MainActivity when the Flutter EventChannel starts listening. */
        var eventSink: ((Map<String, Any>) -> Unit)? = null
            set(value) {
                field = value
                // When the sink attaches, drain any durably-queued events.
                if (value != null) appContext?.let { drainTo(it, value) }
            }

        /** App context captured so the setter can drain without a live receiver. */
        @Volatile
        var appContext: Context? = null

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Durably append an event, then deliver immediately if a sink is live. */
        fun enqueueOrSend(context: Context, event: Map<String, Any>) {
            appContext = context.applicationContext
            persist(context, event)
            eventSink?.let { drainTo(context, it) }
        }

        private fun persist(context: Context, event: Map<String, Any>) {
            val p = prefs(context)
            val arr = JSONArray(p.getString(KEY_QUEUE, "[]"))
            val obj = JSONObject()
            for ((k, v) in event) obj.put(k, v)
            arr.put(obj)
            p.edit().putString(KEY_QUEUE, arr.toString()).apply()
        }

        /** Send every queued event to the sink, clearing the queue as we go. */
        @Synchronized
        private fun drainTo(context: Context, sink: (Map<String, Any>) -> Unit) {
            val p = prefs(context)
            val arr = JSONArray(p.getString(KEY_QUEUE, "[]"))
            if (arr.length() == 0) return
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val map = HashMap<String, Any>()
                obj.keys().forEach { k -> map[k] = obj.get(k) }
                sink(map)
            }
            // Clear only after all events were handed off.
            p.edit().putString(KEY_QUEUE, "[]").apply()
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        appContext = context.applicationContext
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return
        if (geofencingEvent.hasError()) {
            Log.e("GeofenceReceiver", "Error: ${geofencingEvent.errorCode}")
            return
        }

        if (geofencingEvent.geofenceTransition == Geofence.GEOFENCE_TRANSITION_EXIT) {
            for (geofence in geofencingEvent.triggeringGeofences ?: emptyList()) {
                Log.d("GeofenceReceiver", "EXIT: ${geofence.requestId}")
                enqueueOrSend(context, mapOf(
                    "zoneId" to geofence.requestId,
                    "transition" to "exit"
                ))
            }
        }
    }
}
