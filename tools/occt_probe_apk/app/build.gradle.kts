plugins {
    id("com.android.application")
}

android {
    namespace = "com.fieldbim.occtprobe"
    compileSdk {
        version = release(37) {
            minorApiLevel = 0
        }
    }

    defaultConfig {
        applicationId = "com.fieldbim.occtprobe"
        minSdk = 28
        targetSdk = 28
        versionCode = 1
        versionName = "0.1-probe"
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        debug {
            isDebuggable = true
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
