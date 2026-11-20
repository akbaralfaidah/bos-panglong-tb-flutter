package com.bospanglong.pos

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Helper terpusat untuk notifikasi transaksi Pemilik Toko di Android:
 * - Memakai channel versi baru (`owner_employee_tx_channel_v2`) dengan suara default eksplisit,
 *   pola getar tegas, prioritas tinggi (heads-up), dan visibilitas publik di layar terkunci.
 * - Menghapus channel lama yang mungkin sempat ter-cache tanpa suara di OEM tertentu.
 * - Membangunkan layar sebentar (4 detik) saat HP sedang terkunci agar notifikasi langsung
 *   terlihat dan berbunyi jelas.
 */
object OwnerNotificationHelper {
    const val ALERT_CHANNEL_ID = "owner_employee_tx_channel_v2"
    private const val OLD_ALERT_CHANNEL_ID = "owner_employee_tx_channel"
    private const val ALERT_CHANNEL_NAME = "Notifikasi Transaksi Kasir"
    private const val ALERT_CHANNEL_DESC =
        "Notifikasi berbunyi & tampil di layar terkunci saat karyawan menyelesaikan transaksi."

    const val MONITOR_CHANNEL_ID = "owner_monitor_status_channel"
    private const val MONITOR_CHANNEL_NAME = "Status Pemantau Kasir"
    private const val MONITOR_CHANNEL_DESC =
        "Menjaga notifikasi transaksi kasir tetap masuk walau layar terkunci atau aplikasi ditutup."

    const val MONITOR_NOTIF_ID = 900101
    private val VIBRATION_PATTERN = longArrayOf(0L, 300L, 140L, 300L)

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Bersihkan channel v1 lama agar tidak ada channel duplikat/senyap di pengaturan HP
        try {
            nm.deleteNotificationChannel(OLD_ALERT_CHANNEL_ID)
        } catch (_: Throwable) {
        }

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val alertChannel = NotificationChannel(
            ALERT_CHANNEL_ID,
            ALERT_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = ALERT_CHANNEL_DESC
            setSound(soundUri, audioAttrs)
            enableVibration(true)
            vibrationPattern = VIBRATION_PATTERN
            enableLights(true)
            lightColor = Color.rgb(37, 99, 235)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(true)
        }
        nm.createNotificationChannel(alertChannel)

        val monitorChannel = NotificationChannel(
            MONITOR_CHANNEL_ID,
            MONITOR_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_MIN
        ).apply {
            description = MONITOR_CHANNEL_DESC
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        nm.createNotificationChannel(monitorChannel)
    }

    fun buildMonitorStatusNotification(context: Context): Notification {
        ensureChannels(context)
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            MONITOR_NOTIF_ID,
            launchIntent,
            pendingFlags
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, MONITOR_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_MIN)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Pemantau Transaksi Kasir Aktif")
            .setContentText("Notifikasi tetap masuk saat layar terkunci atau aplikasi ditutup")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_DEFERRED)
        }

        return builder.build()
    }

    fun showTransactionNotification(
        context: Context,
        id: Int,
        title: String,
        body: String,
        docId: String? = null,
        txIso: String? = null
    ): Boolean {
        if (!docId.isNullOrEmpty()) {
            if (OwnerMonitorPrefs.hasNotified(context, docId)) {
                return false
            }
            OwnerMonitorPrefs.markNotified(context, docId, txIso)
        }

        ensureChannels(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(context, id, launchIntent, pendingFlags)
        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_HIGH)
                .setSound(soundUri)
                .setVibrate(VIBRATION_PATTERN)
                .setDefaults(Notification.DEFAULT_ALL)
        }

        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(false)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setContentIntent(pendingIntent)
            .build()

        nm.notify(id, notification)
        wakeScreenBriefly(context)
        return true
    }

    private fun wakeScreenBriefly(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) {
                @Suppress("DEPRECATION")
                val wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "bospanglong:owner_tx_alert_wake"
                )
                wakeLock.acquire(4000L)
            }
        } catch (_: Throwable) {
            // Aman jika OEM membatasi wake lock
        }
    }

    fun isBatteryOptimizationIgnored(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } catch (_: Throwable) {
            false
        }
    }

    fun openBatteryOptimizationPrompt(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            activity.startActivity(intent)
        } catch (_: Throwable) {
            try {
                activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Throwable) {
            }
        }
    }

    fun openNotificationChannelSettings(activity: Activity) {
        ensureChannels(activity)
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, ALERT_CHANNEL_ID)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
            }
            activity.startActivity(intent)
        } catch (_: Throwable) {
        }
    }
}
