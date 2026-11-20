package com.bospanglong.pos

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Penyimpanan lokal khusus layanan pemantau transaksi Pemilik Toko di Android.
 * Menyimpan storeId, status aktif/nonaktif, timestamp terakhir yang sudah dipantau,
 * serta daftar ID dokumen yang sudah dinotifikasikan agar tidak pernah double-notify
 * walaupun aplikasi ditutup, di-restart, atau menerima push FCM bersamaan.
 */
object OwnerMonitorPrefs {
    private const val PREFS_NAME = "owner_tx_monitor_prefs"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_STORE_ID = "store_id"
    private const val KEY_OWNER_NAME = "owner_name"
    private const val KEY_LAST_SEEN_ISO = "last_seen_iso"
    private const val KEY_NOTIFIED_IDS = "notified_doc_ids"
    private const val MAX_NOTIFIED_CACHE = 250

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun nowIso(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        return sdf.format(Date())
    }

    fun todayDatePrefix(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return sdf.format(Date())
    }

    fun enable(context: Context, storeId: String, ownerName: String) {
        val p = prefs(context)
        val prevStore = p.getString(KEY_STORE_ID, "") ?: ""
        val prevEnabled = p.getBoolean(KEY_ENABLED, false)
        val existingLastSeen = p.getString(KEY_LAST_SEEN_ISO, "") ?: ""

        val editor = p.edit()
            .putBoolean(KEY_ENABLED, true)
            .putString(KEY_STORE_ID, storeId)
            .putString(KEY_OWNER_NAME, ownerName)

        // Jika baru diaktifkan atau ganti toko, mulai pantau dari waktu sekarang (hindari spam data lama)
        if (!prevEnabled || prevStore != storeId || existingLastSeen.isEmpty()) {
            editor.putString(KEY_LAST_SEEN_ISO, nowIso())
            editor.putStringSet(KEY_NOTIFIED_IDS, emptySet())
        }
        editor.apply()
    }

    fun disable(context: Context) {
        prefs(context).edit()
            .putBoolean(KEY_ENABLED, false)
            .remove(KEY_STORE_ID)
            .remove(KEY_OWNER_NAME)
            .remove(KEY_LAST_SEEN_ISO)
            .remove(KEY_NOTIFIED_IDS)
            .apply()
    }

    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, false)

    fun getStoreId(context: Context): String = prefs(context).getString(KEY_STORE_ID, "") ?: ""

    fun getOwnerName(context: Context): String = prefs(context).getString(KEY_OWNER_NAME, "") ?: ""

    fun getLastSeenIso(context: Context): String {
        val saved = prefs(context).getString(KEY_LAST_SEEN_ISO, "") ?: ""
        if (saved.isNotEmpty()) return saved
        val now = nowIso()
        prefs(context).edit().putString(KEY_LAST_SEEN_ISO, now).apply()
        return now
    }

    fun updateLastSeenIsoIfNewer(context: Context, iso: String) {
        if (iso.isEmpty()) return
        val current = getLastSeenIso(context)
        if (iso > current) {
            prefs(context).edit().putString(KEY_LAST_SEEN_ISO, iso).apply()
        }
    }

    @Synchronized
    fun hasNotified(context: Context, docId: String): Boolean {
        if (docId.isEmpty()) return false
        val set = prefs(context).getStringSet(KEY_NOTIFIED_IDS, emptySet()) ?: emptySet()
        return set.contains(docId)
    }

    @Synchronized
    fun markNotified(context: Context, docId: String, txIso: String? = null) {
        val p = prefs(context)
        val existing = (p.getStringSet(KEY_NOTIFIED_IDS, emptySet()) ?: emptySet()).toMutableList()
        if (docId.isNotEmpty() && !existing.contains(docId)) {
            existing.add(docId)
            while (existing.size > MAX_NOTIFIED_CACHE) {
                existing.removeAt(0)
            }
        }
        val editor = p.edit().putStringSet(KEY_NOTIFIED_IDS, existing.toSet())
        if (!txIso.isNullOrEmpty()) {
            val current = p.getString(KEY_LAST_SEEN_ISO, "") ?: ""
            if (txIso > current) {
                editor.putString(KEY_LAST_SEEN_ISO, txIso)
            }
        }
        editor.apply()
    }
}
