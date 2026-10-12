package uz.shs.better_player_plus

/**
 * Shared WorkManager / MethodChannel keys.
 * Kept outside [BetterPlayerPlugin] to avoid circular compile references
 * between BetterPlayer ↔ Plugin ↔ Workers in release builds.
 */
internal object BetterPlayerConstants {
    const val URL_PARAMETER = "url"
    const val PRE_CACHE_SIZE_PARAMETER = "preCacheSize"
    const val MAX_CACHE_SIZE_PARAMETER = "maxCacheSize"
    const val MAX_CACHE_FILE_SIZE_PARAMETER = "maxCacheFileSize"
    const val HEADER_PARAMETER = "header_"
    const val FILE_PATH_PARAMETER = "filePath"
    const val CACHE_KEY_PARAMETER = "cacheKey"
}
