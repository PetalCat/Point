package dev.petalcat.point

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    companion object {
        /** Set by MainActivity when the Flutter EventChannel is listening. */
        var eventSink: ((Map<String, Any>) -> Unit)? = null
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
                val event = mapOf<String, Any>(
                    "zoneId" to geofence.requestId,
                    "transition" to "exit"
                )
                eventSink?.invoke(event)
            }
        }
    }
}
