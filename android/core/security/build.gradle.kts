plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.nuum.security"
    compileSdk = libs.versions.compileSdk.get().toInt()
    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    implementation(project(":core:contracts"))
    implementation(libs.androidx.security.crypto)
    implementation(libs.kotlinx.coroutines.android)
}
