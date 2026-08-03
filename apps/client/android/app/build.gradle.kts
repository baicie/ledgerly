import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseSigningPropertiesFile.isFile) {
    FileInputStream(releaseSigningPropertiesFile).use(releaseSigningProperties::load)
}

val requiredReleaseSigningProperties =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingReleaseSigningProperties =
    requiredReleaseSigningProperties.filter { releaseSigningProperties.getProperty(it).isNullOrBlank() }
val releaseTaskRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

if (releaseTaskRequested) {
    if (!releaseSigningPropertiesFile.isFile) {
        throw GradleException("Release signing requires android/key.properties")
    }
    if (missingReleaseSigningProperties.isNotEmpty()) {
        throw GradleException(
            "Release signing properties are missing: ${missingReleaseSigningProperties.joinToString()}",
        )
    }

    val releaseStoreFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
    if (!releaseStoreFile.isFile) {
        throw GradleException("Release signing keystore does not exist")
    }
}

android {
    namespace = "app.ledgerly.ledgerly_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.ledgerly.ledgerly_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningPropertiesFile.isFile && missingReleaseSigningProperties.isEmpty()) {
            create("release") {
                storeFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let { signingConfig = it }
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
