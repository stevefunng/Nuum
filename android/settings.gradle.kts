pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "nuum-android"

include(
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
    ":feature:settings",
    ":testing:acceptance"
)
