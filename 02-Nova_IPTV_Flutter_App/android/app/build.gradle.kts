// حجم APK: flutter build apk الافتراضي يبني android-x64 فيدخل lib/x86_64 (عشرات الميجا).
// للبناء الأصغر بدون split-per-abi:
//   flutter build apk --release --target-platform android-arm,android-arm64
// اختياري (تصغير Dart): --obfuscate --split-debug-info=build/app/debug-info
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.skypro.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.skypro.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // Universal Build supporting both 32-bit (armeabi-v7a) and 64-bit (arm64-v8a)
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    signingConfigs {
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
        }
        create("release") {
            enableV1Signing = true
            enableV2Signing = true
            val hasReleaseKeystore =
                keystoreProperties["storeFile"] != null &&
                keystoreProperties["storePassword"] != null &&
                keystoreProperties["keyAlias"] != null &&
                keystoreProperties["keyPassword"] != null
            if (hasReleaseKeystore) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // R8 يصغّر كود Java/Kotlin والموارد غير المستخدمة (توفير كبير في الحجم).
            // قواعد الحفظ في proguard-rules.pro تقلّل تعارض المشغّل والإعلانات والويب.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback for local release testing only. For Play Store, provide key.properties.
                signingConfigs.getByName("debug")
            }
        }
    }

    // إن بُني المشروع بدون --target-platform يمرّ أحياناً x86/x86_64؛ نمنعها من داخل الـ APK.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            excludes += "**/lib/x86/**"
            excludes += "**/lib/x86_64/**"
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

flutter {
    source = "../.."
}

// Local Exo AARs (better_player_plus/libs) replace Maven media3-exoplayer/ui.
// video_player / pod_player also pull media3-exoplayer → duplicate class errors.
configurations.configureEach {
    exclude(group = "androidx.media3", module = "media3-exoplayer")
    exclude(group = "androidx.media3", module = "media3-ui")
}

dependencies {
    implementation("com.google.android.play:app-update:2.1.0")
    // Package Media3 Exo/UI + decoder AARs (better_player_plus uses them as compileOnly).
    implementation(
        fileTree(
            mapOf(
                "dir" to "${rootProject.projectDir}/../packages/better_player_plus/android/libs",
                "include" to listOf("lib-*.aar"),
            ),
        ),
    )
}
