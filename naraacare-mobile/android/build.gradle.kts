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
// Old plugins (e.g. flutter_jailbreak_detection 1.10.0) still declare their namespace only as
// `package` in AndroidManifest.xml, which AGP 9 rejects. Fill it in from the manifest.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val android = extensions.getByName("android")
        if (android.javaClass.getMethod("getNamespace").invoke(android) == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            val pkg = if (manifest.exists()) {
                Regex("""package="([^"]+)"""").find(manifest.readText())?.groupValues?.get(1)
            } else {
                null
            }
            android.javaClass
                .getMethod("setNamespace", String::class.java)
                .invoke(android, pkg ?: group.toString())
        }
        // Plugins written for AGP 9 built-in Kotlin (e.g. screen_protector 1.5.3) skip the Kotlin
        // plugin, but android.builtInKotlin=false here, so their Kotlin would never compile.
        if (file("src/main/kotlin").exists()) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
    // Same plugins leave Kotlin on the running JDK's target (e.g. 25) while Java stays on 11, which
    // fails the JVM-target check. Pin both to 17, like :app.
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        pluginManager.withPlugin("com.android.library") {
            val android = extensions.getByName("android")
            val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
            compileOptions.javaClass
                .getMethod("setSourceCompatibility", JavaVersion::class.java)
                .invoke(compileOptions, JavaVersion.VERSION_17)
            compileOptions.javaClass
                .getMethod("setTargetCompatibility", JavaVersion::class.java)
                .invoke(compileOptions, JavaVersion.VERSION_17)
        }
        tasks.matching { it.javaClass.name.contains("KotlinCompile") }.configureEach {
            val options = javaClass.getMethod("getCompilerOptions").invoke(this)

            @Suppress("UNCHECKED_CAST")
            val jvmTarget = options.javaClass.getMethod("getJvmTarget").invoke(options) as Property<Any>
            val jvmTargetClass = Class.forName("org.jetbrains.kotlin.gradle.dsl.JvmTarget", true, javaClass.classLoader)
            jvmTarget.set(jvmTargetClass.enumConstants.first { (it as Enum<*>).name == "JVM_17" })
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
