plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_test1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Sceneform libraries use language constructs from Java 8.
    // Add these compile options if targeting minSdkVersion < 26.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.flutter_test1"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a") // 只保留 arm6
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.." 
}

dependencies {
    implementation("com.google.ar:core:1.33.0")
    implementation("io.github.sceneview:sceneview:2.2.1")
    // Provides ArFragment, and other UX resources.
    // implementation("com.google.ar.sceneform.ux:sceneform-ux:1.8.0")

    // Alternatively, use ArSceneView without the UX dependency.
    // implementation("com.google.ar.sceneform:core:1.8.0")
}