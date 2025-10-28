allprojects {
    repositories {
        google()
        mavenCentral()
        
    }

    configurations.all {
        // 1. 强制版本
        resolutionStrategy {
            force("com.google.android.filament:filament-android:1.52.0")
            force("com.google.android.filament:filament-utils-android:1.52.0")
        }
        // 2. 排除旧模块
        exclude(group = "com.google.ar.sceneform", module = "core")
        exclude(group = "com.google.ar.sceneform", module = "rendering")
        exclude(group = "com.google.ar.sceneform", module = "sceneform-base")
        exclude(group = "com.google.ar.sceneform", module = "filament-android")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
