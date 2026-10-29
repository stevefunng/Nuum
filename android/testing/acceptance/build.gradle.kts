import java.util.zip.ZipFile

plugins {
    alias(libs.plugins.android.test)
}

android {
    namespace = "com.nuum.testing.acceptance"
    targetProjectPath = ":app"
    compileSdk = libs.versions.compileSdk.get().toInt()
    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        testInstrumentationRunnerArguments["nuum.fakeModel"] = "router"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    implementation(libs.androidx.test.ext.junit)
    implementation(libs.androidx.test.runner)
    implementation(libs.androidx.test.espresso)
    implementation(libs.androidx.test.uiautomator)
    implementation(libs.androidx.test.core)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui.test.junit4)
    implementation(libs.kotlinx.coroutines.android)
}

/**
 * Not part of `check`. Run after `:app:assembleRelease`.
 * Fails when the release APK is 30 MB or larger, ships a native library,
 * or still contains the debug model router.
 */
tasks.register("checkReleaseBudget") {
    group = "verification"
    description = "Checks the release APK size, native libraries, and absence of the debug model router."
    dependsOn(":app:assembleRelease")
    doLast {
        val apkDir = rootProject.file("app/build/outputs/apk/release")
        val apks = apkDir.listFiles()?.filter { it.isFile && it.extension == "apk" }.orEmpty()
        if (apks.isEmpty()) {
            error("No release APK in $apkDir. Run :app:assembleRelease first.")
        }
        val apk = apks.maxBy { it.length() }
        val limit = 30L * 1024 * 1024
        println("Release APK ${apk.name} is ${apk.length()} bytes (budget under $limit)")
        if (apk.length() >= limit) {
            error("${apk.name} is ${apk.length()} bytes; the budget is under $limit")
        }
        ZipFile(apk).use { zip ->
            val natives = zip.entries().asSequence()
                .map { it.name }
                .filter { it.startsWith("lib/") && it.endsWith(".so") }
                .toList()
            if (natives.isNotEmpty()) error("Native libraries in ${apk.name}: $natives")
            val forbidden = listOf("AcceptanceRouterModel", "nuum.fakeModel")
            val hits = zip.entries().asSequence()
                .filter { it.name.endsWith(".dex") }
                .flatMap { entry ->
                    val text = zip.getInputStream(entry).readBytes().toString(Charsets.ISO_8859_1)
                    forbidden.filter { text.contains(it) }.asSequence()
                }
                .toList()
            if (hits.isNotEmpty()) error("Release APK contains the debug model switch: $hits")
        }
        println("Release budget OK: ${apk.name} ${apk.length()} bytes, no lib/*.so, no debug model router")
    }
}
