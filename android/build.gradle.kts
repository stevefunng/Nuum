import java.io.File

// AGP 9 bundles an older Kotlin Gradle plugin. This classpath lifts built-in Kotlin
// and KSP. Do not apply the legacy Android Kotlin plugin; AGP 9 rejects it.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21")
        classpath("com.google.devtools.ksp:symbol-processing-gradle-plugin:2.3.12")
    }
}

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.android.test) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
}

/**
 * Direct project edges allowed by ANDROID_ARCHITECTURE.md §3.1.
 * Absence is a failure: a new module must be added here in the same change.
 */
val allowedProjectEdges: Map<String, Set<String>> = mapOf(
    ":app" to setOf(
        ":feature:shell",
        ":feature:conversation",
        ":feature:work",
        ":feature:settings",
        ":core:security",
        ":core:storage",
        ":core:model",
        ":core:kernel",
        ":core:agent",
        ":core:tools",
        ":core:contracts",
        ":core:protocol"
    ),
    ":testing:acceptance" to setOf(":app"),
    ":feature:shell" to setOf(":core:contracts", ":core:protocol"),
    ":feature:conversation" to setOf(":core:contracts", ":core:protocol"),
    ":feature:work" to setOf(":core:contracts", ":core:protocol"),
    ":feature:settings" to setOf(":core:contracts", ":core:protocol"),
    ":core:agent" to setOf(":core:contracts", ":core:protocol"),
    ":core:kernel" to setOf(":core:contracts", ":core:protocol"),
    ":core:model" to setOf(":core:contracts", ":core:protocol"),
    ":core:tools" to setOf(":core:contracts", ":core:protocol"),
    ":core:storage" to setOf(":core:contracts", ":core:protocol"),
    ":core:security" to setOf(":core:contracts"),
    ":core:protocol" to emptySet(),
    ":core:contracts" to setOf(":core:protocol")
)

fun forbiddenImportPrefixes(projectPath: String): List<String> {
    val featureImpl = listOf(
        "com.nuum.kernel.",
        "com.nuum.agent.",
        "com.nuum.model.",
        "com.nuum.storage."
    )
    return when {
        projectPath == ":core:protocol" -> listOf(
            "android.",
            "androidx.",
            "okhttp3.",
            "retrofit2."
        )
        projectPath == ":core:contracts" -> listOf(
            "android.",
            "androidx.",
            "okhttp3.",
            "retrofit2."
        )
        projectPath == ":core:kernel" -> featureImpl + listOf(
            "com.nuum.feature.",
            "com.nuum.security.",
            "com.nuum.tools.",
            "okhttp3.",
            "retrofit2.",
            "java.net.http."
        )
        projectPath == ":core:agent" -> listOf(
            "com.nuum.kernel.",
            "com.nuum.model.",
            "okhttp3.",
            "retrofit2.",
            "java.net.http.",
            "javax.net.ssl."
        )
        projectPath.startsWith(":feature:") -> featureImpl
        else -> emptyList()
    }
}

fun importViolations(projectPath: String, source: String): List<String> {
    val banned = forbiddenImportPrefixes(projectPath)
    if (banned.isEmpty()) return emptyList()
    return source.lineSequence().mapIndexedNotNull { index, line ->
        val trimmed = line.trim()
        if (!trimmed.startsWith("import ")) return@mapIndexedNotNull null
        val imported = trimmed.removePrefix("import ").removeSuffix(";").substringBefore(" ").trim()
        val hit = banned.firstOrNull { imported == it.removeSuffix(".") || imported.startsWith(it) }
        hit?.let { "${projectPath}:${index + 1} imports $imported ($it)" }
    }.toList()
}

fun edgeAllowed(from: String, to: String): Boolean = allowedProjectEdges[from]?.contains(to) == true

fun appliesLegacyKotlinAndroidPlugin(text: String): Boolean {
    val applied = Regex("""id\(\s*["']org\.jetbrains\.kotlin\.android["']\s*\)""")
    val kotlinDsl = Regex("""kotlin\(\s*["']android["']\s*\)""")
    return applied.containsMatchIn(text) || kotlinDsl.containsMatchIn(text)
}

