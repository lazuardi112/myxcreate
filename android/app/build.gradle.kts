// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter Gradle Plugin wajib dipanggil terakhir
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.myxcreate"
    // nilai compileSdk / targetSdk / version diisi lewat extension flutter dari plugin
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.myxcreate"

        // Minimal SDK modern untuk service & background tasks
        minSdk = 23
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Multidex
        multiDexEnabled = true
    }

    compileOptions {
        // Aktifkan dukungan Java 11 dan desugaring
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    signingConfigs {
        // Buat signing config release (sesuaikan atau hapus jika tidak menggunakan signing lokal)
        create("release") {
            // Jika belum ada keystore, ganti atau komentar baris di bawah
            storeFile = file("my-release-key.jks")
            storePassword = "ardigg12"
            keyAlias = "myalias"
            keyPassword = "ardigg12"
        }
    }

    buildTypes {
        getByName("release") {
            // jika tidak ingin menandatangani saat build lokal, comment out baris signingConfig
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

    // Lint configuration (Kotlin DSL)
    lint {
        abortOnError = false
        checkReleaseBuilds = false
        // menonaktifkan rule tertentu jika perlu
        disable += "InvalidPackage"
    }

    // Packaging options (hindari duplikat file)
    packaging {
        resources {
            excludes += listOf(
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/DEPENDENCIES",
                "META-INF/INDEX.LIST"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Desugaring agar bisa pakai API Java 8+ di Android lama
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Multidex
    implementation("androidx.multidex:multidex:2.0.1")

    // AndroidX dasar
    implementation("androidx.core:core-ktx:1.10.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.11.0")

    // WorkManager (opsional, untuk job scheduling)
    implementation("androidx.work:work-runtime-ktx:2.8.1")

    // Lifecycle & Coroutine
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // HTTP client (OkHttp)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // JSON parser (Gson) — dipakai di native Kotlin/Java
    implementation("com.google.code.gson:gson:2.10.1")
}
