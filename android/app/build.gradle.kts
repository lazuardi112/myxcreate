// android/app/build.gradle

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin harus selalu dipanggil terakhir
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.myxcreate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion // gunakan versi NDK bawaan Flutter agar kompatibel

    defaultConfig {
        applicationId = "com.example.myxcreate"
        minSdk = 23 // minimal SDK modern agar service dan notifikasi bisa berjalan
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true // mencegah 64K method error
        vectorDrawables.useSupportLibrary = true
    }

    signingConfigs {
        create("release") {
            storeFile = file("my-release-key.jks") // ganti jika lokasi file berbeda
            storePassword = "ardigg12"
            keyAlias = "myalias"
            keyPassword = "ardigg12"
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

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true // aktifkan desugaring
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    lint {
        abortOnError = false
    }

    buildFeatures {
        buildConfig = true
    }

    packagingOptions {
        resources.excludes += [
            "META-INF/LICENSE*",
            "META-INF/DEPENDENCIES",
            "META-INF/NOTICE*"
        ]
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ================================================================
    // 🔹 Android & Kotlin Dasar
    // ================================================================
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.8.22")
    implementation("androidx.core:core-ktx:1.10.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.11.0")

    // ================================================================
    // 🔹 Desugaring & Multidex
    // ================================================================
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")

    // ================================================================
    // 🔹 Lifecycle & Background
    // ================================================================
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
    implementation("androidx.work:work-runtime-ktx:2.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // ================================================================
    // 🔹 Networking & JSON
    // ================================================================
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.10.1")
}
