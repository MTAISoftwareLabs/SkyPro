package uz.shs.better_player_plus

import android.content.Context
import android.net.Uri
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import java.net.CookieHandler
import java.net.CookieManager
import java.net.CookiePolicy

@UnstableApi
internal object DataSourceUtils {
    private const val USER_AGENT = "User-Agent"
    private const val DEFAULT_UA = "VLC/3.0.21 LibVLC/3.0.21"

    const val CONNECT_TIMEOUT_MS = 10_000
    const val READ_TIMEOUT_MS = 15_000

    /** Live: tolerate short CDN quiet gaps without killing the long GET. */
    const val LIVE_READ_TIMEOUT_MS = 20_000

    private val cookieManager: CookieManager = CookieManager().apply {
        setCookiePolicy(CookiePolicy.ACCEPT_ORIGINAL_SERVER)
    }

    @Volatile
    private var bandwidthMeter: DefaultBandwidthMeter? = null

    private fun installCookies() {
        if (CookieHandler.getDefault() !== cookieManager) {
            CookieHandler.setDefault(cookieManager)
        }
    }

    private fun sharedBandwidthMeter(context: Context): DefaultBandwidthMeter {
        val existing = bandwidthMeter
        if (existing != null) return existing
        synchronized(this) {
            val again = bandwidthMeter
            if (again != null) return again
            val created = DefaultBandwidthMeter.Builder(context.applicationContext).build()
            bandwidthMeter = created
            return created
        }
    }

    @JvmStatic
    fun getUserAgent(headers: Map<String, String>?): String {
        headers?.get(USER_AGENT)?.takeIf { it.isNotBlank() }?.let { return it }
        return DEFAULT_UA
    }

    @JvmStatic
    @JvmOverloads
    fun getDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?,
        forLive: Boolean = false,
        /** When true (soft-reload/retry), avoid pooled half-open sockets. */
        forceFreshConnection: Boolean = false,
        context: Context? = null,
    ): DataSource.Factory {
        installCookies()
        val props = LinkedHashMap<String, String>()
        // Avoid duplicate User-Agent (setUserAgent + request props) — some panels reject it.
        headers?.forEach { (k, v) ->
            if (!k.equals(USER_AGENT, ignoreCase = true)) {
                props[k] = v
            }
        }
        // Do not force Accept-Encoding/Connection for normal playback. Let the
        // native HTTP stack negotiate these headers. On a confirmed soft reload
        // only, close the previous socket so a stale long-lived IPTV GET cannot
        // be reused.
        if (forceFreshConnection) {
            val existingConn = props.keys.firstOrNull { it.equals("Connection", ignoreCase = true) }
            if (existingConn != null) props[existingConn] = "close" else props["Connection"] = "close"
        }

        if (forLive) {
            if (!props.keys.any { it.equals("Cache-Control", ignoreCase = true) }) {
                props["Cache-Control"] = "no-cache"
            }
            if (!props.keys.any { it.equals("Pragma", ignoreCase = true) }) {
                props["Pragma"] = "no-cache"
            }
        }
        val ua = userAgent?.takeIf { it.isNotBlank() } ?: DEFAULT_UA
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(ua)
            .setAllowCrossProtocolRedirects(true)
            .setKeepPostFor302Redirects(true)
            .setConnectTimeoutMs(CONNECT_TIMEOUT_MS)
            .setReadTimeoutMs(if (forLive) LIVE_READ_TIMEOUT_MS else READ_TIMEOUT_MS)
            .setDefaultRequestProperties(props)
        if (context != null) {
            http.setTransferListener(sharedBandwidthMeter(context))
            return DefaultDataSource.Factory(context, http)
        }
        return http
    }

    @JvmStatic
    fun bitrateEstimate(): Long = bandwidthMeter?.bitrateEstimate ?: 0L

    @JvmStatic
    fun isHTTP(uri: Uri?): Boolean {
        val scheme = uri?.scheme ?: return false
        return scheme.equals("http", true) || scheme.equals("https", true)
    }
}
