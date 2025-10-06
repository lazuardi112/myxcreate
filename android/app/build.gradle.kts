def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withInputStream { stream ->
        localProperties.load(stream)
    }
}

def flutterSdkPath = localProperties.getProperty('flutter.sdk')
if (flutterSdkPath == null) {
    throw new GradleException("Flutter SDK not found. Define location with flutter.sdk in the local.properties file.")
}

apply plugin: 'com.android.application'
apply plugin: 'kotlin-android'
apply from: "$flutterSdkPath/packages/flutter_tools/gradle/flutter.gradle"

android {
    compileSdkVersion flutter.compileSdkVersion.toInteger()

    defaultConfig {
        applicationId "com.example.myxcreate"
        minSdkVersion 23
        targetSdkVersion flutter.targetSdkVersion.toInteger()
        versionCode flutter.versionCode.toInteger()
        versionName flutter.versionName
        multiDexEnabled true
        vectorDrawables.useSupportLibrary = true
    }

    signingConfigs {
        release {
            // Jika kamu gunakan signing, isi di sini. Jika tidak, hapus block ini.
            storeFile file("my-release-key.jks")
            storePassword "ardigg12"
            keyAlias "myalias"
            keyPassword "ardigg12"
        }
    }

    buildTypes {
        release {
            // Aktifkan ProGuard jika perlu
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
            signingConfig signingConfigs.release // uncomment jika kamu mengisi signingConfigs
        }
        debug {
            minifyEnabled false
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
        coreLibraryDesugaringEnabled true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    lintOptions {
        abortOnError false
    }
}

flutter {
    source "../.."
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlin_version"

    // Desugaring (Java 8+ API)
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'

    // Multidex
    implementation 'androidx.multidex:multidex:2.0.1'

    // AndroidX
    implementation 'androidx.core:core-ktx:1.10.1'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'com.google.android.material:material:1.11.0'

    // WorkManager (jika nanti dipakai)
    implementation 'androidx.work:work-runtime-ktx:2.8.1'

    // Lifecycle & Coroutines
    implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.6.2'
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3'

    // Network
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'

    // JSON parsing for native (Gson)
    implementation 'com.google.code.gson:gson:2.10.1'
}
