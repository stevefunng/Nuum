plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.nuum"
    compileSdk = libs.versions.compileSdk.get().toInt()
    defaultConfig {
        applicationId = "com.nuum"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    buildFeatures {
        compose = true
    }
    buildTypes {
        release {
            // Architecture §11: R8 is what keeps the release APK under 30 MB.
            // The unminified dex was about 31 MB. Consumer rules from Room,
            // DataStore, and kotlinx.serialization stay in effect.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
    sourceSets.named("test") {
        kotlin.directories.add("../testing/acceptance/src/host/kotlin")
    }
}

dependencies {
    implementation(project(":feature:shell"))
    implementation(project(":feature:conversation"))
    implementation(project(":feature:work"))
    implementation(project(":feature:settings"))
    implementation(project(":core:security"))
    implementation(project(":core:storage"))
    implementation(project(":core:model"))
    implementation(project(":core:kernel"))
    implementation(project(":core:agent"))
    implementation(project(":core:tools"))
    implementation(project(":core:contracts"))
    implementation(project(":core:protocol"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
}
