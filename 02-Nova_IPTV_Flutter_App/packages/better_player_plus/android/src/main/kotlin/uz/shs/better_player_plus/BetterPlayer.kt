package uz.shs.better_player_plus

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaFormat
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.Surface
import android.view.accessibility.CaptioningManager
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.lifecycle.Observer
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.dash.DefaultDashChunkSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.exoplayer.drm.DummyExoMediaDrm
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.drm.UnsupportedDrmException
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import androidx.media3.exoplayer.smoothstreaming.DefaultSsChunkSource
import androidx.media3.exoplayer.smoothstreaming.SsMediaSource
import androidx.media3.exoplayer.source.ClippingMediaSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.ui.PlayerNotificationManager
import androidx.media3.ui.PlayerNotificationManager.BitmapCallback
import androidx.media3.ui.PlayerNotificationManager.MediaDescriptionAdapter
import androidx.work.Data
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry.SurfaceTextureEntry
import uz.shs.better_player_plus.DataSourceUtils.getDataSourceFactory
import uz.shs.better_player_plus.DataSourceUtils.getUserAgent
import uz.shs.better_player_plus.DataSourceUtils.isHTTP
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.min

/**
 * Production Media3 ExoPlayer bridge for Flutter Texture output.
 *
 * One ExoPlayer per texture instance. Channel/URL switches reuse the same player
 * and only replace MediaItems/MediaSources. Heavy MediaSource work runs off the
 * main thread. Automatic retry (max 5, exponential backoff) for transient errors.
 *
 * Note: Flutter Texture requires a Surface backed by SurfaceTexture (TextureView
 * pipeline). A native SurfaceView would need a PlatformView rewrite of the Flutter
 * surface; all other Media3 optimizations from the rebuild spec are applied here.
 */
