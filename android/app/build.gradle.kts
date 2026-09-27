import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProperties = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keyFile.inputStream().use { keyProperties.load(it) }

android {
    namespace = "jp.nogut.ytdlp_flutter"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "jp.nogut.ytdlp_flutter"
        minSdk = 29
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            val platforms = (project.findProperty("target-platform") as? String ?: "android-arm64").split(",")
            abiFilters.addAll(platforms.mapNotNull {
                mapOf("android-arm64" to "arm64-v8a", "android-x64" to "x86_64", "android-arm" to "armeabi-v7a")[it]
            })
        }
    }
    packaging {
        jniLibs.useLegacyPackaging = true
        jniLibs.keepDebugSymbols.add("**/*.zip.so")
        val requested = (project.findProperty("target-platform") as? String ?: "android-arm64").split(",")
        val allowed = requested.mapNotNull {
            mapOf("android-arm64" to "arm64-v8a", "android-x64" to "x86_64", "android-arm" to "armeabi-v7a")[it]
        }
        listOf("x86", "x86_64", "armeabi-v7a", "arm64-v8a").filter { it !in allowed }.forEach {
            jniLibs.excludes.add("**/$it/**")
        }
    }
    signingConfigs {
        if (keyFile.exists()) create("release") {
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
            storeFile = file(keyProperties.getProperty("storeFile"))
            storePassword = keyProperties.getProperty("storePassword")
        }
    }
    buildTypes {
        release {
            signingConfig = if (keyFile.exists()) signingConfigs.getByName("release") else null
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }
dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("androidx.core:core-ktx:1.17.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