fun declaredProjectEdges(buildFile: File): Set<String> {
    val text = buildFile.readText()
    val edges = Regex("""project\("(:[^"]+)"\)""").findAll(text).map { it.groupValues[1] }.toMutableSet()
    Regex("""targetProjectPath\s*=\s*"(:[^"]+)"""").findAll(text).forEach { edges += it.groupValues[1] }
    return edges
}

val checkDependencyDirection = tasks.register("checkDependencyDirection") {
    group = "verification"
    description = "Fails when a module dependency violates ANDROID_ARCHITECTURE.md section 3.1."
    val rootDir = layout.projectDirectory.asFile
    inputs.file("gradle/libs.versions.toml")
    inputs.file("build.gradle.kts")
    inputs.file("settings.gradle.kts")
    inputs.file("gradle/wrapper/gradle-wrapper.properties")
    subprojects.filter { it.path in allowedProjectEdges }.forEach { sub ->
        inputs.file(sub.buildFile)
        val sources = sub.file("src/main")
        if (sources.exists()) inputs.dir(sources)
    }
    doLast {
        val violations = mutableListOf<String>()
        val selfCheckEdges = listOf(
            ":feature:shell" to ":core:kernel",
            ":feature:conversation" to ":core:agent",
            ":feature:work" to ":core:model",
            ":feature:settings" to ":core:storage",
            ":core:kernel" to ":core:agent",
            ":core:agent" to ":core:model",
            ":core:security" to ":core:protocol",
            ":core:protocol" to ":core:contracts",
            ":testing:acceptance" to ":core:kernel",
            ":app" to ":testing:acceptance"
        )
        selfCheckEdges.forEach { (from, to) ->
            if (edgeAllowed(from, to)) violations += "rule self-check failed to reject $from -> $to"
        }
        listOf(
            ":app" to ":core:kernel",
            ":core:security" to ":core:contracts",
            ":core:contracts" to ":core:protocol",
            ":feature:shell" to ":core:protocol",
            ":testing:acceptance" to ":app"
        ).forEach { (from, to) ->
            if (!edgeAllowed(from, to)) violations += "rule self-check rejected a legal edge $from -> $to"
        }
        if (importViolations(":core:protocol", "import android.util.Log").isEmpty()) {
            violations += "rule self-check allowed android import in :core:protocol"
        }
        if (importViolations(":core:contracts", "import android.view.View").isEmpty()) {
            violations += "rule self-check allowed Android UI import in :core:contracts"
        }
        if (importViolations(":core:agent", "import okhttp3.OkHttpClient").isEmpty()) {
            violations += "rule self-check allowed OkHttp in :core:agent"
        }
        if (importViolations(":core:kernel", "import okhttp3.Request").isEmpty()) {
            violations += "rule self-check allowed OkHttp in :core:kernel"
        }
        if (importViolations(":feature:shell", "import com.nuum.kernel.Kernel").isEmpty()) {
            violations += "rule self-check allowed feature -> kernel import"
        }
        if (importViolations(":feature:shell", "import com.nuum.contracts.AgentPort").isNotEmpty()) {
            violations += "rule self-check rejected a contract import from a feature"
        }

        val included = Regex("""include\(([^)]*)\)""", RegexOption.DOT_MATCHES_ALL)
            .find(rootDir.resolve("settings.gradle.kts").readText())
            ?.groupValues
            ?.get(1)
            ?.let { body -> Regex(""""(:[^"]+)"""").findAll(body).map { it.groupValues[1] }.toSet() }
            ?: emptySet()
        if (included != allowedProjectEdges.keys) {
            violations += "settings includes $included but the allow-map is ${allowedProjectEdges.keys}"
        }

        val rootBuild = rootDir.resolve("build.gradle.kts").readText()
        if (appliesLegacyKotlinAndroidPlugin(rootBuild)) {
            violations += "root build applies the legacy Android Kotlin plugin"
        }
        val toml = rootDir.resolve("gradle/libs.versions.toml").readText()
        fun catalogVersion(key: String): String {
            val match = Regex("""(?m)^$key\s*=\s*"([^"]+)"""").find(toml)
                ?: error("libs.versions.toml is missing $key")
            return match.groupValues[1]
        }
        val kotlinVersion = catalogVersion("kotlin")
        val kspVersion = catalogVersion("ksp")
        val gradleVersion = catalogVersion("gradle")
        if (!rootBuild.contains("kotlin-gradle-plugin:$kotlinVersion")) {
            violations += "root buildscript must classpath kotlin-gradle-plugin:$kotlinVersion"
        }
        if (!rootBuild.contains("symbol-processing-gradle-plugin:$kspVersion")) {
            violations += "root buildscript must classpath symbol-processing-gradle-plugin:$kspVersion"
        }
        if (appliesLegacyKotlinAndroidPlugin(toml)) {
            violations += "version catalog must not declare the legacy Android Kotlin plugin"
        }
        val wrapper = rootDir.resolve("gradle/wrapper/gradle-wrapper.properties").readText()
        if (!wrapper.contains("gradle-$gradleVersion-")) {
            violations += "Gradle wrapper must be $gradleVersion"
        }

        subprojects.filter { it.path in allowedProjectEdges }.sortedBy { it.path }.forEach { sub ->
            val text = sub.buildFile.readText()
            if (appliesLegacyKotlinAndroidPlugin(text)) {
                violations += "${sub.path} applies the legacy Android Kotlin plugin"
            }
            if (text.contains("projects.")) {
                violations += "${sub.path} must declare project dependencies as project(\":path\")"
            }
            if (sub.path == ":core:protocol" &&
                (text.contains("com.android.library") || text.contains("com.android.application"))
            ) {
                violations += ":core:protocol must stay a pure JVM module"
            }
            val allowed = allowedProjectEdges[sub.path] ?: emptySet()
            declaredProjectEdges(sub.buildFile).forEach { target ->
                if (target !in allowed) violations += "${sub.path} depends on $target"
            }
            val sources = sub.file("src/main")
            if (sources.exists()) {
                sources.walkTopDown()
                    .filter { it.isFile && (it.extension == "kt" || it.extension == "java") }
                    .forEach { file ->
                        importViolations(sub.path, file.readText()).forEach { hit ->
                            violations += "${file.relativeTo(rootDir)} $hit"
                        }
                    }
            }
        }

        if (violations.isNotEmpty()) {
            throw GradleException(
                "Dependency direction check failed:\n" + violations.joinToString("\n") { "- $it" }
            )
        }
    }
}

val testAll = tasks.register("test") {
    group = "verification"
    description = "Runs every module test task and the dependency-direction check."
    dependsOn(checkDependencyDirection)
}

val unitTestProjects = listOf(
    ":app",
    ":core:contracts",
    ":core:protocol",
    ":core:security",
    ":core:storage",
    ":core:model",
    ":core:kernel",
    ":core:agent",
    ":core:tools",
    ":feature:shell",
    ":feature:conversation",
    ":feature:work",
    ":feature:settings"
)

testAll.configure {
    dependsOn(unitTestProjects.map { "$it:test" })
}
