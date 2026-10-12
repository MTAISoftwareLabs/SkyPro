package uz.shs.better_player_plus

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.FileDataSource
import androidx.media3.datasource.cache.CacheDataSink
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter

/**
 * VOD cache factory. Does NOT use FLAG_BLOCK_ON_CACHE.
 * Reuses a process-wide BandwidthMeter to avoid per-load allocations.
 */
@UnstableApi
internal class CacheDataSourceFactory(
    private val context: Context,
    private val maxCacheSize: Long,
    private val maxFileSize: Long,
    upstreamDataSource: DataSource.Factory?
) : DataSource.Factory {
    private var defaultDatasourceFactory: DefaultDataSource.Factory? = null

    override fun createDataSource(): CacheDataSource {
        val cache = BetterPlayerCache.createCache(context, maxCacheSize)
            ?: throw IllegalStateException("Cache can't be null.")
        val fileSize = if (maxFileSize > 0) maxFileSize else maxCacheSize
        return CacheDataSource(
            cache,
            defaultDatasourceFactory?.createDataSource(),
            FileDataSource(),
            CacheDataSink(cache, fileSize),
            CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR,
            null
        )
    }

    init {
        upstreamDataSource?.let {
            defaultDatasourceFactory = DefaultDataSource.Factory(context, upstreamDataSource)
            defaultDatasourceFactory?.setTransferListener(sharedBandwidthMeter(context))
        }
    }

    companion object {
        @Volatile
        private var bandwidthMeter: DefaultBandwidthMeter? = null

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
    }
}
