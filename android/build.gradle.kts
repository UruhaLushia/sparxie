allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val projectNdkVersion = "29.0.14206865"
val projectCmakeVersion = "3.22.1"
val projectBuildToolsVersion = "37.0.0"
val projectCompileSdk = 37

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
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.apply {
            buildToolsVersion = projectBuildToolsVersion
            compileSdk = projectCompileSdk
            ndkVersion = projectNdkVersion
            externalNativeBuild.cmake.version = projectCmakeVersion
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
