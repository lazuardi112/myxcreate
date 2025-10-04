plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin harus dipanggil terakhir
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.myxcreate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion // ✅ gunakan NDK bawaan Flutter

    defaultConfig {
        applicationId = "com.example.myxcreate"

        // ✅ minSdk 23 supaya kompatibel dengan plugin modern (WorkManager, ForegroundService)
        minSdk = 23
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    compileOptions {
        // ✅ aktifkan Java 11 dengan desugaring
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    signingConfigs {
        create("release") {
            storeFile = file("my-release-key.jks")   // path ke keystore
            storePassword = "ardigg12"               // password keystore
            keyAlias = "myalias"                     // alias key
            keyPassword = "ardigg12"                 // password key
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            isMinifyEnabled = false
        }
    }

    lint {
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Desugaring untuk Java 8+ API
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ✅ Multidex agar tidak error 64K methods
    implementation("androidx.multidex:multidex:2.0.1")

    // ✅ AndroidX dasar
    implementation("androidx.core:core-ktx:1.10.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.11.0")

    // ✅ WorkManager untuk background tasks (posting notifikasi ke URL)
    implementation("androidx.work:work-runtime-ktx:2.8.1")

    // ✅ Lifecycle & coroutine (jalan bareng WorkManager/ForegroundService)
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // ✅ OkHttp untuk HTTP POST ke server
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
