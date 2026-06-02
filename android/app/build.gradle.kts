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

// versionCode = <UTC+8 build date yyyyMMdd> * 100 + <git commit count>, e.g.
// 2026052912. Monotonic (date and commit count only ever increase) and well
// under the 2_147_483_647 int ceiling until year ~2147. Needs full git
// history (CI checks out with fetch-depth: 0); commit count falls back to 0
// when git is unavailable (e.g. a source tarball).
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
val resolvedVersionCode = buildDate * 100 + gitCommitCount()

android {
    namespace = "zip.atri.sparxie"
    compileSdk = 36
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "zip.atri.sparxie"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = resolvedVersionCode
        versionName = flutter.versionName
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
        }
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
