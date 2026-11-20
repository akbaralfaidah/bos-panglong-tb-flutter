package com.bospanglong.pos

import android.app.NotificationManager
import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.bospanglong.pos/owner_notifications"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OwnerNotificationHelper.ensureChannels(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "showTransactionNotification" -> {
                    val id = call.argument<Int>("id")
                        ?: ((System.currentTimeMillis() % 100000).toInt())
                    val title = call.argument<String>("title") ?: "Transaksi Baru Kasir"
                    val body = call.argument<String>("body") ?: ""
                    val docId = call.argument<String>("docId")
                    val txIso = call.argument<String>("txIso")
                    val shown = OwnerNotificationHelper.showTransactionNotification(
                        context = this,
                        id = id,
                        title = title,
                        body = body,
                        docId = docId,
                        txIso = txIso
                    )
                    result.success(shown)
                }
                "startBackgroundMonitor" -> {
                    val storeId = call.argument<String>("storeId") ?: ""
                    val ownerName = call.argument<String>("ownerName") ?: ""
                    if (storeId.isEmpty()) {
                        result.success(false)
                    } else {
                        OwnerMonitorPrefs.enable(this, storeId, ownerName)
                        val started = OwnerTxMonitorService.start(this)
                        result.success(started)
                    }
                }
                "stopBackgroundMonitor" -> {
                    OwnerMonitorPrefs.disable(this)
                    OwnerTxMonitorService.stop(this)
                    result.success(true)
                }
                "isBackgroundMonitorRunning" -> {
                    result.success(OwnerTxMonitorService.isRunning)
                }
                "isBatteryOptimizationIgnored" -> {
                    result.success(OwnerNotificationHelper.isBatteryOptimizationIgnored(this))
                }
                "requestIgnoreBatteryOptimization" -> {
                    OwnerNotificationHelper.openBatteryOptimizationPrompt(this)
                    result.success(true)
                }
                "openChannelSettings" -> {
                    OwnerNotificationHelper.openNotificationChannelSettings(this)
                    result.success(true)
                }
                "cancelAll" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancelAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
