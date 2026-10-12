package uz.shs.better_player_plus

import android.content.Context
import android.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

/**
 * Singleton media cache for Movies/Series (never used for live IPTV).
 * Default size: 300 MB.
 */
@UnstableApi
object BetterPlayerCache {
    const val DEFAULT_CACHE_BYTES: Long = 300L * 1024L * 1024L

    @Volatile
    private var instance: SimpleCache? = null

    fun createCache(context: Context, cacheFileSize: Long): SimpleCache? {
        val size = if (cacheFileSize > 0) cacheFileSize else DEFAULT_CACHE_BYTES
        val existing = instance
        if (existing != null) return existing
        synchronized(BetterPlayerCache::class.java) {
            if (instance == null) {
                instance = SimpleCache(
                    File(context.cacheDir, "betterPlayerCache"),
                    LeastRecentlyUsedCacheEvictor(size),
                    StandaloneDatabaseProvider(context)
                )
                Log.i(TAG, "Cache created sizeBytes=$size")
            }
            return instance
        }
    }

    @JvmStatic
    fun releaseCache() {
        try {
            synchronized(BetterPlayerCache::class.java) {
                instance?.release()
                instance = null
                Log.i(TAG, "Cache released")
            }
        } catch (exception: Exception) {
            Log.e(TAG, "releaseCache: $exception")
        }
    }

    private const val TAG = "NovaMedia3Cache"
}
