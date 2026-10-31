import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing comes from android/key.properties (gitignored; see
// android/key.properties.example). A release build without it fails instead of
// silently falling back to the debug key.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.ataei.zanjir"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ataei.zanjir"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        defaultConfig {
            addManifestPlaceholders(
                mapOf("TapsellMediationAppKey" to "mfhmdqriqiegbngfoadealqktsqnsbrgastsbgghalftsqihbqsakbqgdjpnarnecchtpr")
            )
        }
    }

    signingConfigs {
        create("release") {
            if (keyProps.isNotEmpty()) {
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// Fail fast (before any compilation) when a release artifact is requested
// without a signing key.
gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release", ignoreCase = true) && it.project == project }
    if (wantsRelease && keyProps.isEmpty()) {
        throw GradleException("android/key.properties is missing — release builds must be signed with the Zanjir release key.")
    }
}