@UnstableApi
internal class BetterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    customDefaultLoadControl: CustomDefaultLoadControl?,
    result: MethodChannel.Result
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mediaExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "nova-media3-source").apply { isDaemon = true }
    }
    private val loadGeneration = AtomicInteger(0)
    private val retryAttempt = AtomicInteger(0)
    private var pendingRetryRunnable: Runnable? = null
    private var stallWatchdogRunnable: Runnable? = null

    private val eventSink = QueuingEventSink()
    private val trackSelector: DefaultTrackSelector = buildTrackSelector(appContext)
    private val loadControl: LoadControl
    private val exoPlayer: ExoPlayer
    private var playerListener: Player.Listener? = null
    /**
     * MPEG-TS IPTV: ALLOW_NON_IDR + DETECT_ACCESS_UNITS + HDMV_DTS
     * (ExoPlayer issue #8571). Timestamp search = 3000 packets.
     */
    private val extractorsFactory = DefaultExtractorsFactory()
        .setTsExtractorFlags(
            DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or
                DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS or
                DefaultTsPayloadReaderFactory.FLAG_ENABLE_HDMV_DTS_AUDIO_STREAMS
        )
        .setTsExtractorTimestampSearchBytes(3000 * TsExtractor.TS_PACKET_SIZE)
    private val timelineWindow = Timeline.Window()
    private val liveLoadErrorPolicy: LoadErrorHandlingPolicy =
        object : DefaultLoadErrorHandlingPolicy(LIVE_LOAD_ERROR_RETRIES) {
            override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
                val n = loadErrorInfo.errorCount.coerceAtMost(5)
                return min(500L * (1L shl (n - 1)), 8_000L)
            }
        }

    private var isInitialized = false
    private var surface: Surface? = null
    private var key: String? = null
    private var playerNotificationManager: PlayerNotificationManager? = null
    private var refreshHandler: Handler? = null
    private var refreshRunnable: Runnable? = null
    private var exoPlayerEventListener: Player.Listener? = null
    private var bitmap: Bitmap? = null
    private var mediaSession: MediaSessionCompat? = null
    private var drmSessionManager: DrmSessionManager? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private val workManager: WorkManager = WorkManager.getInstance(appContext)
    private val workerObserverMap: HashMap<UUID, Observer<WorkInfo?>> = HashMap()
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        customDefaultLoadControl ?: CustomDefaultLoadControl()
    private var lastSendBufferedPosition = 0L

    private var lastDataSource: String? = null
    private var lastFormatHint: String? = null
    private var lastHeaders: Map<String, String>? = null
    private var lastUseCache: Boolean = false
    private var lastMaxCacheSize: Long = 0
    private var lastMaxCacheFileSize: Long = 0
    private var lastOverriddenDuration: Long = 0
    private var lastLicenseUrl: String? = null
    private var lastDrmHeaders: Map<String, String>? = null
    private var lastCacheKey: String? = null
    private var lastClearKey: String? = null
    private var lastIsLiveStream: Boolean = false
    private var lastLoadStartElapsed: Long = 0L
    private var disposed = false
    /** Preserved across media swaps so Dart pause is not overridden. */
    private var desiredPlayWhenReady = true
    @Volatile
    private var probedFps = 0f
    private var fpsDecoderRendered = 0
    private var fpsDecoderAtElapsed = 0L
    private var fpsFrameListener: androidx.media3.exoplayer.video.VideoFrameMetadataListener? = null

    // Stall detection (BUFFERING / frozen position without PlaybackException).
    private var bufferingSinceElapsed: Long = 0L
    private var lastPositionSample: Long = -1L
    private var lastPositionSampleElapsed: Long = 0L
    private var lastSoftReloadElapsed: Long = 0L
    private var softReloadCount: Int = 0
    /** First READY for current media — soft-reload grace window. */
    private var mediaReadyElapsed: Long = 0L
    /** Timestamps of recent BUFFERING entries — detect underrun loops. */
    private val recentBufferingStartsMs = ArrayDeque<Long>()
    private var forceFreshHttpConnection: Boolean = false

    init {
        val cfg = this.customDefaultLoadControl
        // Production IPTV LoadControl: min/max/playback/rebuffer from Dart, default 40/150/1/3.
        loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                cfg.minBufferMs,
                cfg.maxBufferMs,
                cfg.bufferForPlaybackMs,
                cfg.bufferForPlaybackAfterRebufferMs
            )
            .build()

        val preferSoftware = cfg.preferSoftwareDecoder
        // Hardware: decoder fallback + extension PREFER (FFmpeg/AV1 AARs).
        // Software: fallback off + extension OFF.
        val renderersFactory = DefaultRenderersFactory(appContext).apply {
            if (preferSoftware) {
                setEnableDecoderFallback(false)
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF)
            } else {
                setEnableDecoderFallback(true)
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            }
        }

        val mediaSourceFactory = DefaultMediaSourceFactory(
            DefaultDataSource.Factory(appContext),
            extractorsFactory,
        )

        exoPlayer = ExoPlayer.Builder(appContext, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setHandleAudioBecomingNoisy(!isLeanbackDevice(appContext))
            .build()

        exoPlayer.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            /* handleAudioFocus= */ true,
        )

        logMem("player_create")
        Log.i(
            TAG,
            "Player created loadControl=[" +
                "${cfg.minBufferMs},${cfg.maxBufferMs}," +
                "${cfg.bufferForPlaybackMs},${cfg.bufferForPlaybackAfterRebufferMs}] " +
                "decoder=" +
                (if (preferSoftware) "software" else "hardware")
        )
        setupVideoPlayer(eventChannel, textureEntry, result)
    }

    private fun cancelPendingRetry() {
        pendingRetryRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingRetryRunnable = null
    }

    private fun cancelStallWatchdog() {
        stallWatchdogRunnable?.let { mainHandler.removeCallbacks(it) }
        stallWatchdogRunnable = null
        bufferingSinceElapsed = 0L
        lastPositionSample = -1L
        lastPositionSampleElapsed = 0L
    }

    /**
     * Progressive live often stalls in STATE_BUFFERING with no PlaybackException
     * (stale socket / stuck TsExtractor). Channel-zap works because MediaSource is
     * recreated — this watchdog does the same soft reload automatically.
     *
     * Armed only after the first READY so startup buffering is not treated as a stall.
     */
    private fun startStallWatchdog() {
        if (disposed || !lastIsLiveStream) return
        stallWatchdogRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                if (disposed || !lastIsLiveStream) {
                    stallWatchdogRunnable = null
                    return
                }
                try {
                    evaluateStallAndMaybeReload()
                } catch (e: Exception) {
                    Log.e(TAG, "Stall watchdog error: $e")
                }
                if (!disposed && lastIsLiveStream) {
                    mainHandler.postDelayed(this, STALL_POLL_MS)
                } else {
                    stallWatchdogRunnable = null
                }
            }
        }
        stallWatchdogRunnable = runnable
        mainHandler.postDelayed(runnable, STALL_POLL_MS)
    }

    private fun evaluateStallAndMaybeReload() {
        if (!desiredPlayWhenReady || !isInitialized) return
        val now = SystemClock.elapsedRealtime()
        // لا تقتل التشغيل في ثواني الإقلاع الأولى (يبدو كتجميد→قفزة).
        if (mediaReadyElapsed > 0L &&
            now - mediaReadyElapsed < SOFT_RELOAD_STARTUP_GRACE_MS
        ) {
            return
        }
        val state = exoPlayer.playbackState
        val pos = exoPlayer.currentPosition
        val buffered = exoPlayer.bufferedPosition
        val bufferedAhead = (buffered - pos).coerceAtLeast(0L)

        if (state == Player.STATE_BUFFERING) {
            if (bufferingSinceElapsed == 0L) {
                bufferingSinceElapsed = now
                Log.w(
                    TAG,
                    "Stall: bufferingStart pos=$pos buffered=$buffered aheadMs=$bufferedAhead " +
                        "live=$lastIsLiveStream url=${safeUrl(lastDataSource)}"
                )
            } else {
                val bufferingFor = now - bufferingSinceElapsed
                if (bufferingFor >= STALL_BUFFERING_MS) {
                    Log.w(
                        TAG,
                        "Stall: prolonged BUFFERING ${bufferingFor}ms pos=$pos aheadMs=$bufferedAhead " +
                            "→ softReload (recreate MediaSource)"
                    )
                    softReloadMediaSource("prolonged_buffering_${bufferingFor}ms")
                    return
                }
            }
        } else {
            bufferingSinceElapsed = 0L
        }

        // Frozen progressive live: READY, want play, position not advancing, buffer empty.
        if (state == Player.STATE_READY && exoPlayer.playWhenReady) {
            if (lastPositionSample < 0L) {
                lastPositionSample = pos
                lastPositionSampleElapsed = now
            } else if (pos != lastPositionSample) {
                lastPositionSample = pos
                lastPositionSampleElapsed = now
            } else {
                val frozenFor = now - lastPositionSampleElapsed
                if (frozenFor >= STALL_FROZEN_MS && bufferedAhead < 1_500L) {
                    Log.w(
                        TAG,
                        "Stall: frozen position ${frozenFor}ms pos=$pos aheadMs=$bufferedAhead " +
                            "→ softReload"
                    )
                    softReloadMediaSource("frozen_position_${frozenFor}ms")
                }
            }
        } else if (state != Player.STATE_BUFFERING) {
            lastPositionSample = pos
            lastPositionSampleElapsed = now
        }
    }

    /**
     * Short rebuffer loops (e.g. every ~20s) with tiny aheadMs on progressive
     * TS often mean the long HTTP GET degraded. Refresh MediaSource/TCP after
     * several underruns — not on a single healthy rebuffer.
     */
    private fun noteLiveRebufferAndMaybeRefresh() {
        val now = SystemClock.elapsedRealtime()
        if (mediaReadyElapsed > 0L &&
            now - mediaReadyElapsed < SOFT_RELOAD_STARTUP_GRACE_MS
        ) {
            return
        }
        recentBufferingStartsMs.addLast(now)
        while (recentBufferingStartsMs.isNotEmpty() &&
            now - recentBufferingStartsMs.first() > REBUFFER_LOOP_WINDOW_MS
        ) {
            recentBufferingStartsMs.removeFirst()
        }
        Log.w(
            TAG,
            "Rebuffer count=${recentBufferingStartsMs.size} in ${REBUFFER_LOOP_WINDOW_MS}ms window"
        )
        if (recentBufferingStartsMs.size >= REBUFFER_LOOP_THRESHOLD) {
            softReloadMediaSource("rebuffer_loop_${recentBufferingStartsMs.size}")
        }
    }

    private fun softReloadMediaSource(reason: String) {
        if (disposed) return
        val url = lastDataSource
        if (url.isNullOrEmpty()) return
        val now = SystemClock.elapsedRealtime()
        // Startup grace: لا تقفز للـ live edge بعد ثوانٍ من البداية.
        if (mediaReadyElapsed > 0L &&
            now - mediaReadyElapsed < SOFT_RELOAD_STARTUP_GRACE_MS
        ) {
            Log.w(TAG, "SoftReload skipped startup grace reason=$reason")
            return
        }
        if (now - lastSoftReloadElapsed < SOFT_RELOAD_COOLDOWN_MS) {
            Log.w(TAG, "SoftReload skipped cooldown reason=$reason")
            return
        }
        if (softReloadCount >= MAX_SOFT_RELOADS) {
            Log.e(TAG, "SoftReload exhausted ($MAX_SOFT_RELOADS) reason=$reason")
            eventSink.error(
                "VideoError",
                "Live stream stalled after $MAX_SOFT_RELOADS soft reloads ($reason)",
                ""
            )
            return
        }
        softReloadCount++
        lastSoftReloadElapsed = now
        bufferingSinceElapsed = 0L
        lastPositionSample = -1L
        recentBufferingStartsMs.clear()
        // Soft-reload must not reuse a half-open pooled socket.
        forceFreshHttpConnection = true
        Log.w(
            TAG,
            "SoftReload #$softReloadCount/$MAX_SOFT_RELOADS reason=$reason " +
                "url=${safeUrl(url)} — same effect as channel zap"
        )
        eventSink.success(
            mapOf(
                "event" to "softReload",
                "reason" to reason,
                "attempt" to softReloadCount
            )
        )
        setDataSourceInternal(
            key = key,
            dataSource = lastDataSource,
            formatHint = lastFormatHint,
            result = object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.i(TAG, "SoftReload media applied reason=$reason")
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "SoftReload failed: $errorMessage")
                }

                override fun notImplemented() {}
            },
            headers = lastHeaders,
            useCache = false,
            maxCacheSize = 0,
            maxCacheFileSize = 0,
            overriddenDuration = lastOverriddenDuration,
            licenseUrl = lastLicenseUrl,
            drmHeaders = lastDrmHeaders,
            cacheKey = lastCacheKey,
            clearKey = lastClearKey,
            isLiveStream = lastIsLiveStream,
            resetRetryCounter = false,
            fromSoftReload = true
        )
    }

    @OptIn(UnstableApi::class)
    fun setDataSource(
        context: Context,
        key: String?,
        dataSource: String?,
        formatHint: String?,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?,
        isLiveStream: Boolean = false
    ) {
        softReloadCount = 0
        lastSoftReloadElapsed = 0L
        mediaReadyElapsed = 0L
        resetFpsProbe()
        setDataSourceInternal(
            key = key,
            dataSource = dataSource,
            formatHint = formatHint,
            result = result,
            headers = headers,
            useCache = useCache,
            maxCacheSize = maxCacheSize,
            maxCacheFileSize = maxCacheFileSize,
            overriddenDuration = overriddenDuration,
            licenseUrl = licenseUrl,
            drmHeaders = drmHeaders,
            cacheKey = cacheKey,
            clearKey = clearKey,
            isLiveStream = isLiveStream,
            resetRetryCounter = true,
            fromSoftReload = false
        )
    }

    /**
     * @param resetRetryCounter false when reloading from automatic retry so attempts accumulate.
     */
    private fun setDataSourceInternal(
        key: String?,
        dataSource: String?,
        formatHint: String?,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?,
        isLiveStream: Boolean,
        resetRetryCounter: Boolean,
        fromSoftReload: Boolean = false
    ) {
        if (disposed) {
            result.error("disposed", "Player released", null)
            return
        }
        this.key = key
        isInitialized = false
        cancelPendingRetry()
        if (!fromSoftReload) {
            cancelStallWatchdog()
        } else {
            bufferingSinceElapsed = 0L
            lastPositionSample = -1L
        }
        if (resetRetryCounter) {
            retryAttempt.set(0)
        }
        lastDataSource = dataSource
        lastFormatHint = formatHint
        lastHeaders = headers
        lastUseCache = useCache
        lastMaxCacheSize = maxCacheSize
        lastMaxCacheFileSize = maxCacheFileSize
        lastOverriddenDuration = overriddenDuration
        lastLicenseUrl = licenseUrl
        lastDrmHeaders = drmHeaders
        lastCacheKey = cacheKey
        lastClearKey = clearKey
        lastIsLiveStream = isLiveStream

        val generation = loadGeneration.incrementAndGet()
        lastLoadStartElapsed = SystemClock.elapsedRealtime()
        // Always log media loads for IPTV diagnostics (filter: NovaMedia3).
        Log.i(
            TAG,
            "Media loading gen=$generation live=$isLiveStream softReload=$fromSoftReload " +
                "cache=$useCache format=$formatHint url=${safeUrl(dataSource)}"
        )

        mediaExecutor.execute {
            try {
                val uri = dataSource?.toUri()
                configureDrm(licenseUrl, drmHeaders, clearKey)

                var dataSourceFactory: DataSource.Factory
                val userAgent = getUserAgent(headers)
                if (isHTTP(uri)) {
                    dataSourceFactory = getDataSourceFactory(
                        userAgent,
                        headers,
                        forLive = isLiveStream,
                        // Live MPEG-TS: always close previous HTTP GET (Xtream 1-stream limit).
                        forceFreshConnection = isLiveStream || forceFreshHttpConnection || fromSoftReload,
                        context = appContext,
                    )
                    forceFreshHttpConnection = false
                    // Live IPTV must never use cache. VOD may use disk cache.
                    if (!isLiveStream && useCache && maxCacheSize > 0 && maxCacheFileSize > 0) {
                        dataSourceFactory = CacheDataSourceFactory(
                            appContext,
                            maxCacheSize,
                            maxCacheFileSize,
                            dataSourceFactory
                        )
                    }
                } else {
                    dataSourceFactory = DefaultDataSource.Factory(appContext)
                }

                val mediaSource = buildMediaSource(
                    uri,
                    dataSourceFactory,
                    formatHint,
                    cacheKey,
                    appContext,
                    isLiveStream
                )
                val finalSource = if (overriddenDuration != 0L) {
                    ClippingMediaSource.Builder(mediaSource)
                        .setStartPositionMs(0)
                        .setEndPositionMs(overriddenDuration * 1000)
                        .build()
                } else {
                    mediaSource
                }

                mainHandler.post {
                    if (disposed || generation != loadGeneration.get()) {
                        if (DEBUG) Log.i(TAG, "Cancel stale media load gen=$generation")
                        result.success(null)
                        return@post
                    }
                    try {
                        // Fresh channel: drop any prior audio override that can leave IPTV silent.
                        clearAudioTrackOverride()
                        exoPlayer.volume = 1f
                        if (isLiveStream) {
                            try {
                                exoPlayer.stop()
                            } catch (_: Exception) {
                            }
                        }
                        exoPlayer.setMediaSource(finalSource, /* resetPosition= */ true)
                        exoPlayer.prepare()
                        // Honor Dart play/pause — do not force playWhenReady=true.
                        exoPlayer.playWhenReady = desiredPlayWhenReady
                        applyLoudnessEnhancer(exoPlayer.audioSessionId)
                        Log.i(
                            TAG,
                            "Media prepared gen=$generation live=$isLiveStream " +
                                "playWhenReady=$desiredPlayWhenReady"
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "setMediaSource failed: $e")
                        result.error("VideoError", "Failed to set media source: $e", null)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "buildMediaSource failed: $e")
                mainHandler.post {
                    if (!disposed && generation == loadGeneration.get()) {
                        result.error("VideoError", "Failed to build media source: $e", null)
                    } else {
                        result.success(null)
                    }
                }
            }
        }
    }

    private fun configureDrm(
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        clearKey: String?
    ) {
        drmSessionManager = null
        if (!licenseUrl.isNullOrEmpty()) {
            val httpMediaDrmCallback =
                HttpMediaDrmCallback(licenseUrl, DefaultHttpDataSource.Factory())
            drmHeaders?.forEach { (drmKey, drmValue) ->
                httpMediaDrmCallback.setKeyRequestProperty(drmKey, drmValue)
            }
            val drmSchemeUuid = Util.getDrmUuid("widevine")
            if (drmSchemeUuid != null) {
                drmSessionManager = DefaultDrmSessionManager.Builder()
                    .setUuidAndExoMediaDrmProvider(drmSchemeUuid) { uuid: UUID? ->
                        try {
                            val mediaDrm = FrameworkMediaDrm.newInstance(uuid!!)
                            mediaDrm.setPropertyString("securityLevel", "L3")
                            mediaDrm
                        } catch (_: UnsupportedDrmException) {
                            DummyExoMediaDrm()
                        }
                    }
                    .setMultiSession(false)
                    .build(httpMediaDrmCallback)
            }
        } else if (!clearKey.isNullOrEmpty()) {
            drmSessionManager = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(
                    C.CLEARKEY_UUID,
                    FrameworkMediaDrm.DEFAULT_PROVIDER
                ).build(LocalMediaDrmCallback(clearKey.toByteArray()))
        }
    }

    fun setupPlayerNotification(
        context: Context, title: String, author: String?,
        imageUrl: String?, notificationChannelName: String?,
        activityName: String
    ) {
        // Avoid duplicate notification listeners / refresh loops.
        disposeRemoteNotifications()
        BetterPlayerForegroundService.start(context, title, activityName)
        val mediaDescriptionAdapter: MediaDescriptionAdapter = object : MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): String = title

            @SuppressLint("UnspecifiedImmutableFlag")
            override fun createCurrentContentIntent(player: Player): PendingIntent? {
                val packageName = context.applicationContext.packageName
                val notificationIntent = Intent()
                notificationIntent.setClassName(packageName, "$packageName.$activityName")
                notificationIntent.flags =
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                return PendingIntent.getActivity(
                    context, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
                )
            }

            override fun getCurrentContentText(player: Player): String? = author

            override fun getCurrentLargeIcon(player: Player, callback: BitmapCallback): Bitmap? {
                if (imageUrl == null) return null
                if (bitmap != null) return bitmap
                val imageWorkRequest = OneTimeWorkRequest.Builder(ImageWorker::class.java)
                    .addTag(imageUrl)
                    .setInputData(
                        Data.Builder()
                            .putString(BetterPlayerConstants.URL_PARAMETER, imageUrl)
                            .build()
                    )
                    .build()
                workManager.enqueue(imageWorkRequest)
                val workInfoObserver = Observer { workInfo: WorkInfo? ->
                    try {
                        if (workInfo != null) {
                            val state = workInfo.state
                            if (state == WorkInfo.State.SUCCEEDED) {
                                val filePath =
                                    workInfo.outputData.getString(BetterPlayerConstants.FILE_PATH_PARAMETER)
                                bitmap = BitmapFactory.decodeFile(filePath)
                                bitmap?.let { callback.onBitmap(it) }
                            }
                            if (state == WorkInfo.State.SUCCEEDED ||
                                state == WorkInfo.State.CANCELLED ||
                                state == WorkInfo.State.FAILED
                            ) {
                                val uuid = imageWorkRequest.id
                                val observer = workerObserverMap.remove(uuid)
                                if (observer != null) {
                                    workManager.getWorkInfoByIdLiveData(uuid)
                                        .removeObserver(observer)
                                }
                            }
                        }
                    } catch (exception: Exception) {
                        Log.e(TAG, "Image select error: $exception")
                    }
                }
                val workerUuid = imageWorkRequest.id
                workManager.getWorkInfoByIdLiveData(workerUuid).observeForever(workInfoObserver)
                workerObserverMap[workerUuid] = workInfoObserver
                return null
            }
        }
        var playerNotificationChannelName = notificationChannelName
        if (notificationChannelName == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                DEFAULT_NOTIFICATION_CHANNEL,
                DEFAULT_NOTIFICATION_CHANNEL,
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = DEFAULT_NOTIFICATION_CHANNEL
            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
            playerNotificationChannelName = DEFAULT_NOTIFICATION_CHANNEL
        }

        playerNotificationManager = PlayerNotificationManager.Builder(
            context, NOTIFICATION_ID, playerNotificationChannelName!!
        ).setMediaDescriptionAdapter(mediaDescriptionAdapter).build()

        playerNotificationManager?.apply {
            setPlayer(ForwardingPlayer(exoPlayer))
            setUseNextAction(false)
            setUsePreviousAction(false)
            setUseStopAction(false)
        }

        refreshHandler = Handler(Looper.getMainLooper())
        refreshRunnable = Runnable {
            val playbackState: PlaybackStateCompat = if (exoPlayer.isPlaying) {
                PlaybackStateCompat.Builder()
                    .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                    .setState(PlaybackStateCompat.STATE_PLAYING, position, 1.0f)
                    .build()
            } else {
                PlaybackStateCompat.Builder()
                    .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                    .setState(PlaybackStateCompat.STATE_PAUSED, position, 1.0f)
                    .build()
            }
            mediaSession?.setPlaybackState(playbackState)
            refreshHandler?.postDelayed(refreshRunnable!!, 1000)
        }
        refreshHandler?.postDelayed(refreshRunnable!!, 0)
        exoPlayerEventListener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                mediaSession?.setMetadata(
                    MediaMetadataCompat.Builder()
                        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, getDuration())
                        .build()
                )
            }
        }
        exoPlayerEventListener?.let { exoPlayer.addListener(it) }
        exoPlayer.seekTo(0)
    }

    fun disposeRemoteNotifications() {
        exoPlayerEventListener?.let { exoPlayer.removeListener(it) }
        exoPlayerEventListener = null
        refreshHandler?.removeCallbacksAndMessages(null)
        refreshHandler = null
        refreshRunnable = null
        playerNotificationManager?.setPlayer(null)
        playerNotificationManager = null
        bitmap = null
    }

    private fun applyLoudnessEnhancer(audioSessionId: Int) {
        try {
            loudnessEnhancer?.release()
        } catch (_: Exception) {
        }
        loudnessEnhancer = null
        if (audioSessionId == 0) return
        try {
            loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                setEnabled(true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "LoudnessEnhancer unavailable: $e")
        }
    }

    private fun buildMediaSource(
        uri: Uri?,
        mediaDataSourceFactory: DataSource.Factory,
        formatHint: String?,
        cacheKey: String?,
        context: Context,
        isLiveStream: Boolean
    ): MediaSource {
        val type: Int = when {
            formatHint.equals(FORMAT_SS, true) -> C.CONTENT_TYPE_SS
            formatHint.equals(FORMAT_DASH, true) -> C.CONTENT_TYPE_DASH
            formatHint.equals(FORMAT_HLS, true) -> C.CONTENT_TYPE_HLS
            formatHint.equals(FORMAT_OTHER, true) -> C.CONTENT_TYPE_OTHER
            uri != null -> Util.inferContentType(uri)
            else -> C.CONTENT_TYPE_OTHER
        }

        val mediaItemBuilder = MediaItem.Builder().setUri(uri)
        if (!cacheKey.isNullOrEmpty()) {
            mediaItemBuilder.setCustomCacheKey(cacheKey)
        }
        val mediaItem = mediaItemBuilder.build()
        val drmSessionManagerProvider: DrmSessionManagerProvider? =
            drmSessionManager?.let { mgr -> DrmSessionManagerProvider { mgr } }
        val loadPolicy: LoadErrorHandlingPolicy? =
            if (isLiveStream) liveLoadErrorPolicy else null

        Log.i(
            TAG,
            "MediaSource type=$type live=$isLiveStream " +
                "url=${safeUrl(uri?.toString())}"
        )

        return when (type) {
            C.CONTENT_TYPE_SS -> SsMediaSource.Factory(
                DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                DefaultDataSource.Factory(context, mediaDataSourceFactory)
            ).apply {
                drmSessionManagerProvider?.let { setDrmSessionManagerProvider(it) }
                loadPolicy?.let { setLoadErrorHandlingPolicy(it) }
            }.createMediaSource(mediaItem)

            C.CONTENT_TYPE_DASH -> DashMediaSource.Factory(
                DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                DefaultDataSource.Factory(context, mediaDataSourceFactory)
            ).apply {
                drmSessionManagerProvider?.let { setDrmSessionManagerProvider(it) }
                loadPolicy?.let { setLoadErrorHandlingPolicy(it) }
            }.createMediaSource(mediaItem)

            C.CONTENT_TYPE_HLS -> HlsMediaSource.Factory(mediaDataSourceFactory)
                .apply {
                    drmSessionManagerProvider?.let { setDrmSessionManagerProvider(it) }
                    loadPolicy?.let { setLoadErrorHandlingPolicy(it) }
                }.createMediaSource(mediaItem)

            C.CONTENT_TYPE_RTSP -> RtspMediaSource.Factory()
                .createMediaSource(mediaItem)

            C.CONTENT_TYPE_OTHER -> ProgressiveMediaSource.Factory(
                mediaDataSourceFactory,
                extractorsFactory
            ).apply {
                drmSessionManagerProvider?.let { setDrmSessionManagerProvider(it) }
                loadPolicy?.let { setLoadErrorHandlingPolicy(it) }
            }.createMediaSource(mediaItem)

            else -> ProgressiveMediaSource.Factory(mediaDataSourceFactory)
                .createMediaSource(mediaItem)
        }
    }

    private fun setupVideoPlayer(
        eventChannel: EventChannel,
        textureEntry: SurfaceTextureEntry,
        result: MethodChannel.Result
    ) {
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(o: Any?, sink: EventSink) {
                    eventSink.setDelegate(sink)
                }

                override fun onCancel(o: Any?) {
                    eventSink.setDelegate(null)
                }
            },
        )
        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer.setVideoSurface(surface)
        attachFpsProbe()
        setAudioAttributes(exoPlayer, false)

        playerListener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        val pos = exoPlayer.currentPosition
                        val ahead = (exoPlayer.bufferedPosition - pos).coerceAtLeast(0L)
                        // aheadMs on progressive MPEG-TS is often ~40ms and misleading.
                        Log.i(
                            TAG,
                            "Buffering started pos=$pos aheadMs=$ahead " +
                                "(progressive ahead often unreliable) live=$lastIsLiveStream"
                        )
                        sendBufferingUpdate(true)
                        eventSink.success(mapOf("event" to "bufferingStart"))
                        if (lastIsLiveStream && isInitialized) {
                            noteLiveRebufferAndMaybeRefresh()
                        }
                    }

                    Player.STATE_READY -> {
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                            logSelectedDecoder()
                            val took = SystemClock.elapsedRealtime() - lastLoadStartElapsed
                            Log.i(TAG, "Playback started readyMs=$took live=$lastIsLiveStream")
                            if (lastIsLiveStream) {
                                mediaReadyElapsed = SystemClock.elapsedRealtime()
                                bufferingSinceElapsed = 0L
                                lastPositionSample = -1L
                                recentBufferingStartsMs.clear()
                                startStallWatchdog()
                            }
                        } else if (lastIsLiveStream) {
                            Log.i(TAG, "Buffering ended pos=${exoPlayer.currentPosition}")
                        }
                        // IPTV: video-only when wrong PID / unsupported preferred track.
                        ensurePlayableAudio("state_ready")
                        mainHandler.postDelayed({
                            if (!disposed) ensurePlayableAudio("state_ready_delayed")
                        }, 700L)
                        // Successful ready ends the current retry streak.
                        retryAttempt.set(0)
                        cancelPendingRetry()
                        bufferingSinceElapsed = 0L
                        // After a healthy ready, allow more soft reloads later in the session.
                        if (softReloadCount > 0 &&
                            SystemClock.elapsedRealtime() - lastSoftReloadElapsed > SOFT_RELOAD_SUCCESS_RESET_MS
                        ) {
                            softReloadCount = 0
                        }
                        eventSink.success(mapOf("event" to "bufferingEnd"))
                    }

                    Player.STATE_ENDED -> {
                        if (DEBUG) Log.i(TAG, "Playback ended")
                        eventSink.success(
                            mapOf(
                                "event" to "completed",
                                "key" to key
                            )
                        )
                    }

                    Player.STATE_IDLE -> if (DEBUG) Log.i(TAG, "Playback state idle")
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (DEBUG) {
                    Log.i(TAG, if (isPlaying) "Playback resumed/playing" else "Playback paused")
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e(TAG, "Playback error code=${error.errorCodeName} msg=${error.message}")
                if (tryAutoRecover(error)) return
                eventSink.error("VideoError", "Video player had error $error", "")
            }
        }
        exoPlayer.addListener(playerListener!!)

        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    /** Exponential retry for transient network/source/timeout errors. Max 5. */
    private fun tryAutoRecover(error: PlaybackException): Boolean {
        // Behind live window: seek to live edge — cheaper than full reload.
        if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            return try {
                cancelPendingRetry()
                exoPlayer.seekToDefaultPosition()
                exoPlayer.prepare()
                exoPlayer.playWhenReady = desiredPlayWhenReady
                if (DEBUG) Log.i(TAG, "Recovered BEHIND_LIVE_WINDOW via seekToDefaultPosition")
                true
            } catch (e: Exception) {
                Log.e(TAG, "BEHIND_LIVE_WINDOW recover failed: $e")
                false
            }
        }

        if (!isRetriable(error)) {
            Log.e(TAG, "Non-retriable error ${error.errorCodeName}")
            return false
        }
        val attempt = retryAttempt.incrementAndGet()
        if (attempt > MAX_RETRIES) {
            Log.e(TAG, "Retry exhausted ($MAX_RETRIES)")
            return false
        }
        cancelPendingRetry()
        val delayMs = min(1000L * (1L shl (attempt - 1)), 16_000L)
        Log.w(TAG, "Retry attempt=$attempt/$MAX_RETRIES in ${delayMs}ms")
        val generationAtSchedule = loadGeneration.get()
        val runnable = Runnable {
            pendingRetryRunnable = null
            if (disposed || generationAtSchedule != loadGeneration.get()) return@Runnable
            val url = lastDataSource
            if (url.isNullOrEmpty()) {
                try {
                    exoPlayer.prepare()
                    exoPlayer.playWhenReady = desiredPlayWhenReady
                } catch (e: Exception) {
                    Log.e(TAG, "Retry prepare failed: $e")
                }
                return@Runnable
            }
            // Reload last media; do NOT reset retryAttempt.
            setDataSourceInternal(
                key = key,
                dataSource = lastDataSource,
                formatHint = lastFormatHint,
                result = object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        Log.i(TAG, "Retry media reload success attempt=$attempt")
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.e(TAG, "Retry media reload failed: $errorMessage")
                    }

                    override fun notImplemented() {}
                },
                headers = lastHeaders,
                useCache = lastUseCache && !lastIsLiveStream,
                maxCacheSize = lastMaxCacheSize,
                maxCacheFileSize = lastMaxCacheFileSize,
                overriddenDuration = lastOverriddenDuration,
                licenseUrl = lastLicenseUrl,
                drmHeaders = lastDrmHeaders,
                cacheKey = lastCacheKey,
                clearKey = lastClearKey,
                isLiveStream = lastIsLiveStream,
                resetRetryCounter = false,
                fromSoftReload = false
            )
        }
        pendingRetryRunnable = runnable
        mainHandler.postDelayed(runnable, delayMs)
        return true
    }

    private fun isRetriable(error: PlaybackException): Boolean {
        return when (error.errorCode) {
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
            PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,
            PlaybackException.ERROR_CODE_TIMEOUT,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FAILED -> true
            else -> error.errorCodeName.contains("IO", true) ||
                error.errorCodeName.contains("TIMEOUT", true)
        }
    }

    private fun logSelectedDecoder() {
        try {
            val vf = exoPlayer.videoFormat
            val af = exoPlayer.audioFormat
            Log.i(
                TAG,
                "Selected decoder video=${vf?.sampleMimeType}/${vf?.width}x${vf?.height} " +
                    "audio=${af?.sampleMimeType} codecs=${vf?.codecs}"
            )
        } catch (e: Exception) {
            Log.w(TAG, "logSelectedDecoder: $e")
        }
    }

    /**
     * IPTV MPEG-TS often exposes empty AAC + real MPEG/AC3 PIDs. Preferring AAC
     * (or a stale override) yields video with no sound. Recover by clearing
     * overrides and walking demux audio tracks until [audioFormat] is non-null.
     */
    private fun ensurePlayableAudio(reason: String) {
        try {
            exoPlayer.volume = 1f
            val current = try {
                exoPlayer.audioFormat
            } catch (_: Exception) {
                null
            }
            if (current != null) {
                if (DEBUG) {
                    Log.i(TAG, "Audio OK ($reason) mime=${current.sampleMimeType}")
                }
                return
            }
            Log.w(TAG, "Silent playback — recovering audio ($reason)")
            clearAudioTrackOverride()
            val tracks = getAudioTracks()
            if (tracks.isEmpty()) {
                Log.w(TAG, "No demux audio tracks to try ($reason)")
                return
            }
            for (row in tracks) {
                val id = (row["id"] as? Number)?.toInt() ?: continue
                val label = (row["label"] as? String)?.ifBlank { null }
                    ?: (row["language"] as? String)?.ifBlank { null }
                    ?: "Audio"
                setAudioTrack(label, id)
                val af = try {
                    exoPlayer.audioFormat
                } catch (_: Exception) {
                    null
                }
                if (af != null) {
                    Log.i(
                        TAG,
                        "Audio recovered ($reason) id=$id mime=${af.sampleMimeType} label=$label"
                    )
                    return
                }
            }
            clearAudioTrackOverride()
            Log.w(TAG, "Audio still missing after trying ${tracks.size} tracks ($reason)")
        } catch (e: Exception) {
            Log.e(TAG, "ensurePlayableAudio failed: $e")
        }
    }

    fun sendBufferingUpdate(isFromBufferingStart: Boolean) {
        val bufferedPosition = exoPlayer.bufferedPosition
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = "bufferingUpdate"
            event["values"] = listOf(listOf(0, bufferedPosition))
            eventSink.success(event)
            lastSendBufferedPosition = bufferedPosition
        }
    }

    @Suppress("DEPRECATION")
    private fun setAudioAttributes(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        exoPlayer?.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            !mixWithOthers
        )
    }

    fun play() {
        desiredPlayWhenReady = true
        exoPlayer.playWhenReady = true
    }

    fun pause() {
        desiredPlayWhenReady = false
        exoPlayer.playWhenReady = false
    }

    fun setLooping(value: Boolean) {
        exoPlayer.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    fun setVolume(value: Double) {
        exoPlayer.volume = max(0.0, min(1.0, value)).toFloat()
    }

    fun setSpeed(value: Double) {
        exoPlayer.playbackParameters = PlaybackParameters(value.toFloat())
    }

    fun setTrackParameters(width: Int, height: Int, bitrate: Int) {
        val parametersBuilder = trackSelector.buildUponParameters()
        if (width != 0 && height != 0) {
            parametersBuilder.setMaxVideoSize(width, height)
        }
        if (bitrate != 0) {
            parametersBuilder.setMaxVideoBitrate(bitrate)
        }
        if (width == 0 && height == 0 && bitrate == 0) {
            parametersBuilder.clearVideoSizeConstraints()
            parametersBuilder.setMaxVideoBitrate(Int.MAX_VALUE)
        }
        trackSelector.setParameters(parametersBuilder)
    }

    fun seekTo(location: Int) {
        exoPlayer.seekTo(location.toLong())
    }

    val position: Long
        get() = exoPlayer.currentPosition

    val absolutePosition: Long
        get() {
            val timeline = exoPlayer.currentTimeline
            if (!timeline.isEmpty) {
                val windowStartTimeMs =
                    timeline.getWindow(0, timelineWindow).windowStartTimeMs
                return windowStartTimeMs + exoPlayer.currentPosition
            }
            return exoPlayer.currentPosition
        }

    private fun sendInitialized() {
        if (!isInitialized) return
        val event: MutableMap<String, Any?> = HashMap()
        event["event"] = "initialized"
        event["key"] = key
        event["duration"] = getDuration()
        exoPlayer.videoFormat?.let { videoFormat ->
            var width = videoFormat.width
            var height = videoFormat.height
            val rotationDegrees = videoFormat.rotationDegrees
            if (rotationDegrees == 90 || rotationDegrees == 270) {
                width = videoFormat.height
                height = videoFormat.width
            }
            event["width"] = width
            event["height"] = height
        }
        eventSink.success(event)
    }

    private fun getDuration(): Long = exoPlayer.duration

    @SuppressLint("InlinedApi")
    fun setupMediaSession(context: Context?): MediaSessionCompat? {
        mediaSession?.release()
        context?.let {
            val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
            val pendingIntent = PendingIntent.getBroadcast(
                context, 0, mediaButtonIntent, PendingIntent.FLAG_IMMUTABLE
            )
            val mediaSession = MediaSessionCompat(context, TAG, null, pendingIntent)
            mediaSession.setCallback(object : MediaSessionCompat.Callback() {
                override fun onSeekTo(pos: Long) {
                    sendSeekToEvent(pos)
                    super.onSeekTo(pos)
                }
            })
            mediaSession.isActive = true
            this.mediaSession = mediaSession
            return mediaSession
        }
        return null
    }

    fun onPictureInPictureStatusChanged(inPip: Boolean) {
        eventSink.success(mapOf("event" to if (inPip) "pipStart" else "pipStop"))
    }

    fun disposeMediaSession() {
        mediaSession?.release()
        mediaSession = null
    }

    fun setAudioTrack(name: String, index: Int) {
        try {
            if (index < 0) {
                clearAudioTrackOverride()
                return
            }
            val mappedTrackInfo = trackSelector.currentMappedTrackInfo ?: return
            for (rendererIndex in 0 until mappedTrackInfo.rendererCount) {
                if (mappedTrackInfo.getRendererType(rendererIndex) != C.TRACK_TYPE_AUDIO) continue
                val trackGroupArray = mappedTrackInfo.getTrackGroups(rendererIndex)
                var hasElementWithoutLabel = false
                var hasStrangeAudioTrack = false
                for (groupIndex in 0 until trackGroupArray.length) {
                    val group = trackGroupArray[groupIndex]
                    for (groupElementIndex in 0 until group.length) {
                        val format = group.getFormat(groupElementIndex)
                        if (format.label == null) hasElementWithoutLabel = true
                        if (format.id != null && format.id == "1/15") hasStrangeAudioTrack = true
                    }
                }
                // Prefer exact match by groupIndex + label/language (IPTV multi-audio).
                for (groupIndex in 0 until trackGroupArray.length) {
                    val group = trackGroupArray[groupIndex]
                    for (groupElementIndex in 0 until group.length) {
                        val format = group.getFormat(groupElementIndex)
                        val label = format.label
                        val language = format.language
                        val nameMatch =
                            name.isNotEmpty() &&
                                (name == label || name == language ||
                                    name.equals(label, ignoreCase = true) ||
                                    name.equals(language, ignoreCase = true))
                        if (nameMatch && index == groupIndex) {
                            setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                            return
                        }
                        if (nameMatch && index == groupElementIndex && trackGroupArray.length == 1) {
                            setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                            return
                        }
                    }
                }
                // Flat index across all audio formats in this renderer.
                var flat = 0
                for (groupIndex in 0 until trackGroupArray.length) {
                    val group = trackGroupArray[groupIndex]
                    for (groupElementIndex in 0 until group.length) {
                        if (flat == index) {
                            setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                            return
                        }
                        flat++
                    }
                }
                for (groupIndex in 0 until trackGroupArray.length) {
                    val group = trackGroupArray[groupIndex]
                    for (groupElementIndex in 0 until group.length) {
                        val label = group.getFormat(groupElementIndex).label
                        if (name == label && index == groupIndex) {
                            setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                            return
                        }
                        if (!hasStrangeAudioTrack && hasElementWithoutLabel && index == groupIndex) {
                            setAudioTrack(rendererIndex, groupIndex, 0)
                            return
                        }
                        if (hasStrangeAudioTrack && name == label) {
                            setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                            return
                        }
                    }
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "setAudioTrack failed$exception")
        }
    }

    fun clearAudioTrackOverride() {
        try {
            val builder = trackSelector.parameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
            trackSelector.setParameters(builder)
        } catch (exception: Exception) {
            Log.e(TAG, "clearAudioTrackOverride failed$exception")
        }
    }

    /**
     * Lists demux / embedded audio tracks (MPEG-TS multi-PID, HLS, etc.)
     * so Flutter can show Default + language rows like typical IPTV apps.
     */
    fun getAudioTracks(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        try {
            val mappedTrackInfo = trackSelector.currentMappedTrackInfo ?: return out
            val selectedFormat = try {
                exoPlayer.audioFormat
            } catch (_: Exception) {
                null
            }
            var flatIndex = 0
            for (rendererIndex in 0 until mappedTrackInfo.rendererCount) {
                if (mappedTrackInfo.getRendererType(rendererIndex) != C.TRACK_TYPE_AUDIO) continue
                val trackGroupArray = mappedTrackInfo.getTrackGroups(rendererIndex)
                for (groupIndex in 0 until trackGroupArray.length) {
                    val group = trackGroupArray[groupIndex]
                    for (trackIndex in 0 until group.length) {
                        val format = group.getFormat(trackIndex)
                        val language = format.language?.trim().orEmpty()
                        val labelRaw = format.label?.trim().orEmpty()
                        val label = when {
                            labelRaw.isNotEmpty() -> labelRaw
                            language.isNotEmpty() -> language
                            else -> "Audio ${flatIndex + 1}"
                        }
                        val selected = selectedFormat != null && (
                            selectedFormat === format ||
                                (selectedFormat.id != null && selectedFormat.id == format.id) ||
                                (selectedFormat.language != null &&
                                    selectedFormat.language == format.language &&
                                    selectedFormat.bitrate == format.bitrate &&
                                    selectedFormat.channelCount == format.channelCount)
                            )
                        out.add(
                            mapOf(
                                "id" to flatIndex,
                                "groupIndex" to groupIndex,
                                "trackIndex" to trackIndex,
                                "rendererIndex" to rendererIndex,
                                "label" to label,
                                "language" to language,
                                "selected" to selected,
                            )
                        )
                        flatIndex++
                    }
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "getAudioTracks failed$exception")
        }
        return out
    }

    private fun setAudioTrack(rendererIndex: Int, groupIndex: Int, trackIndex: Int) {
        val mappedTrackInfo = trackSelector.currentMappedTrackInfo ?: return
        val trackGroups = mappedTrackInfo.getTrackGroups(rendererIndex)
        if (groupIndex < 0 || groupIndex >= trackGroups.length) return
        val group = trackGroups.get(groupIndex)
        val safeTrackIndex = trackIndex.coerceIn(0, group.length - 1)
        val builder = trackSelector.parameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
            .addOverride(TrackSelectionOverride(group, safeTrackIndex))
        trackSelector.setParameters(builder)
    }

    private fun sendSeekToEvent(positionMs: Long) {
        exoPlayer.seekTo(positionMs)
        eventSink.success(mapOf("event" to "seek", "position" to positionMs))
    }

    fun setMixWithOthers(mixWithOthers: Boolean) {
        setAudioAttributes(exoPlayer, mixWithOthers)
    }

    fun getStreamStats(): Map<String, Any?> {
        val vf = try {
            exoPlayer.videoFormat
        } catch (_: Exception) {
            null
        }
        val af = try {
            exoPlayer.audioFormat
        } catch (_: Exception) {
            null
        }
        var width = vf?.width ?: 0
        var height = vf?.height ?: 0
        if (vf != null && (vf.rotationDegrees == 90 || vf.rotationDegrees == 270)) {
            val rotatedW = height
            height = width
            width = rotatedW
        }
        if (width == Format.NO_VALUE) width = 0
        if (height == Format.NO_VALUE) height = 0
        val bitrateCandidates = listOfNotNull(
            vf?.bitrate,
            vf?.averageBitrate,
            vf?.peakBitrate,
            af?.bitrate,
            af?.averageBitrate,
        )
        val declaredBitrate = bitrateCandidates.firstOrNull { it > 0 } ?: 0
        val estimated = try {
            DataSourceUtils.bitrateEstimate()
        } catch (_: Exception) {
            0L
        }
        sampleDecoderFps()
        val formatFps = vf?.frameRate ?: 0f
        val fps = when {
            formatFps > 1f -> formatFps
            probedFps > 1f -> probedFps
            else -> 0f
        }
        return hashMapOf(
            "width" to width,
            "height" to height,
            "videoMime" to (vf?.sampleMimeType ?: ""),
            "videoCodecs" to (vf?.codecs ?: ""),
            "audioMime" to (af?.sampleMimeType ?: ""),
            "audioCodecs" to (af?.codecs ?: ""),
            "bitrate" to if (declaredBitrate > 0) declaredBitrate else estimated.toInt(),
            "fps" to fps,
        )
    }

    private fun resetFpsProbe() {
        probedFps = 0f
        fpsDecoderRendered = 0
        fpsDecoderAtElapsed = 0L
    }

    private fun attachFpsProbe() {
        try {
            val listener = androidx.media3.exoplayer.video.VideoFrameMetadataListener { _, _, format, mediaFormat ->
                var declared = format.frameRate
                if (declared <= 1f) {
                    declared = mediaFormatFrameRate(mediaFormat)
                }
                if (declared in 1f..120f) {
                    probedFps = declared
                }
            }
            fpsFrameListener = listener
            exoPlayer.setVideoFrameMetadataListener(listener)
        } catch (_: Exception) {
        }
    }

    private fun mediaFormatFrameRate(mediaFormat: MediaFormat?): Float {
        if (mediaFormat == null || !mediaFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
            return 0f
        }
        return try {
            mediaFormat.getFloat(MediaFormat.KEY_FRAME_RATE)
        } catch (_: Exception) {
            try {
                mediaFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat()
            } catch (_: Exception) {
                0f
            }
        }
    }

    private fun sampleDecoderFps() {
        val counters = try {
            exoPlayer.videoDecoderCounters
        } catch (_: Exception) {
            null
        } ?: return
        val rendered = counters.renderedOutputBufferCount
        val now = SystemClock.elapsedRealtime()
        if (fpsDecoderAtElapsed > 0L) {
            val dtSec = (now - fpsDecoderAtElapsed) / 1000f
            val delta = rendered - fpsDecoderRendered
            if (dtSec >= 0.25f && delta >= 0) {
                val measured = delta / dtSec
                if (measured in 1f..120f) {
                    probedFps = measured
                }
            }
        }
        fpsDecoderRendered = rendered
        fpsDecoderAtElapsed = now
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        if (DEBUG) Log.i(TAG, "Player release")
        loadGeneration.incrementAndGet()
        cancelPendingRetry()
        cancelStallWatchdog()
        mainHandler.removeCallbacksAndMessages(null)
        disposeMediaSession()
        disposeRemoteNotifications()
        try {
            loudnessEnhancer?.release()
        } catch (_: Exception) {
        }
        loudnessEnhancer = null
        playerListener?.let { exoPlayer.removeListener(it) }
        playerListener = null
        fpsFrameListener?.let { listener ->
            try {
                exoPlayer.clearVideoFrameMetadataListener(listener)
            } catch (_: Exception) {
            }
        }
        fpsFrameListener = null
        try {
            exoPlayer.stop()
        } catch (_: Exception) {
        }
        eventChannel.setStreamHandler(null)
        surface?.release()
        surface = null
        exoPlayer.release()
        textureEntry.release()
        mediaExecutor.shutdownNow()
        logMem("player_release")
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || javaClass != other.javaClass) return false
        val that = other as BetterPlayer
        return exoPlayer == that.exoPlayer && surface == that.surface
    }

    override fun hashCode(): Int {
        var result = exoPlayer.hashCode()
        result = 31 * result + (surface?.hashCode() ?: 0)
        return result
    }

    companion object {
        private const val TAG = "NovaMedia3"
        /** Hot-path logging off in release; enable for adb debugging. */
        private const val DEBUG = false
        private const val FORMAT_SS = "ss"
        private const val FORMAT_DASH = "dash"
        private const val FORMAT_HLS = "hls"
        private const val FORMAT_OTHER = "other"
        private const val DEFAULT_NOTIFICATION_CHANNEL = "BETTER_PLAYER_NOTIFICATION"
        private const val NOTIFICATION_ID = 20772077

        private const val MAX_RETRIES = 5
        private const val LIVE_LOAD_ERROR_RETRIES = 8
        /** Prolonged BUFFERING without error → soft MediaSource reload. */
        private const val STALL_BUFFERING_MS = 12_000L
        /** READY but position frozen + empty buffer → soft reload. */
        private const val STALL_FROZEN_MS = 10_000L
        private const val STALL_POLL_MS = 1_000L
        private const val SOFT_RELOAD_COOLDOWN_MS = 20_000L
        private const val SOFT_RELOAD_SUCCESS_RESET_MS = 60_000L
        private const val MAX_SOFT_RELOADS = 6
        /** لا soft-reload في الثواني الأولى — jitter الإقلاع طبيعي. */
        private const val SOFT_RELOAD_STARTUP_GRACE_MS = 20_000L
        /** 4 underruns within 70s → refresh TCP (أقل حساسية من قبل). */
        private const val REBUFFER_LOOP_WINDOW_MS = 70_000L
        private const val REBUFFER_LOOP_THRESHOLD = 4

        private fun isLeanbackDevice(context: Context): Boolean {
            val ui = context.resources.configuration.uiMode
            return ui and Configuration.UI_MODE_TYPE_MASK ==
                Configuration.UI_MODE_TYPE_TELEVISION
        }

        private fun buildTrackSelector(context: Context): DefaultTrackSelector {
            val selector = DefaultTrackSelector(context)
            selector.setParameters(
                selector.buildUponParameters()
                    .setPreferredVideoMimeTypes(
                        MimeTypes.VIDEO_H263,
                        MimeTypes.VIDEO_H264,
                        MimeTypes.VIDEO_H265,
                        MimeTypes.VIDEO_VP8,
                        MimeTypes.VIDEO_VP9,
                        MimeTypes.VIDEO_AV1,
                        MimeTypes.VIDEO_MATROSKA,
                        MimeTypes.VIDEO_MP4,
                        MimeTypes.VIDEO_WEBM,
                        MimeTypes.VIDEO_MPEG,
                        MimeTypes.VIDEO_FLV,
                        MimeTypes.VIDEO_AVI,
                        MimeTypes.VIDEO_UNKNOWN,
                    )
                    .setPreferredAudioMimeTypes(
                        MimeTypes.AUDIO_AAC,
                        MimeTypes.AUDIO_AC3,
                        MimeTypes.AUDIO_E_AC3,
                        MimeTypes.AUDIO_FLAC,
                        MimeTypes.AUDIO_MPEG,
                        MimeTypes.AUDIO_OPUS,
                        MimeTypes.AUDIO_VORBIS,
                        MimeTypes.AUDIO_ALAC,
                        MimeTypes.AUDIO_WAV,
                        MimeTypes.AUDIO_DTS,
                        MimeTypes.AUDIO_DTS_HD,
                        MimeTypes.AUDIO_TRUEHD,
                    )
                    .setAllowVideoMixedMimeTypeAdaptiveness(true)
                    .setAllowMultipleAdaptiveSelections(true)
                    .setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
            )

            val captioning =
                context.getSystemService(Context.CAPTIONING_SERVICE) as? CaptioningManager
            if (captioning != null && !captioning.isEnabled) {
                selector.setParameters(
                    selector.buildUponParameters()
                        .setIgnoredTextSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                )
            }
            val locale = captioning?.locale
            if (locale != null) {
                try {
                    selector.setParameters(
                        selector.buildUponParameters()
                            .setPreferredTextLanguage(locale.isO3Language)
                    )
                } catch (_: Exception) {
                    selector.setParameters(
                        selector.buildUponParameters()
                            .setPreferredTextLanguage(locale.language)
                    )
                }
            }
            return selector
        }

        private fun safeUrl(url: String?): String {
            if (url.isNullOrEmpty()) return ""
            return try {
                val u = Uri.parse(url)
                "${u.scheme}://${u.host}${u.path?.take(48) ?: ""}"
            } catch (_: Exception) {
                url.take(64)
            }
        }

        private fun logMem(tag: String) {
            if (!DEBUG) return
            try {
                val rt = Runtime.getRuntime()
                val used = (rt.totalMemory() - rt.freeMemory()) / (1024 * 1024)
                val max = rt.maxMemory() / (1024 * 1024)
                Log.i(TAG, "Memory $tag usedMb=$used maxMb=$max")
            } catch (_: Exception) {
            }
        }

        fun clearCache(context: Context?, result: MethodChannel.Result) {
            try {
                BetterPlayerCache.releaseCache()
                context?.let {
                    val file = File(it.cacheDir, "betterPlayerCache")
                    deleteDirectory(file)
                }
                result.success(null)
            } catch (exception: Exception) {
                Log.e(TAG, exception.toString())
                result.error("", "", "")
            }
        }

        private fun deleteDirectory(file: File) {
            if (file.isDirectory) {
                file.listFiles()?.forEach { deleteDirectory(it) }
            }
            if (!file.delete()) {
                Log.e(TAG, "Failed to delete cache dir.")
            }
        }

        fun preCache(
            context: Context?, dataSource: String?, preCacheSize: Long,
            maxCacheSize: Long, maxCacheFileSize: Long, headers: Map<String, String?>,
            cacheKey: String?, result: MethodChannel.Result
        ) {
            val dataBuilder = Data.Builder()
                .putString(BetterPlayerConstants.URL_PARAMETER, dataSource)
                .putLong(BetterPlayerConstants.PRE_CACHE_SIZE_PARAMETER, preCacheSize)
                .putLong(BetterPlayerConstants.MAX_CACHE_SIZE_PARAMETER, maxCacheSize)
                .putLong(BetterPlayerConstants.MAX_CACHE_FILE_SIZE_PARAMETER, maxCacheFileSize)
            if (cacheKey != null) {
                dataBuilder.putString(BetterPlayerConstants.CACHE_KEY_PARAMETER, cacheKey)
            }
            for (headerKey in headers.keys) {
                dataBuilder.putString(
                    BetterPlayerConstants.HEADER_PARAMETER + headerKey,
                    headers[headerKey]
                )
            }
            if (dataSource != null && context != null) {
                val cacheWorkRequest =
                    OneTimeWorkRequest.Builder(CacheWorker::class.java)
                        .addTag(dataSource)
                        .setInputData(dataBuilder.build())
                        .build()
                WorkManager.getInstance(context).enqueue(cacheWorkRequest)
            }
            result.success(null)
        }

        fun stopPreCache(context: Context?, url: String?, result: MethodChannel.Result) {
            if (url != null && context != null) {
                WorkManager.getInstance(context).cancelAllWorkByTag(url)
            }
            result.success(null)
        }
    }
}
