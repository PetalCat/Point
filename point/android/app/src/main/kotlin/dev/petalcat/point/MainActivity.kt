package dev.petalcat.point

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var geofenceManager: GeofenceManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        geofenceManager = GeofenceManager(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.petalcat.point/geofence"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "registerGeofence" -> {
                    val id = call.argument<String>("id")!!
                    val lat = call.argument<Double>("lat")!!
                    val lon = call.argument<Double>("lon")!!
                    val radius = call.argument<Double>("radius")!!
                    geofenceManager.registerGeofence(id, lat, lon, radius.toFloat())
                    result.success(null)
                }
                "unregisterGeofence" -> {
                    val id = call.argument<String>("id")!!
                    geofenceManager.unregisterGeofence(id)
                    result.success(null)
                }
                "unregisterAll" -> {
                    geofenceManager.unregisterAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.petalcat.point/geofence_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                GeofenceBroadcastReceiver.eventSink = { event ->
                    runOnUiThread { events.success(event) }
                }
            }
            override fun onCancel(arguments: Any?) {
                GeofenceBroadcastReceiver.eventSink = null
            }
        })
    }
}
