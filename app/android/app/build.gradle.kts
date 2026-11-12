import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties（Git 管理外）があればその鍵で署名、無ければデバッグ鍵
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "app.thetahatch.photo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.thetahatch.photo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // シリーズ共通の鍵（Theta.Hatch.Series secrets/README.md）で署名する。
    // CI：Secret 4 つ（release.yml が鍵を SIGNING_FILE に書き出す）。手元：android/key.properties（Git 管理外）。
    // どちらも無ければデバッグ鍵（ハブからは入らない・ハブの共通設定も読めない）。別名はここに書かない。
    val signingFile = System.getenv("SIGNING_FILE")
    signingConfigs {
        if (!signingFile.isNullOrEmpty()) {
            create("release") {
                storeFile = file(signingFile)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
            }
        } else if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // シリーズの権限（app.thetahatch.permission.SHARE）の定義は、本番の鍵で署名するときだけ入れる
    if (signingConfigs.findByName("release") != null) {
        sourceSets.getByName("release").manifest.srcFile("src/series/AndroidManifest.xml")
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
