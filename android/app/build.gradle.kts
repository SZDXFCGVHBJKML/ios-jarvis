plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val verName = System.getenv("JARVIS_VERSION") ?: "1.0.0"
val verCode = (System.getenv("JARVIS_VERCODE") ?: "1").toInt()
val ciKeystore = System.getenv("CI_KEYSTORE")

android {
    namespace = "com.boris.jarvis"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.boris.jarvis"
        minSdk = 26
        targetSdk = 34
        versionCode = verCode
        versionName = verName
    }

    signingConfigs {
        create("ci") {
            if (ciKeystore != null) {
                storeFile = file(ciKeystore)
                storePassword = "jarvis123"
                keyAlias = "jarvis"
                keyPassword = "jarvis123"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (ciKeystore != null) signingConfig = signingConfigs.getByName("ci")
        }
    }

    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    val bom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(bom)
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
