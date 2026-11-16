plugins {
    // Keep the Kotlin Gradle Plugin available to this root script so the
    // file_picker AGP 9 compatibility workaround can configure KotlinCompile.
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker 11.0.3 has an AGP 9 edge case when android.builtInKotlin=false:
// its frozen v11 Android module skips applying the Kotlin Gradle Plugin.
// Apply KGP after the Android library plugin is present and keep JVM target 17.
// Upstream issue: https://github.com/vicajilau/flutter_file_picker/issues/2200
subprojects {
    if (name == "file_picker") {
        plugins.withId("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
            tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
