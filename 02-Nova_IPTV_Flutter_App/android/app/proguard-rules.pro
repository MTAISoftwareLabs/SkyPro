# ProGuard / R8 — release shrink without stripping needed player & ads code.
# If a device crashes only in release, add -keep for that package and rebuild.

# --- App entry / license gate ---
-keep class com.novaiptviptv.player.MainActivity { *; }
-keep class com.novaiptviptv.player.LicenseNativeGate { *; }

# --- Flutter ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- JSON / reflection (used by many SDKs) ---
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# --- Google Mobile Ads ---
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.**

# --- WebView (policy / in-app browser) ---
-keepclassmembers class * extends android.webkit.WebViewClient {
   public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
   public boolean *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.WebChromeClient {
   public void *(android.webkit.WebView, java.lang.String);
}

# --- VLC / libVLC (flutter_vlc_player) ---
-keep class org.videolan.libvlc.** { *; }
-keep class org.videolan.** { *; }
-dontwarn org.videolan.**

# --- ExoPlayer / media (better_player_plus, ExoPlayer-based stacks) ---
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn androidx.media3.**
-dontwarn com.google.android.exoplayer2.**

# --- OkHttp / Dio (common transitive) ---
-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# --- Kotlin ---
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# --- Mobile scanner / camera (ML Kit transients) ---
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# --- Keep native method names used from JNI ---
-keepclasseswithmembernames class * {
    native <methods>;
}
