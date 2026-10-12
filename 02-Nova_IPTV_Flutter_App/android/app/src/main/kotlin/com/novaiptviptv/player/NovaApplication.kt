package com.novaiptviptv.player

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log

/**
 * Applies AdMob App ID from admin-panel cache (SharedPreferences) before the
 * Mobile Ads SDK reads the manifest meta-data. Manifest keeps a Google sample
 * ID as bootstrap so the process never crashes on a fresh install.
 */
class NovaApplication : Application() {
    override fun onCreate() {
        applyCachedAdMobAppId(this)
        super.onCreate()
    }

    companion object {
        private const val TAG = "NovaAds"
        private const val PREFS = "FlutterSharedPreferences"
        private const val KEY = "flutter.admob_app_id_android"
        private const val META = "com.google.android.gms.ads.APPLICATION_ID"

        fun applyCachedAdMobAppId(context: Context) {
            try {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val appId = prefs.getString(KEY, null)?.trim().orEmpty()
                if (appId.isEmpty()) return
                patchApplicationIdMeta(context, appId)
            } catch (e: Exception) {
                Log.w(TAG, "applyCachedAdMobAppId: ${e.message}")
            }
        }

        fun patchApplicationIdMeta(context: Context, appId: String): Boolean {
            val id = appId.trim()
            if (id.isEmpty()) return false
            return try {
                val ai = context.packageManager.getApplicationInfo(
                    context.packageName,
                    PackageManager.GET_META_DATA,
                )
                val meta = ai.metaData ?: return false
                meta.putString(META, id)
                Log.i(TAG, "AdMob APPLICATION_ID prepared from panel")
                true
            } catch (e: Exception) {
                Log.w(TAG, "patchApplicationIdMeta: ${e.message}")
                false
            }
        }
    }
}
