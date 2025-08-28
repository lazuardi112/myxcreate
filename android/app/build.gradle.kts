plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin harus setelah Android dan Kotlin plugin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.myxcreate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.myxcreate"

        // ✅ fix minSdk agar cocok google_mobile_ads
        minSdk = 23
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            storeFile = file("my-release-key.jks")   // path ke keystore
            storePassword = "ardigg12"               // password keystore
            keyAlias = "myalias"                     // alias
            keyPassword = "ardigg12"                 // password alias
        }
        // ❌ jangan buat debug di sini, sudah otomatis dari Flutter
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
            // otomatis pakai debug keystore bawaan
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
