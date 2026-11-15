plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.naraacare.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (scheduled reminders) needs Java 8+ APIs on old Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.naraacare.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        resValues = true
    }

    // Flavors (doc 08 §4): separate app IDs so dev/staging/prod install side by side.
    flavorDimensions += "env"
    productFlavors {
        // Referral link hosts (REFERRAL_LINK_DOMAIN per flavor; domain to confirm, OQ-39).
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "NaraaCare Dev")
            manifestPlaceholders["referralLinkHost"] = "dev.naraacare.app"
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "NaraaCare Staging")
            manifestPlaceholders["referralLinkHost"] = "staging.naraacare.app"
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "NaraaCare")
            manifestPlaceholders["referralLinkHost"] = "naraacare.app"
        }
    }

    buildTypes {
        release {
            // Release signing (upload keystore from CI secrets) is wired in Session 17.
            // Until then release builds use debug keys and must never be uploaded to a store.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Apache-2.0; required by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
