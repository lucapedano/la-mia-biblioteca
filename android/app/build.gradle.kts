import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadKeyPropertiesFile = rootProject.file("key.properties")
val uploadKeyProperties = Properties()
if (uploadKeyPropertiesFile.isFile) {
    uploadKeyPropertiesFile.inputStream().use(uploadKeyProperties::load)
}

android {
    namespace = "it.lamialibreria.la_mia_libreria"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    if (uploadKeyPropertiesFile.isFile) {
        signingConfigs {
            create("release") {
                val keyStorePath = uploadKeyProperties.getProperty("storeFile")
                    ?: throw GradleException("Missing storeFile in android/key.properties")
                storeFile = rootProject.file(keyStorePath)
                storePassword = uploadKeyProperties.getProperty("storePassword")
                    ?: throw GradleException("Missing storePassword in android/key.properties")
                keyAlias = uploadKeyProperties.getProperty("keyAlias")
                    ?: throw GradleException("Missing keyAlias in android/key.properties")
                keyPassword = uploadKeyProperties.getProperty("keyPassword")
                    ?: throw GradleException("Missing keyPassword in android/key.properties")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "it.lamialibreria.la_mia_libreria"
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

    buildTypes {
        release {
            if (uploadKeyPropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

gradle.taskGraph.whenReady {
    val packagingRelease = allTasks.any {
        (it.name == "assembleRelease" || it.name == "bundleRelease") &&
            it.project == project
    }
    if (packagingRelease && !uploadKeyPropertiesFile.isFile) {
        throw GradleException(
            "Release signing is not configured. Create android/key.properties " +
                "and the upload keystore before building a release."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
