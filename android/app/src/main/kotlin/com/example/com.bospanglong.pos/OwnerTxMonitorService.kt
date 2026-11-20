package com.bospanglong.pos

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs

/**
 * Layanan latar belakang native Android khusus **Pemilik Toko** (START_STICKY + ForegroundService).
 * Menjaga koneksi Firestore real-time tetap hidup 24 jam meskipun:
 * - HP sedang terkunci dalam mode Doze / layar mati,
 * - Aplikasi sudah di-swipe tutup atau berhari-hari tidak dibuka,
 * - HP baru dinyalakan ulang (melalui OwnerMonitorBootReceiver),
 * - Hari berganti melewati tengah malam (rollover tanggal otomatis),
 * - Jaringan internet sempat terputus lalu menyambung kembali.
 */
class OwnerTxMonitorService : Service() {

    companion object {
        private const val TAG = "OwnerTxMonitorService"
        const val ACTION_RESTART_MONITOR = "com.bospanglong.pos.RESTART_OWNER_MONITOR"
        private const val RESTART_REQ_CODE = 900202

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context): Boolean {
            if (!OwnerMonitorPrefs.isEnabled(context)) return false
            return try {
                val intent = Intent(context.applicationContext, OwnerTxMonitorService::class.java)
                ContextCompat.startForegroundService(context.applicationContext, intent)
                true
            } catch (e: Throwable) {
                Log.w(TAG, "Gagal startForegroundService: ${e.message}")
                false
            }
        }

        fun stop(context: Context) {
            cancelScheduledRestart(context)
            try {
                val intent = Intent(context.applicationContext, OwnerTxMonitorService::class.java)
                context.applicationContext.stopService(intent)
            } catch (_: Throwable) {
            }
            isRunning = false
        }

