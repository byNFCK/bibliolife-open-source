plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "app.bibliolife.reader.readium"
    compileSdk = 36

    // Continuous is the production default. The exact value "false" remains a
    // session-bound build-time rollback control for the legacy EPUB rendition.
    val continuousScrollCutover = providers.gradleProperty("bibliolifeContinuousScrollCutover")
        .map { value -> if (value.equals("true", ignoreCase = true)) "true" else "false" }
        .getOrElse("true")

    defaultConfig {
        minSdk = 23
        buildConfigField(
            "String",
            "BIBLIOLIFE_CONTINUOUS_SCROLL_CUTOVER",
            "\"$continuousScrollCutover\"",
        )
    }
    buildTypes {
        create("profile") {
            initWith(getByName("debug"))
            matchingFallbacks += listOf("debug")
        }
    }
    buildFeatures { buildConfig = true }
    testOptions {
        unitTests {
            // Bridge interaction diagnostics use android.util.Log. Host JVM tests
            // intentionally exercise those paths without an Android runtime.
            isReturnDefaultValues = true
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
}

kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }

dependencies {
    implementation("org.readium.kotlin-toolkit:readium-shared:3.2.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.2.0")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.2.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.recyclerview:recyclerview:1.4.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
