import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // google-services.json 을 읽어 FCM 설정을 주입한다 (S15P11B209-617).
    id("com.google.gms.google-services")
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

// 릴리스 서명 자재 (S15P11B209-623).
// key.properties 와 keystore 는 .gitignore 대상 — 저장소에 절대 들어오지 않는다.
// CI 에서는 infra/mobile/build-aab.sh 가 Jenkins Credentials 에서 받아 컨테이너에 넣는다.
val keystoreProperties = Properties().apply {
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        keystoreFile.inputStream().use(::load)
    }
}

// "파일이 있다"가 아니라 "네 값이 다 있다"로 판정한다.
// 한 줄이라도 비면 AGP 가 조용히 서명을 건너뛰고, 그 AAB 는 업로드 단계에서야 거절당한다.
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseKeystore =
    releaseSigningKeys.all { !keystoreProperties.getProperty(it).isNullOrBlank() } &&
        keystoreProperties.getProperty("storeFile")
            ?.let { rootProject.file(it).exists() } == true

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
        // flutter_local_notifications 가 요구한다 — 없으면 checkDebugAarMetadata 실패
        // (S15P11B209-617). 구버전 Android에서도 java.time 계열을 쓰기 위한 설정이다.
        isCoreLibraryDesugaringEnabled = true
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

        // key.properties 가 갖춰졌을 때만 만든다. 없는데 만들면 storeFile=null 로
        // configuration 단계에서 죽어, 서명이 필요 없는 debug 빌드까지 못 하게 된다.
        if (hasReleaseKeystore) {
            create("release") {
                // 경로는 rootProject(android/) 기준으로 푼다. 절대경로면 그대로 쓰인다.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 릴리스 키가 있으면 그것으로, 없으면 debug 로 폴백한다.
            // 폴백을 남겨 두는 이유: 개발자가 로컬에서 `flutter run --release` 로 성능을 볼 때
            //   키를 요구하면 아무도 못 돌린다. 대신 **CI 에서는 폴백을 금지**한다(아래 가드).
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }

            // ── R8 축소·난독화를 끈다 (S15P11B209-765) ────────────────────────
            // 2026-08-04, 릴리스 APK 가 실행 즉시 죽었다. 스택은 이랬다:
            //   ClassCastException: ExceptionInInitializerError cannot be cast to Exception
            //     at bf.l0.run(r8-map-id-…)        ← kotlinx.coroutines.DispatchedTask.run
            //
            // 읽는 법: 네이버 로그인 SDK 의 static 초기화가 ExceptionInInitializerError 로
            // 터졌고(= R8 이 리플렉션으로만 참조되는 클래스를 지웠다), SDK 의 실패 처리
            // 경로가 그걸 Exception 으로 캐스팅하려다 앱을 죽였다
            // (NidOAuthInitializingCallback.onFailure 의 시그니처가 Exception 이다).
            //
            // ★ MainActivity 의 initializeNaverSdk() 를 try/catch 로 감싸도 소용없다.
            //   크래시가 Dispatchers.Main 의 코루틴에서 **비동기로** 발생하므로
            //   동기 호출을 감싼 catch 에 걸리지 않는다.
            //
            // 이 프로젝트에는 proguard-rules.pro 가 아예 없다. keep 규칙 없이 R8 만
            // 켜져 있던 것이고, debug 빌드에는 R8 이 없어 이 결함이 보이지 않았다.
            //
            // 왜 규칙을 쓰지 않고 끄나: 어느 클래스를 살려야 하는지는 시행착오로만
            // 알아낼 수 있는데 한 번 확인에 빌드 15분 + 실기기 설치가 든다. 원스토어
            // 등록이 막힌 상태에서 감당할 비용이 아니다. 대가는 APK 가 커지는 것뿐이다.
            //
            // ⚠️ 되돌릴 때: proguard-rules.pro 에 네이버(com.navercorp.nid.**)·카카오
            //   SDK keep 규칙을 넣고 **릴리스 APK 를 실기기에 설치해 앱이 뜨는지**까지
            //   확인한 뒤에 켤 것. 빌드 성공은 검증이 아니다 — 이번이 그 사례다.
            isMinifyEnabled = false
            isShrinkResources = false
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
    // 위 isCoreLibraryDesugaringEnabled 와 짝 — flutter_local_notifications 22.x 요구 버전
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
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

// CI 릴리스 빌드에서 debug 서명 폴백을 금지한다 (S15P11B209-623).
// reason: 위 폴백은 로컬 편의를 위한 것이라, CI 에서도 조용히 동작하면
//   "빌드는 초록불인데 Play 업로드에서 거절되는" 상태가 만들어진다.
//   이 프로젝트에서 반복된 실패 양상이 정확히 "설정은 켜져 있는데 실제로는 아닌" 것이라,
//   폴백이 일어났는지를 빌드 시점에 판정해 즉시 끊는다.
tasks
    .matching { it.name == "preReleaseBuild" }
    .configureEach {
        doFirst {
            val required =
                (System.getenv("DODAM_REQUIRE_RELEASE_SIGNING") ?: "false").equals("true", ignoreCase = true)
            check(!required || hasReleaseKeystore) {
                "DODAM_REQUIRE_RELEASE_SIGNING=true 인데 릴리스 keystore 가 갖춰지지 않았다. " +
                    "android/key.properties 의 storeFile·storePassword·keyAlias·keyPassword 4개와 " +
                    "storeFile 이 가리키는 파일의 실존을 확인할 것 (debug 서명 폴백은 CI 에서 금지)."
            }
        }
    }
