import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val oauthProperties = Properties().apply {
    val oauthFile = rootProject.file("oauth.properties")
    if (oauthFile.exists()) {
        oauthFile.inputStream().use(::load)
    }
}

fun oauthValue(name: String): String =
    System.getenv(name)
        ?: oauthProperties.getProperty(name)
        ?: "missing-${name.lowercase().replace('_', '-')}"

fun requireOAuthValue(name: String) {
    val value = oauthValue(name)
    require(
        value.isNotBlank() &&
            !value.startsWith("missing-") &&
            !value.startsWith("your-") &&
            !value.contains("\n") &&
            !value.contains("\r"),
    ) {
        "Missing or invalid required OAuth configuration: $name"
    }
}

android {
    namespace = "com.dodam.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dodam.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["kakaoScheme"] = "kakao${oauthValue("KAKAO_NATIVE_APP_KEY")}"
        manifestPlaceholders["naverClientId"] = oauthValue("NAVER_CLIENT_ID")
        manifestPlaceholders["naverClientSecret"] = oauthValue("NAVER_CLIENT_SECRET")
        manifestPlaceholders["naverClientName"] = oauthValue("NAVER_APP_NAME")
    }

    signingConfigs {
        getByName("debug") {
            storeFile = file("dodam-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
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
    implementation("com.navercorp.nid:oauth:5.11.2")
}

tasks
    .matching {
        it.name == "preDebugBuild" ||
            it.name == "preReleaseBuild" ||
            it.name == "preProfileBuild"
    }
    .configureEach {
        doFirst {
            listOf(
                "KAKAO_NATIVE_APP_KEY",
                "GOOGLE_SERVER_CLIENT_ID",
                "NAVER_CLIENT_ID",
                "NAVER_CLIENT_SECRET",
                "NAVER_APP_NAME",
            ).forEach(::requireOAuthValue)
        }
    }
