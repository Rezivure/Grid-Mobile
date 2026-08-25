import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.reader(Charsets.UTF_8).use { load(it) }
    }
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.reader(Charsets.UTF_8).use { load(it) }
    }
}

val flutterVersionCode: Int =
    localProperties.getProperty("flutter.versionCode")?.toIntOrNull() ?: 1

val flutterVersionName: String =
    localProperties.getProperty("flutter.versionName") ?: "1.0"

kotlin {
    compilerOptions {
        languageVersion = org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0
        // Optional: Set jvmTarget
        // jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

// configurations.configureEach {
//     exclude(group = "com.google.crypto.tink", module = "tink")
// }

android {
    namespace = "app.mygrid.grid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // For AGP 4.1+
        isCoreLibraryDesugaringEnabled = true
        // For AGP 4.0
        // coreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    defaultConfig {
        applicationId = "app.mygrid.grid"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode
        versionName = flutterVersionName

        manifestPlaceholders["applicationName"] = "android.app.Application"

        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
        }
    }


    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias") as String?
            keyPassword = keystoreProperties.getProperty("keyPassword") as String?
            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword") as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

configurations.configureEach {
    val tinkAndroid = "com.google.crypto.tink:tink-android:1.9.0"
    resolutionStrategy {
        force(tinkAndroid)
        dependencySubstitution {
            substitute(module("com.google.crypto.tink:tink"))
                .using(module(tinkAndroid))
        }
    }
}

// TODO(Yuki): when firebase services are used for Flutter and not required in Android, this should be removed and generated with the 'flutterfire' tool
dependencies {
    // Desugaring-Bibliothek für neuere Java-Features
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase BoM & Services
    implementation(platform("com.google.firebase:firebase-bom:33.9.0"))
    implementation("com.google.firebase:firebase-messaging")
}
