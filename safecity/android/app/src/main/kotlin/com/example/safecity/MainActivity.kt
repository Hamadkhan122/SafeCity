package com.example.safecity

import android.Manifest
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Adds a "safecity/phone" channel for DIRECT calls (ACTION_CALL).
 * A direct call returns to SafeCity when it ends, instead of leaving the
 * user in the dialer app. Returns false if permission is denied so the
 * Dart side can fall back to the normal dialer.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "safecity/phone"
    private var pendingNumber: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSms: Pair<String, String>? = null
    private var pendingSmsResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // App settings stored on the phone (Settings screen).
        val prefs = getSharedPreferences("safecity_settings", Context.MODE_PRIVATE)

        // Incident alerts while the app is closed (IncidentAlertService).
        MethodChannel(messenger, "safecity/alerts").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIF
                        )
                    }
                    IncidentAlertService.start(this)
                    result.success(true)
                }
                "stop" -> {
                    IncidentAlertService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "safecity/prefs").setMethodCallHandler { call, result ->
            val key = call.argument<String>("key")
            when (call.method) {
                "getAll" -> {
                    val m = HashMap<String, Any?>()
                    for ((k, v) in prefs.all) m[k] = v
                    result.success(m)
                }
                "setBool" -> {
                    prefs.edit().putBoolean(key, call.argument<Boolean>("value") ?: false).apply()
                    result.success(true)
                }
                "setInt" -> {
                    prefs.edit().putInt(key, call.argument<Int>("value") ?: 0).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Accident detection: streams strong accelerations (m/s^2, gravity
        // removed). Only values above ~1.4 g are sent to keep traffic low.
        EventChannel(messenger, "safecity/accel").setStreamHandler(
            object : EventChannel.StreamHandler {
                private var listener: SensorEventListener? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                    val linear = sm.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
                    val sensor = linear ?: sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                    if (sensor == null) {
                        events.error("NO_SENSOR", "No accelerometer on this phone", null)
                        return
                    }
                    val removeGravity = linear == null
                    listener = object : SensorEventListener {
                        override fun onSensorChanged(e: SensorEvent) {
                            val x = e.values[0].toDouble()
                            val y = e.values[1].toDouble()
                            val z = e.values[2].toDouble()
                            var mag = Math.sqrt(x * x + y * y + z * z)
                            if (removeGravity) mag = Math.abs(mag - SensorManager.GRAVITY_EARTH)
                            if (mag > 14.0) events.success(mag)
                        }

                        override fun onAccuracyChanged(s: Sensor?, accuracy: Int) {}
                    }
                    sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
                }

                override fun onCancel(arguments: Any?) {
                    val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                    listener?.let { sm.unregisterListener(it) }
                    listener = null
                }
            }
        )

        // System share sheet (WhatsApp, SMS, Gmail, ...) for location links.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safecity/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text") ?: ""
                val title = call.argument<String>("title") ?: "Share via"
                try {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(send, title))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
        // Automatic SOS SMS (no need to press Send in the messaging app).
        // Returns false if permission is denied so Dart can fall back to
        // opening the messaging app.
        MethodChannel(messenger, "safecity/sms").setMethodCallHandler { call, result ->
            if (call.method != "sendSms") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val number = call.argument<String>("number")
            val text = call.argument<String>("text") ?: ""
            if (number.isNullOrBlank() || text.isBlank()) {
                result.success(false)
                return@setMethodCallHandler
            }
            if (hasSmsPermission()) {
                result.success(sendSms(number, text))
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                pendingSmsResult?.success(false)
                pendingSms = Pair(number, text)
                pendingSmsResult = result
                requestPermissions(arrayOf(Manifest.permission.SEND_SMS), REQUEST_SMS)
            } else {
                result.success(false)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "directCall") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val number = call.argument<String>("number")
                if (number.isNullOrBlank()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (hasCallPermission()) {
                    result.success(startCall(number))
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    pendingResult?.success(false)
                    pendingNumber = number
                    pendingResult = result
                    requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), REQUEST_CALL)
                } else {
                    result.success(false)
                }
            }
    }

    private fun hasCallPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasSmsPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun sendSms(number: String, text: String): Boolean = try {
        val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            getSystemService(SmsManager::class.java)
        else SmsManager.getDefault()
        val parts = sms.divideMessage(text)
        if (parts.size > 1) sms.sendMultipartTextMessage(number, null, parts, null, null)
        else sms.sendTextMessage(number, null, text, null, null)
        true
    } catch (e: Exception) {
        false
    }

    private fun startCall(number: String): Boolean = try {
        startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:" + Uri.encode(number))))
        true
    } catch (e: Exception) {
        false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SMS) {
            val ok = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            val sms = pendingSms
            val res = pendingSmsResult
            pendingSms = null
            pendingSmsResult = null
            res?.success(if (ok && sms != null) sendSms(sms.first, sms.second) else false)
            return
        }
        if (requestCode != REQUEST_CALL) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val number = pendingNumber
        val result = pendingResult
        pendingNumber = null
        pendingResult = null
        result?.success(if (granted && number != null) startCall(number) else false)
    }

    override fun onResume() {
        super.onResume()
        isVisible = true
    }

    override fun onPause() {
        isVisible = false
        super.onPause()
    }

    companion object {
        private const val REQUEST_CALL = 4411
        private const val REQUEST_SMS = 4412
        private const val REQUEST_NOTIF = 4413

        /** True while SafeCity is on screen (alerts then use in-app banners). */
        @Volatile
        var isVisible = false
    }
}
