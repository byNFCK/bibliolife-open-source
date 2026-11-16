pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// An included build has its own Gradle root, so it can't read this project's
// android/local.properties. Generate its ignored SDK configuration from the
// host project's portable configuration before Gradle configures Readium.
val hostLocalProperties = java.util.Properties().apply {
    val hostLocalPropertiesFile = file("local.properties")
    if (hostLocalPropertiesFile.isFile) {
        hostLocalPropertiesFile.inputStream().use(::load)
    }
}
val androidSdkPath = hostLocalProperties.getProperty("sdk.dir")
    ?: System.getenv("ANDROID_SDK_ROOT")
    ?: System.getenv("ANDROID_HOME")
    ?: throw GradleException(
        "Android SDK location not found. Checked sdk.dir in android/local.properties, " +
            "ANDROID_SDK_ROOT, and ANDROID_HOME."
    )
val readiumLocalPropertiesFile = file("../third_party/readium-kotlin-toolkit/local.properties")
val readiumLocalProperties = java.util.Properties().apply {
    if (readiumLocalPropertiesFile.isFile) {
        readiumLocalPropertiesFile.inputStream().use(::load)
    }
}
if (readiumLocalProperties.getProperty("sdk.dir") != androidSdkPath) {
    readiumLocalProperties.setProperty("sdk.dir", androidSdkPath)
    readiumLocalPropertiesFile.parentFile.mkdirs()
    readiumLocalPropertiesFile.outputStream().use {
        readiumLocalProperties.store(it, "Generated from BiblioLife android/local.properties or SDK environment")
    }
}

// Readium is patched locally for the Android WebView CSS-columns selection bug.
// The checkout is pinned to upstream tag 3.2.0 (commit fe4c32b97f4745971facfbdfbde31520553c770e).
includeBuild("../third_party/readium-kotlin-toolkit") {
    dependencySubstitution {
        substitute(module("org.readium.kotlin-toolkit:readium-shared"))
            .using(project(":readium:readium-shared"))
        substitute(module("org.readium.kotlin-toolkit:readium-streamer"))
            .using(project(":readium:readium-streamer"))
        substitute(module("org.readium.kotlin-toolkit:readium-navigator"))
            .using(project(":readium:readium-navigator"))
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
