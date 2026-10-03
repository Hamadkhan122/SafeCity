package com.example.safecity

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

/**
 * SafeCity - Incident alerts while the app is closed.
 *
 * A small foreground service keeps a Firestore listener on "notifications"
 * (the same docs the in-app bell uses). When a new incident is reported
 * within [RADIUS_METERS] of the user's last known location, a heads-up
 * notification pops up on the screen (like a WhatsApp message), even if
 * SafeCity is closed or swiped away. Tapping it opens the app.
 *
 * Free: no server / Cloud Functions / FCM needed (Spark plan).
 * Started and stopped from Dart via the "safecity/alerts" channel
 * (Settings -> Incident Alerts) and restarted after the phone reboots.
 */
class IncidentAlertService : Service() {

    private var registration: ListenerRegistration? = null
    private var authListener: FirebaseAuth.AuthStateListener? = null
    private var startedAt: Timestamp = Timestamp.now()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels(this)
        startInForeground()
        startedAt = Timestamp.now()

        // Listen only while a user is signed in (Firestore rules need auth).
        val auth = FirebaseAuth.getInstance()
        authListener = FirebaseAuth.AuthStateListener { a ->
            if (a.currentUser != null) attachListener() else detachListener()
        }
        auth.addAuthStateListener(authListener!!)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY // Android restarts the service if it is killed

    override fun onDestroy() {
        detachListener()
        authListener?.let { FirebaseAuth.getInstance().removeAuthStateListener(it) }
        super.onDestroy()
    }

    private fun startInForeground() {
        val n = NotificationCompat.Builder(this, CHANNEL_SERVICE)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("SafeCity incident alerts are on")
            .setContentText("You will be alerted about incidents near you")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(openAppIntent(this, 0))
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ONGOING_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ONGOING_ID, n)
        }
    }

    private fun attachListener() {
        if (registration != null) return
        registration = FirebaseFirestore.getInstance()
            .collection("notifications")
            .whereGreaterThan("createdAt", startedAt)
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) return@addSnapshotListener
                for (change in snap.documentChanges) {
                    if (change.type != DocumentChange.Type.ADDED) continue
                    val d = change.document
                    if (d.metadata.hasPendingWrites()) continue // written by this phone
                    val reporter = d.getString("userId")
                    if (reporter != null &&
                        reporter == FirebaseAuth.getInstance().currentUser?.uid
                    ) continue // don't alert the reporter
                    if (MainActivity.isVisible) continue // in-app banner handles it

                    val lat = d.getDouble("latitude")
                    val lng = d.getDouble("longitude")
                    val distance = distanceTo(lat, lng)
                    if (distance != null && distance > RADIUS_METERS) continue

                    showIncident(
                        d.id.hashCode(),
                        d.getString("title") ?: "Incident reported",
                        d.getString("message") ?: "",
                        distance
                    )
                }
            }
    }

    private fun detachListener() {
        registration?.remove()
        registration = null
    }

    /** Distance in metres from the last known location, or null if unknown. */
    @SuppressLint("MissingPermission")
    private fun distanceTo(lat: Double?, lng: Double?): Float? {
        if (lat == null || lng == null) return null
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) return null
        return try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            var best: Location? = null
            for (p in lm.getProviders(true)) {
                val l = lm.getLastKnownLocation(p) ?: continue
                if (best == null || l.time > best.time) best = l
            }
            if (best == null) return null
            val out = FloatArray(1)
            Location.distanceBetween(best.latitude, best.longitude, lat, lng, out)
            out[0]
        } catch (e: Exception) {
            null
        }
    }

    private fun showIncident(id: Int, title: String, message: String, distance: Float?) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val away = when {
            distance == null -> ""
            distance < 1000 -> " (${distance.toInt()} m away)"
            else -> " (${"%.1f".format(distance / 1000)} km away)"
        }
        val n = NotificationCompat.Builder(this, CHANNEL_ALERTS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("🚨 $title")
            .setContentText(message + away)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message + away))
            .setPriority(NotificationCompat.PRIORITY_HIGH) // heads-up popup
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(this, id))
            .build()
        try {
            NotificationManagerCompat.from(this).notify(id, n)
        } catch (e: SecurityException) {
            // notification permission revoked
        }
    }

    companion object {
        const val CHANNEL_ALERTS = "incident_alerts"
        const val CHANNEL_SERVICE = "incident_alert_service"
        private const val ONGOING_ID = 7001
        const val RADIUS_METERS = 10_000f

        fun createChannels(ctx: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val nm = ctx.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ALERTS, "Incident alerts",
                    NotificationManager.IMPORTANCE_HIGH // pops up on screen
                ).apply { description = "New incidents reported near you" }
            )
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_SERVICE, "Alert service",
                    NotificationManager.IMPORTANCE_MIN
                ).apply { description = "Keeps incident alerts running" }
            )
        }

        fun openAppIntent(ctx: Context, requestCode: Int): PendingIntent {
            val i = Intent(ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                ctx, requestCode, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        fun start(ctx: Context) {
            val i = Intent(ctx, IncidentAlertService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i)
                else ctx.startService(i)
            } catch (e: Exception) {
                // Android may refuse to start it from the background; it will
                // start next time the app is opened.
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, IncidentAlertService::class.java))
        }

        fun isEnabled(ctx: Context): Boolean =
            ctx.getSharedPreferences("safecity_settings", Context.MODE_PRIVATE)
                .getBoolean("incidentAlerts", true)
    }
}

/** Restarts the alert service after the phone reboots. */
class IncidentAlertBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED &&
            IncidentAlertService.isEnabled(context)
        ) {
            IncidentAlertService.start(context)
        }
    }
}