        private fun scheduleRestart(context: Context, delayMs: Long = 2500L) {
            if (!OwnerMonitorPrefs.isEnabled(context)) return
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val restartIntent = Intent(context.applicationContext, OwnerMonitorBootReceiver::class.java).apply {
                    action = ACTION_RESTART_MONITOR
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pi = PendingIntent.getBroadcast(
                    context.applicationContext,
                    RESTART_REQ_CODE,
                    restartIntent,
                    flags
                )
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + delayMs,
                    pi
                )
            } catch (e: Throwable) {
                Log.w(TAG, "Gagal menjadwalkan restart monitor: ${e.message}")
            }
        }

        private fun cancelScheduledRestart(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val restartIntent = Intent(context.applicationContext, OwnerMonitorBootReceiver::class.java).apply {
                    action = ACTION_RESTART_MONITOR
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_NO_CREATE
                }
                val pi = PendingIntent.getBroadcast(
                    context.applicationContext,
                    RESTART_REQ_CODE,
                    restartIntent,
                    flags
                )
                if (pi != null) {
                    alarmManager.cancel(pi)
                }
            } catch (_: Throwable) {
            }
        }
    }

    private var txListener: ListenerRegistration? = null
    private var activeStoreId: String = ""
    private var activeDatePrefix: String = ""
    private var initialSnapshotProcessed: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val dateWatchdogRunnable = object : Runnable {
        override fun run() {
            if (OwnerMonitorPrefs.isEnabled(this@OwnerTxMonitorService)) {
                ensureFirestoreListener(forceRebind = false)
                mainHandler.postDelayed(this, 15 * 60 * 1000L) // Cek pergantian hari tiap 15 menit
            }
        }
    }

    private val dateChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            ensureFirestoreListener(forceRebind = true)
        }
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        ContextCompat.registerReceiver(
            this,
            dateChangeReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val cb = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        mainHandler.post {
                            if (OwnerMonitorPrefs.isEnabled(this@OwnerTxMonitorService)) {
                                ensureFirestoreListener(forceRebind = false)
                            }
                        }
                    }
                }
                cm.registerDefaultNetworkCallback(cb)
                networkCallback = cb
            } catch (_: Throwable) {
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Wajib panggil startForeground segera (<5 detik) agar tidak crash di Android 12–16
        try {
            val statusNotif = OwnerNotificationHelper.buildMonitorStatusNotification(this)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    OwnerNotificationHelper.MONITOR_NOTIF_ID,
                    statusNotif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
                )
            } else {
                startForeground(OwnerNotificationHelper.MONITOR_NOTIF_ID, statusNotif)
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Gagal startForeground: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }

        if (!OwnerMonitorPrefs.isEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        val storeId = OwnerMonitorPrefs.getStoreId(this)
        if (storeId.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }

        ensureFirestoreListener(forceRebind = false)
        mainHandler.removeCallbacks(dateWatchdogRunnable)
        mainHandler.postDelayed(dateWatchdogRunnable, 15 * 60 * 1000L)

        return START_STICKY
    }

    private fun ensureFirestoreListener(forceRebind: Boolean) {
        if (!OwnerMonitorPrefs.isEnabled(this)) {
            stopSelf()
            return
        }
        val storeId = OwnerMonitorPrefs.getStoreId(this)
        if (storeId.isEmpty()) return

        val todayPrefix = OwnerMonitorPrefs.todayDatePrefix()
        if (!forceRebind &&
            txListener != null &&
            activeStoreId == storeId &&
            activeDatePrefix == todayPrefix
        ) {
            return
        }

        txListener?.remove()
        txListener = null
        activeStoreId = storeId
        activeDatePrefix = todayPrefix
        initialSnapshotProcessed = false

        try {
            if (FirebaseApp.getApps(applicationContext).isEmpty()) {
                FirebaseApp.initializeApp(applicationContext)
            }
            val db = FirebaseFirestore.getInstance()
            // Pantau mulai dari timestamp terakhir terlihat (atau awal hari ini, mana yang lebih awal)
            // agar transaksi yang masuk saat HP sempat offline/restart tetap tertangkap!
            val startOfToday = "${todayPrefix}T00:00:00.000"
            val savedLastSeen = OwnerMonitorPrefs.getLastSeenIso(this)
            val queryLowerBound = if (savedLastSeen.isNotEmpty() && savedLastSeen < startOfToday) {
                savedLastSeen
            } else {
                startOfToday
            }

            txListener = db.collection("stores")
                .document(storeId)
                .collection("transactions")
                .whereGreaterThanOrEqualTo("transaction_date", queryLowerBound)
                .addSnapshotListener { snapshot, error ->
                    if (error != null) {
                        Log.w(TAG, "Snapshot listener error: ${error.message}")
                        return@addSnapshotListener
                    }
                    if (snapshot == null) return@addSnapshotListener
                    if (!OwnerMonitorPrefs.isEnabled(this)) {
                        stopSelf()
                        return@addSnapshotListener
                    }

                    val ownerName = OwnerMonitorPrefs.getOwnerName(this)
                    val lastSeenAtAttach = OwnerMonitorPrefs.getLastSeenIso(this)

                    if (!initialSnapshotProcessed) {
                        initialSnapshotProcessed = true
                        // Tangkap transaksi baru yang terjadi SETELAH lastSeenAtAttach
                        // (misal saat HP sedang reboot atau jaringan sempat putus)
                        for (doc in snapshot.documents) {
                            val data = doc.data ?: continue
                            val txIso = (data["transaction_date"] ?: "").toString()
                            if (txIso > lastSeenAtAttach) {
                                processTransactionIfEligible(doc.id, data, ownerName)
                            } else {
                                OwnerMonitorPrefs.markNotified(this, doc.id)
                            }
                        }
                        return@addSnapshotListener
                    }

                    for (change in snapshot.documentChanges) {
                        if (change.type != DocumentChange.Type.ADDED) continue
                        val doc = change.document
                        val data = doc.data
                        processTransactionIfEligible(doc.id, data, ownerName)
                    }
                }
        } catch (e: Throwable) {
            Log.e(TAG, "Gagal memasang listener Firestore: ${e.message}")
        }
    }

    private fun processTransactionIfEligible(
        docId: String,
        tx: Map<String, Any>,
        ownerName: String
    ) {
        val txIso = (tx["transaction_date"] ?: "").toString()
        if (OwnerMonitorPrefs.hasNotified(this, docId)) return
        if (tx["is_legacy_titipan"] == true) {
            OwnerMonitorPrefs.markNotified(this, docId, txIso)
            return
        }

        val role = (tx["cashier_role"] ?: "").toString().trim().uppercase(Locale.US)
        if (role == "OWNER") {
            OwnerMonitorPrefs.markNotified(this, docId, txIso)
            return
        }

        val cashierName = (tx["cashier_name"] ?: "").toString().trim()
        if (role != "EMPLOYEE") {
            if (cashierName.isEmpty()) {
                OwnerMonitorPrefs.markNotified(this, docId, txIso)
                return
            }
            val cleanOwner = ownerName.trim()
            if (cleanOwner.isNotEmpty() && cashierName.equals(cleanOwner, ignoreCase = true)) {
                OwnerMonitorPrefs.markNotified(this, docId, txIso)
                return
            }
        }

        val txIdNum = (tx["id"] as? Number)?.toLong() ?: System.currentTimeMillis()
        val notifId = (abs(txIdNum) % 2147483000L).toInt()
        val displayCashier = if (cashierName.isNotEmpty()) cashierName else "Kasir"
        val customer = (tx["customer_name"] ?: "Pelanggan Umum").toString().trim()
            .ifEmpty { "Pelanggan Umum" }
        val total = (tx["total_price"] as? Number)?.toLong() ?: 0L
        val status = (tx["payment_status"] ?: "Lunas").toString().trim().ifEmpty { "Lunas" }
        val method = (tx["payment_method"] ?: "Tunai").toString().trim().ifEmpty { "Tunai" }

        val formattedRp = try {
            "Rp " + NumberFormat.getNumberInstance(Locale("in", "ID")).format(total)
        } catch (_: Throwable) {
            "Rp $total"
        }

        val title = "Transaksi Baru • Kasir $displayCashier"
        val body = "$customer • $formattedRp ($status • $method)"

        OwnerNotificationHelper.showTransactionNotification(
            context = this,
            id = notifId,
            title = title,
            body = body,
            docId = docId,
            txIso = txIso
        )
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Jika pengguna menutup/swipe aplikasi dari Recent Apps, jadwalkan hidupkan ulang monitor
        if (OwnerMonitorPrefs.isEnabled(this)) {
            scheduleRestart(this, delayMs = 2000L)
        }
    }

    override fun onDestroy() {
        isRunning = false
        mainHandler.removeCallbacks(dateWatchdogRunnable)
        txListener?.remove()
        txListener = null
        try {
            unregisterReceiver(dateChangeReceiver)
        } catch (_: Throwable) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            networkCallback?.let { cb ->
                try {
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    cm.unregisterNetworkCallback(cb)
                } catch (_: Throwable) {
                }
            }
        }
        networkCallback = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
