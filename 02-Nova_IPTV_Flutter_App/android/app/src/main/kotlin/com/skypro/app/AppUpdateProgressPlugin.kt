package com.skypro.app

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.InstallStateUpdatedListener
import io.flutter.plugin.common.EventChannel

/**
 * يبث تقدّم تنزيل/تثبيت Google Play (بايتات + حالة) إلى Flutter.
 * يبث فقط أحداث التغيّر الحقيقية — بدون لقطة أولية قد تسبب حالة خاطئة.
 */
class AppUpdateProgressPlugin(private val activity: Activity) : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var listener: InstallStateUpdatedListener? = null
    private val manager by lazy { AppUpdateManagerFactory.create(activity) }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        val installListener = InstallStateUpdatedListener { state ->
            val payload = mapOf(
                "status" to state.installStatus(),
                "bytesDownloaded" to state.bytesDownloaded(),
                "totalBytesToDownload" to state.totalBytesToDownload(),
            )
            activity.runOnUiThread {
                sink?.success(payload)
            }
        }
        listener = installListener
        manager.registerListener(installListener)
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { manager.unregisterListener(it) }
        listener = null
        sink = null
    }
}
