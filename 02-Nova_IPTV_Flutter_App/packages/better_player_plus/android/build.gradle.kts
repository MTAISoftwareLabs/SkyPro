plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "uz.shs.better_player_plus"
version = "1.3.4"

val lifecycleVersion = "2.9.4"
val annotationVersion = "1.9.1"
val media3Version = "1.9.1"
val workVersion = "2.10.5"

// إصدارات AGP/Kotlin تُعرَّف في settings.gradle.kts (لا تثبّتها هنا)
// حتى تبقى متوافقة مع التطبيق المضيف ومزامنة IDE.

android {
    namespace = "uz.shs.better_player_plus"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    sourceSets["main"].java.srcDirs("src/main/kotlin")
}

dependencies {
    implementation("androidx.media:media:1.7.1")

    // Core ExoPlayer + UI from local AARs; Maven supplies format modules only.
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-datasource:$media3Version")
    implementation("androidx.media3:media3-decoder:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")
    implementation("androidx.media3:media3-container:$media3Version")
    implementation("androidx.media3:media3-extractor:$media3Version")

    implementation("androidx.media3:media3-exoplayer-dash:$media3Version") {
        exclude(group = "androidx.media3", module = "media3-exoplayer")
    }
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version") {
        exclude(group = "androidx.media3", module = "media3-exoplayer")
    }
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:$media3Version") {
        exclude(group = "androidx.media3", module = "media3-exoplayer")
    }
    implementation("androidx.media3:media3-exoplayer-rtsp:$media3Version") {
        exclude(group = "androidx.media3", module = "media3-exoplayer")
    }

    // compileOnly: AGP forbids packaging local AARs into a library AAR.
    // The host app must implementation() the same libs/ AARs.
    compileOnly(fileTree(mapOf("dir" to "libs", "include" to listOf("lib-*.aar"))))

    implementation("androidx.lifecycle:lifecycle-runtime-ktx:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common-java8:$lifecycleVersion")

    implementation("androidx.annotation:annotation:$annotationVersion")
    implementation("androidx.work:work-runtime:$workVersion")

    //noinspection GradleDependency
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.2.20")
}
