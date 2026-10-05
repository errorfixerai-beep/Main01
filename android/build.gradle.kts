allprojects {
    repositories {
        google()
        mavenCentral()
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

// ⚠️ NEW: purane plugins (jaise native_device_orientation, jo apivideo_live_stream ke saath aata hai)
// android-31 par compile hote hain, jabki naye androidx libraries ko SDK 34+ chahiye.
// Isliye har plugin (app ko chhodkar) ko SDK 36 par compile karwa rahe hain.
// IMPORTANT: ye block neeche wale evaluationDependsOn block se PEHLE hona chahiye.
subprojects {
    afterEvaluate {
        if (project.name != "app") {
            val androidExt = extensions.findByName("android")
            if (androidExt != null) {
                val intType = Int::class.javaPrimitiveType
                val boxedIntType = Int::class.javaObjectType
                val setter =
                    androidExt.javaClass.methods.firstOrNull {
                        it.name == "compileSdkVersion" && it.parameterTypes.size == 1 && it.parameterTypes[0] == intType
                    } ?: androidExt.javaClass.methods.firstOrNull {
                        it.name == "setCompileSdk" && it.parameterTypes.size == 1 && it.parameterTypes[0] == boxedIntType
                    }
                setter?.invoke(androidExt, 36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}