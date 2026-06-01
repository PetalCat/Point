package dev.petalcat.point

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    companion object {
        // Events queued when the Flutter EventChannel isn't listening yet (cold start).
        private val pendingEvents = mutableListOf<Map<String, Any>>()

        /** Set by MainActivity when the Flutter EventChannel starts listening. */
        var eventSink: ((Map<String, Any>) -> Unit)? = null
            set(value) {
                field = value
                if (value != null) {
                    // Drain any events that arrived before the channel was ready.
                    pendingEvents.forEach { value(it) }
                    pendingEvents.clear()
                }
            }

        fun enqueueOrSend(event: Map<String, Any>) {
            val sink = eventSink
            if (sink != null) sink(event) else pendingEvents.add(event)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return
        if (geofencingEvent.hasError()) {
            Log.e("GeofenceReceiver", "Error: ${geofencingEvent.errorCode}")
            return
        }

        if (geofencingEvent.geofenceTransition == Geofence.GEOFENCE_TRANSITION_EXIT) {
            for (geofence in geofencingEvent.triggeringGeofences ?: emptyList()) {
                Log.d("GeofenceReceiver", "EXIT: ${geofence.requestId}")
                enqueueOrSend(mapOf(
                    "zoneId" to geofence.requestId,
                    "transition" to "exit"
                ))
            }
        }
    }
}
