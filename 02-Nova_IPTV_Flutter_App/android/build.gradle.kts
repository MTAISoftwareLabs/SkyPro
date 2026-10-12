allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (!name.contains("flutter_vlc_player")) return@subprojects
    val patched = rootProject.projectDir.resolve("vlc_overlay/FlutterVlcPlayer.java")
    tasks.matching { it.name == "preBuild" }.configureEach {
        doFirst {
            if (!patched.exists()) return@doFirst
            val dest = projectDir.resolve(
                "src/main/java/software/solid/fluttervlcplayer/FlutterVlcPlayer.java"
            )
            if (dest.exists()) {
                patched.copyTo(dest, overwrite = true)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
