package uz.shs.better_player_plus

import androidx.media3.common.util.UnstableApi

/**
 * Buffer targets for DefaultLoadControl.
 * Defaults match the production IPTV profile: 40s / 150s / 1s / 3s.
 */
@UnstableApi
internal class CustomDefaultLoadControl {
    @JvmField
    val minBufferMs: Int

    @JvmField
    val maxBufferMs: Int

    @JvmField
    val bufferForPlaybackMs: Int

    @JvmField
    val bufferForPlaybackAfterRebufferMs: Int

    @JvmField
    val prioritizeTimeOverSizeThresholds: Boolean

    /** Prefer software MediaCodec (and extension renderers) over broken HW decode. */
    @JvmField
    val preferSoftwareDecoder: Boolean

    constructor() {
        minBufferMs = DEFAULT_MIN_BUFFER_MS
        maxBufferMs = DEFAULT_MAX_BUFFER_MS
        bufferForPlaybackMs = DEFAULT_BUFFER_FOR_PLAYBACK_MS
        bufferForPlaybackAfterRebufferMs = DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
        prioritizeTimeOverSizeThresholds = true
        preferSoftwareDecoder = false
    }

    constructor(
        minBufferMs: Int?,
        maxBufferMs: Int?,
        bufferForPlaybackMs: Int?,
        bufferForPlaybackAfterRebufferMs: Int?,
        preferSoftwareDecoder: Boolean? = false,
    ) {
        this.minBufferMs = minBufferMs ?: DEFAULT_MIN_BUFFER_MS
        this.maxBufferMs = maxBufferMs ?: DEFAULT_MAX_BUFFER_MS
        this.bufferForPlaybackMs = bufferForPlaybackMs ?: DEFAULT_BUFFER_FOR_PLAYBACK_MS
        this.bufferForPlaybackAfterRebufferMs =
            bufferForPlaybackAfterRebufferMs ?: DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
        this.prioritizeTimeOverSizeThresholds = true
        this.preferSoftwareDecoder = preferSoftwareDecoder == true
    }

    companion object {
        const val DEFAULT_MIN_BUFFER_MS = 40_000
        const val DEFAULT_MAX_BUFFER_MS = 150_000
        const val DEFAULT_BUFFER_FOR_PLAYBACK_MS = 1_000
        const val DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = 3_000
    }
}
