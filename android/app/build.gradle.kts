import java.util.Properties
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional release signing config. CI (or a local developer) drops a
// `android/key.properties` file pointing at a keystore; if absent, the
// release build falls back to debug signing so `flutter run --release`
// still works without a real key.
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreProperties.load(keystoreFile.inputStream())
}
val hasReleaseSigning = keystoreProperties.getProperty("storeFile") != null

// Base versionCode = <UTC+8 build date yyyyMMdd> * 100 + <git commit count>.
// CI checks out the full history; source archives fall back to a count of 0.
fun gitCommitCount(): Int {
    return try {
        val result = providers.exec {
            commandLine("git", "rev-list", "--count", "HEAD")
            workingDir = rootProject.projectDir
            isIgnoreExitValue = true
        }
        if (result.result.get().exitValue == 0) {
            result.standardOutput.asText.get().trim().toIntOrNull() ?: 0
        } else {
            0
        }
    } catch (_: Exception) {
        0
    }
}

val buildDate = ZonedDateTime.now(ZoneOffset.ofHours(8))
    .format(DateTimeFormatter.ofPattern("yyyyMMdd"))
    .toInt()
// Older split APKs used Flutter's ABI offsets of up to 4000. Start the unified
// APK sequence above that range so existing installations can update in place.
val unifiedApkVersionOffset = 5000
val resolvedVersionCode = buildDate * 100 + gitCommitCount() + unifiedApkVersionOffset

android {
    namespace = "zip.atri.sparxie"
    buildToolsVersion = "37.0.0"
    compileSdk = 37
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "zip.atri.sparxie"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = resolvedVersionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                // storeFile is interpreted relative to the rootProject
                // (`android/`) so the path matches what `key.properties`
                // — which sits there too — naturally describes.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }

        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Flutter adds ABI-specific offsets to --split-per-abi outputs through the
// legacy output API. GitHub also publishes a universal APK, so reset those
// offsets to allow switching directly distributed APKs during updates.
@Suppress("DEPRECATION")
android.applicationVariants.configureEach {
    outputs.configureEach {
        (this as com.android.build.gradle.api.ApkVariantOutput).versionCodeOverride =
            resolvedVersionCode
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core:1.16.0")
}
