plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.nuum.tools"
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
    implementation(libs.androidx.documentfile)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
}
