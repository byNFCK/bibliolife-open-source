import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningPropertiesFile.isFile) {
        releaseSigningPropertiesFile.inputStream().use(::load)
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseSigningValuesPresent = releaseSigningKeys.map { releaseSigningProperties.getProperty(it).orEmpty().isNotBlank() }
val hasAnyReleaseSigningValue = releaseSigningValuesPresent.any { it }
val hasCompleteReleaseSigning = releaseSigningValuesPresent.all { it }

if (hasAnyReleaseSigningValue && !hasCompleteReleaseSigning) {
    throw GradleException(
        "android/key.properties is incomplete. Set storeFile, storePassword, " +
            "keyAlias and keyPassword, or remove the file to build an unsigned release.",
    )
}


android {
    namespace = "app.bibliolife.reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.bibliolife.reader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasCompleteReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("profile") {
            // The local Readium composite build exposes debug/release variants.
            // Profile must use its debug variant so Flutter profile-mode runs can
            // measure the Dart/UI pipeline on device.
            matchingFallbacks += listOf("debug")
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // Never sign a release with the development debug key.
            // Without android/key.properties, Gradle produces an unsigned release.
            signingConfig = if (hasCompleteReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    implementation("androidx.core:core-ktx:1.15.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
