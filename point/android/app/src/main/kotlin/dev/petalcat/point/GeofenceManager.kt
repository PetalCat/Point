package dev.petalcat.point

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

class GeofenceManager(private val context: Context) {
    private val geofencingClient: GeofencingClient =
        LocationServices.getGeofencingClient(context)

    private val geofencePendingIntent: PendingIntent by lazy {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    fun registerGeofence(id: String, lat: Double, lon: Double, radius: Float) {
        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(lat, lon, radius)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(0) // Don't trigger on initial registration
            .addGeofence(geofence)
            .build()

        try {
            geofencingClient.addGeofences(request, geofencePendingIntent)
                .addOnSuccessListener {
                    Log.d("GeofenceManager", "Registered geofence: $id")
                }
                .addOnFailureListener { e ->
                    Log.e("GeofenceManager", "Failed to register geofence: $id", e)
                }
        } catch (e: SecurityException) {
            Log.e("GeofenceManager", "Missing location permission for geofence: $id", e)
        }
    }

    fun unregisterGeofence(id: String) {
        val ids: MutableList<String> = mutableListOf(id)
        geofencingClient.removeGeofences(ids)
            .addOnSuccessListener {
                Log.d("GeofenceManager", "Unregistered geofence: $id")
            }
            .addOnFailureListener { ex: Exception ->
                Log.e("GeofenceManager", "Failed to unregister geofence: $id", ex)
            }
    }

    fun unregisterAll() {
        geofencingClient.removeGeofences(geofencePendingIntent)
            .addOnSuccessListener {
                Log.d("GeofenceManager", "Unregistered all geofences")
            }
            .addOnFailureListener { ex: Exception ->
                Log.e("GeofenceManager", "Failed to unregister all geofences", ex)
            }
    }
}
