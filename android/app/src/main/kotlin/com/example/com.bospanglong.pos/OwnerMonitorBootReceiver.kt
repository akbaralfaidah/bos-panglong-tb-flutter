package com.bospanglong.pos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Menghidupkan kembali OwnerTxMonitorService secara otomatis setelah:
 * - HP selesai dinyalakan ulang (BOOT_COMPLETED),
 * - Aplikasi selesai diperbarui (MY_PACKAGE_REPLACED),
 * - Aplikasi di-swipe dari Recent Apps (RESTART_OWNER_MONITOR).
 *
 * Tetap aman: hanya berjalan jika perangkat terakhir dipakai Pemilik dengan sakelar notifikasi ON.
 */
class OwnerMonitorBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!OwnerMonitorPrefs.isEnabled(context)) return
        OwnerTxMonitorService.start(context)
    }
}
