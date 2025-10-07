// android/app/build.gradle.kts
plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin harus tetap dipanggil terakhir
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.myxcreate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.myxcreate"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
        vectorDrawables.useSupportLibrary = true
    }

    signingConfigs {
        create("release") {
            // isi jika ingin signing release. Jika belum, biarkan/default.
            storeFile = file("my-release-key.jks")
            storePassword = "ardigg12"
            keyAlias = "myalias"
            keyPassword = "ardigg12"
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                file("proguard-rules.pro")
            )
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // aktifkan desugaring untuk Java8+ APIs
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    lint {
        isAbortOnError = false
    }

    // Packaging options: gunakan metode Kotlin DSL yang benar (addAll setOf)
    packaging {
        resources {
            // tambahkan excludes dengan benar (tidak menggunakan [ ... ] Groovy literal)
            excludes.addAll(
                setOf(
                    "META-INF/LICENSE*",
                    "META-INF/DEPENDENCIES",
                    "META-INF/NOTICE*",
                    "META-INF/NOTICE",
                    "META-INF/LICENSE"
                )
            )
        }
    }

    buildFeatures {
        buildConfig = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Kotlin stdlib
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.8.22")

    // Desugaring (Java 8+)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Multidex
    implementation("androidx.multidex:multidex:2.0.1")

    // AndroidX & Material
    implementation("androidx.core:core-ktx:1.10.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.11.0")

    // WorkManager, Lifecycle, Coroutines
    implementation("androidx.work:work-runtime-ktx:2.8.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Network & JSON
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.10.1")
}
