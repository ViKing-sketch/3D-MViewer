plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fieldbim.field_bim_viewer"
    // Filament 1.77.3 requires API 37. A plain `compileSdk = 37` looks for the
    // hash `android-37`, but the SDK package is `platforms/android-37.0`.
    compileSdk {
        version = release(37) {
            minorApiLevel = 0
        }
    }
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // CameraX uses java.time. minSdk is below 34, so desugar it.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fieldbim.field_bim_viewer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(24, flutter.minSdkVersion)
        // Floor is 34, the level the phone probe passed Play Protect with.
        // Flutter 3.44's default is 36. The existing GLB unmap reflection is
        // suppressed on that function so a release build can keep it.
        targetSdk = 34
        ndk {
            // Emulators used for field checks are x86_64; devices are arm64-v8a.
            // `flutter build apk --split-per-abi` sets ABI splits and rejects
            // this list ("cannot be present when splits abi filters are set").
            // The tool passes -Psplit-per-abi=true and chooses the ABIs itself.
            val splitPerAbi = rootProject.findProperty("split-per-abi")?.toString() == "true"
            if (!splitPerAbi) {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug key. No keystore and no password in the tree. The CI APK
            // is an Actions artifact, not a published release.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Extract to nativeLibraryDir so System.loadLibrary finds OCCT next
            // to libocct_probe_jni.so. Do not copy that binary into filesDir.
            useLegacyPackaging = true
            // Flutter and Filament both ship this STL. One copy is enough.
            pickFirsts += listOf("**/libc++_shared.so")
            // Filament and sqlite AARs also ship 32-bit libs. The app is arm64 and x86_64 only.
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**")
        }
    }
}

dependencies {
    val filament = "1.77.3"
    implementation("com.google.android.filament:filament-android:$filament")
    implementation("com.google.android.filament:filament-utils-android:$filament")
    implementation("com.google.android.filament:gltfio-android:$filament")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.camera:camera-core:1.4.2")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    implementation("com.google.zxing:core:3.5.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
