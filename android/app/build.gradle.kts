plugins {
    id("com.android.application")
}

android {
    namespace = "com.leongong.ghodex.androidapp"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.leongong.ghodex.androidapp"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets.getByName("main") {
        java.srcDirs("src/main/java", "..")
        java.exclude("app/**")
    }
}

dependencies {
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
}
