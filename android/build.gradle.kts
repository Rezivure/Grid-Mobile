buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://developer.huawei.com/repo/") }
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}


// Keep plugin modules in sync with the app's ndkVersion. Without this,
// plugins that don't declare ndkVersion (e.g. webcrypto) fall back to
// AGP's default and clash with local.properties' ndk.dir, failing the
// release bundle with CXX1104. Registered in its own block so the hook
// is attached to every subproject before the evaluationDependsOn below
// forces :app to evaluate.

subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.application") || plugins.hasPlugin("com.android.library")) {
            extensions.findByName("android")?.let { androidExt ->
                val setNdkVersion = androidExt.javaClass.getMethod("setNdkVersion", String::class.java)
                setNdkVersion.invoke(androidExt, "28.0.12433566")
            }
        }
    }
}


// Custom build output redirect for Flutter (standard in modern templates)
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
