package com.skypro.app

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaDrm
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.NetworkInterface
import java.util.UUID
import kotlin.system.exitProcess

class MainActivity : FlutterActivity() {
    private val channelName = "main_activity_channel"
    private var mainMethodChannel: MethodChannel? = null

    private val widevineUuid = UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)

    /// آخر طلب اتجاه من Flutter: true=أفقي، false=عمودي، null=لم يُطلب بعد.
    private var flutterWantsLandscape: Boolean? = null

    /// منع لقطات الشاشة — الافتراضي مفعّل (نفس السلوك السابق) حتى تصل إعدادات اللوحة.
    private var blockScreenshots: Boolean = true

    private fun isTelevision(): Boolean {
        return try {
            val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
            if (uiMode == Configuration.UI_MODE_TYPE_TELEVISION) return true
            val pm = packageManager
            if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)) {
                return true
            }
            // TV boxes and media sticks lack touchscreen hardware
            if (!pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)) {
                return true
            }
            // Amazon Fire TV sticks & devices
            val model = Build.MODEL.lowercase()
            val mfr = Build.MANUFACTURER.lowercase()
            mfr.contains("amazon") || model.startsWith("aft")
        } catch (_: Exception) {
            false
        }
    }

    private fun getDeviceMemoryInfo(): Map<String, Any> {
        val out = mutableMapOf<String, Any>()
        try {
            val actManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            if (actManager != null) {
                val memInfo = ActivityManager.MemoryInfo()
                actManager.getMemoryInfo(memInfo)
                out["totalMem"] = memInfo.totalMem
                out["availMem"] = memInfo.availMem
                out["lowMemory"] = memInfo.lowMemory
                out["threshold"] = memInfo.threshold
                out["isLowRamDevice"] = actManager.isLowRamDevice
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun applyNativeOrientationLock() {
        flutterWantsLandscape = true
        // Android TV displays are permanently landscape hardware. Calling requestedOrientation on TV
        // triggers IllegalStateException on translucent activities or missing sensor crashes.
        if (isTelevision()) return

        try {
            // Only set if not already landscape to prevent unnecessary layout destruction
            if (resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE) {
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
        } catch (_: Throwable) {
        }
    }

    private fun applyScreenshotProtection() {
        // TV displays are HDMI external outputs where FLAG_SECURE causes SurfaceFlinger buffer
        // allocation failures or display dropping on low-end TV boxes.
        if (isTelevision()) {
            try {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } catch (_: Exception) {
            }
            return
        }
        try {
            if (blockScreenshots) {
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE
                )
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        } catch (_: Exception) {
        }
    }

    private fun isValidMac(mac: String): Boolean {
        val cleaned = mac.replace(":", "").replace("-", "").uppercase()
        if (cleaned.length != 12) return false
        if (!cleaned.all { it in '0'..'9' || it in 'A'..'F' }) return false
        if (cleaned == "020000000000" || cleaned.all { it == '0' }) return false
        return true
    }

    private fun formatMac(bytes: ByteArray): String {
        if (bytes.size < 6) return ""
        return bytes.take(6).joinToString(":") { "%02X".format(it) }
    }

    private fun readMacFromSysfs(iface: String): String {
        return try {
            val file = File("/sys/class/net/$iface/address")
            if (!file.exists()) return ""
            val mac = file.readText().trim().uppercase()
            if (isValidMac(mac)) mac else ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun readMacAddress(): String {
        val preferred = listOf("eth0", "wlan0", "en0", "en1", "wlan1")
        for (iface in preferred) {
            val mac = readMacFromSysfs(iface)
            if (mac.isNotEmpty()) return mac
        }
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val n = interfaces.nextElement()
                if (n.isLoopback || !n.isUp) continue
                val hw = n.hardwareAddress ?: continue
                val mac = formatMac(hw)
                if (isValidMac(mac)) return mac
            }
        } catch (_: Exception) {
        }
        return ""
    }

    /// معرّف Widevine — فريد لكل جهاز ويبقى بعد factory reset (هواتف + TV).
    private fun readWidevineDeviceId(): String {
        var drm: MediaDrm? = null
        return try {
            drm = MediaDrm(widevineUuid)
            val id = drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
            if (id == null || id.isEmpty()) {
                ""
            } else {
                id.joinToString("") { byte -> "%02x".format(byte) }
            }
        } catch (_: Exception) {
            ""
        } finally {
            try {
                if (drm != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        drm.close()
                    } else {
                        @Suppress("DEPRECATION")
                        drm.release()
                    }
                }
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Settings.Secure.ANDROID_ID — فريد لكل جهاز (و لكل مستخدم/توقيع تطبيق منذ Android 8).
     * ليس Build.ID (نسخة النظام) اللي كيتكرّر بين هواتف بنفس الـ ROM.
     */
    private fun readAndroidId(): String {
        return try {
            val id = Settings.Secure
                .getString(contentResolver, Settings.Secure.ANDROID_ID)
                ?.trim()
                .orEmpty()
            // قيمة معروفة معطّلة على أجهزة قديمة جداً.
            if (id.isEmpty() || id.equals("9774d56d682e549c", ignoreCase = true)) {
                ""
            } else {
                id.uppercase()
            }
        } catch (_: Exception) {
            ""
        }
    }

    /// مكوّنات ثابتة للربط (مخفية عن المستخدم) — تُرسل للوحة فقط.
    private fun readDeviceBindingSeed(): Map<String, String> {
        val out = linkedMapOf<String, String>()
        val widevine = readWidevineDeviceId().trim()
        if (widevine.isNotEmpty()) {
            out["widevine"] = widevine
        }
        val macRaw = readMacAddress()
        if (isValidMac(macRaw)) {
            out["mac"] = macRaw.replace(":", "").replace("-", "").uppercase()
        }
        fun put(key: String, value: String) {
            val v = value.trim()
            if (v.isNotEmpty() && !v.equals("unknown", ignoreCase = true)) {
                out[key] = v
            }
        }
        put("board", Build.BOARD)
        put("hardware", Build.HARDWARE)
        put("brand", Build.BRAND)
        put("manufacturer", Build.MANUFACTURER)
        put("model", Build.MODEL)
        put("device", Build.DEVICE)
        put("product", Build.PRODUCT)
        return out
    }

    private fun readMacForInterface(name: String): String {
        val iface = name.trim()
        if (iface.isEmpty()) return ""
        val fromSys = readMacFromSysfs(iface)
        if (fromSys.isNotEmpty()) return fromSys
        return try {
            val n = NetworkInterface.getByName(iface) ?: return ""
            val mac = formatMac(n.hardwareAddress ?: return "")
            if (isValidMac(mac)) mac else ""
        } catch (_: Exception) {
            ""
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyNativeOrientationLock()
        applyScreenshotProtection()
    }

    override fun onResume() {
        super.onResume()
        applyNativeOrientationLock()
        applyScreenshotProtection()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        mainMethodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceMemoryInfo" -> result.success(getDeviceMemoryInfo())
                "isTelevisionDevice" -> result.success(isTelevision())
                "lockLandscape" -> {
                    flutterWantsLandscape = true
                    applyNativeOrientationLock()
                    result.success(true)
                }
                "lockPortrait" -> {
                    // التطبيق لم يعد يقبل portrait — نبقي الأفقي دائماً.
                    flutterWantsLandscape = true
                    applyNativeOrientationLock()
                    result.success(true)
                }
                "setBlockScreenshots" -> {
                    val block = call.argument<Boolean>("block") ?: true
                    blockScreenshots = block
                    applyScreenshotProtection()
                    result.success(true)
                }
                "getMacAddress" -> result.success(readMacAddress())
                "getAndroidId" -> result.success(readAndroidId())
                "getDeviceBindingSeed" -> result.success(readDeviceBindingSeed())
                "getMacAddressForInterface" -> {
                    val iface = call.argument<String>("interface") ?: ""
                    result.success(readMacForInterface(iface))
                }
                "prepareAdMobAppId" -> {
                    val appId = call.argument<String>("appId")?.trim().orEmpty()
                    if (appId.isEmpty()) {
                        result.success(false)
                    } else {
                        // Persist for next cold start (NovaApplication).
                        try {
                            val prefs = getSharedPreferences(
                                "FlutterSharedPreferences",
                                MODE_PRIVATE,
                            )
                            prefs.edit()
                                .putString("flutter.admob_app_id_android", appId)
                                .apply()
                        } catch (_: Exception) {
                        }
                        result.success(NovaApplication.patchApplicationIdMeta(this, appId))
                    }
                }
                "restartApp" -> {
                    try {
                        val launch = packageManager.getLaunchIntentForPackage(packageName)
                        if (launch == null) {
                            result.error("NO_LAUNCH", "No launch intent for package", null)
                            return@setMethodCallHandler
                        }
                        launch.addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP,
                        )
                        startActivity(launch)
                        finishAffinity()
                        result.success(true)
                        // إعادة تشغيل كاملة للمحرك/الكاش بعد فتح النشاط الجديد.
                        Handler(Looper.getMainLooper()).postDelayed({
                            Process.killProcess(Process.myPid())
                            exitProcess(0)
                        }, 120)
                    } catch (e: Exception) {
                        result.error("RESTART_FAIL", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nova.iptv.license_gate",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "confirmTicket" -> {
                    val ticket = call.argument<String>("ticket") ?: ""
                    val pc = call.argument<String>("pc") ?: ""
                    val eu = call.argument<String>("eu") ?: ""
                    val pkg = call.argument<String>("pkg") ?: ""
                    val bu = call.argument<String>("bu") ?: ""
                    result.success(
                        LicenseNativeGate.confirmTicket(
                            ticket = ticket,
                            purchaseCode = pc,
                            envatoUsername = eu,
                            packageName = pkg,
                            baseUrl = bu,
                        ),
                    )
                }
                "signRequest" -> {
                    val pc = call.argument<String>("pc") ?: ""
                    val eu = call.argument<String>("eu") ?: ""
                    val bu = call.argument<String>("bu") ?: ""
                    val ts = when (val raw = call.argument<Any>("ts")) {
                        is Number -> raw.toLong()
                        is String -> raw.toLongOrNull() ?: 0L
                        else -> 0L
                    }
                    result.success(
                        LicenseNativeGate.signRequest(
                            purchaseCode = pc,
                            envatoUsername = eu,
                            baseUrl = bu,
                            timestampSeconds = ts,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nova.iptv/app_update_progress",
        ).setStreamHandler(AppUpdateProgressPlugin(this))
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            try {
                mainMethodChannel?.invokeMethod("onNativeLowMemory", mapOf("level" to level))
            } catch (_: Exception) {
            }
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        try {
            mainMethodChannel?.invokeMethod("onNativeLowMemory", mapOf("level" to -1))
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        mainMethodChannel = null
        super.onDestroy()
    }
}
