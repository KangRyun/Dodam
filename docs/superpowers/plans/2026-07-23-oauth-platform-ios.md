# OAuth Platform 및 iOS 지원 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 앱에 iOS 플랫폼을 추가하고 Android·iOS의 OAuth 네이티브 설정 기반을 Secret 노출 없이 구성한다.

**Architecture:** `com.dodam.app`을 두 플랫폼의 식별자로 통일하고, Provider별 URL Scheme과 Native 설정값은 플랫폼 설정 파일이 로컬 또는 CI 환경 값을 참조하도록 구성한다. 실제 SDK 호출과 백엔드 인증 전환은 후속 `S15P11B209-381`에서 구현하며 이번 이슈는 플랫폼 계약과 안전한 설정 주입까지만 담당한다.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, Android Gradle Kotlin DSL, Kotlin/JVM 17, iOS 13+, Xcode project configuration

## Global Constraints

- 작업 브랜치는 `feature/S15P11B209-380-oauth-platform`을 사용한다.
- Android namespace·applicationId와 iOS Bundle ID는 `com.dodam.app`이다.
- 실제 Kakao Key, Google Client ID, Naver Client ID·Secret은 Git에 커밋하지 않는다.
- 기존 인증 화면, Coordinator, Mock Client와 Repository 동작은 이번 이슈에서 변경하지 않는다.
- Windows에서는 Android 빌드와 iOS 정적 설정만 검증하고 iOS 빌드 성공을 주장하지 않는다.
- 기존 미커밋 Android Package 변경을 이번 이슈 범위로 보존한다.

---

### Task 1: 플랫폼 식별자 계약과 iOS 프로젝트 생성

**Files:**
- Create: `frontend/mobile/test/platform/oauth_native_config_test.dart`
- Create: `frontend/mobile/ios/**` through the Flutter platform generator
- Modify: `frontend/mobile/.metadata`
- Modify: `frontend/mobile/android/app/build.gradle.kts`
- Move: `frontend/mobile/android/app/src/main/kotlin/com/example/dodam/MainActivity.kt`
- To: `frontend/mobile/android/app/src/main/kotlin/com/dodam/app/MainActivity.kt`

**Interfaces:**
- Consumes: Flutter project metadata and Android application configuration
- Produces: Android·iOS identifier contract fixed to `com.dodam.app`

- [x] **Step 1: 플랫폼 계약 실패 테스트 작성**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android와 iOS 애플리케이션 식별자는 com.dodam.app이다', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(androidGradle, contains('namespace = "com.dodam.app"'));
    expect(androidGradle, contains('applicationId = "com.dodam.app"'));
    expect(iosProject, contains('PRODUCT_BUNDLE_IDENTIFIER = com.dodam.app;'));
  });
}
```

- [x] **Step 2: 테스트가 iOS 프로젝트 부재로 실패하는지 확인**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat test test/platform/oauth_native_config_test.dart
```

Expected: `ios/Runner.xcodeproj/project.pbxproj` 파일을 찾을 수 없어 실패한다.

- [x] **Step 3: Flutter iOS 플랫폼 생성**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat create --platforms=ios --org com.dodam .
```

생성 후 `git diff`를 확인해 기존 `lib/`, `test/`, Android 설정이 덮어써지지 않았는지 검증한다. 생성기가 기존 관리 파일을 변경하면 iOS 플랫폼 등록에 필요한 변경만 유지한다.

- [x] **Step 4: iOS Bundle ID와 Deployment Target 확정**

`ios/Runner.xcodeproj/project.pbxproj`의 Runner Target Debug·Profile·Release 설정을 다음 값으로 통일한다.

```text
IPHONEOS_DEPLOYMENT_TARGET = 13.0;
PRODUCT_BUNDLE_IDENTIFIER = com.dodam.app;
```

RunnerTests Target은 다음 값을 사용한다.

```text
PRODUCT_BUNDLE_IDENTIFIER = com.dodam.app.RunnerTests;
```

- [x] **Step 5: Android Package 이동과 설정 확인**

`MainActivity.kt`는 다음 내용으로 유지한다.

```kotlin
package com.dodam.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
```

- [x] **Step 6: 플랫폼 식별자 테스트 통과 확인**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat test test/platform/oauth_native_config_test.dart
```

Expected: PASS.

- [ ] **Step 7: 변경 Commit**

```powershell
git add frontend/mobile/.metadata frontend/mobile/ios frontend/mobile/android/app/build.gradle.kts frontend/mobile/android/app/src/main/kotlin frontend/mobile/test/platform/oauth_native_config_test.dart
git commit -m "feat(platform): S15P11B209-380 Flutter iOS 플랫폼 구성"
```

### Task 2: OAuth Native 설정과 Secret 분리

**Files:**
- Modify: `frontend/mobile/test/platform/oauth_native_config_test.dart`
- Modify: `frontend/mobile/android/app/build.gradle.kts`
- Modify: `frontend/mobile/android/app/src/main/AndroidManifest.xml`
- Create: `frontend/mobile/android/oauth.properties.example`
- Modify: `frontend/mobile/ios/Runner/Info.plist`
- Modify: `frontend/mobile/ios/Flutter/Debug.xcconfig`
- Modify: `frontend/mobile/ios/Flutter/Release.xcconfig`
- Create: `frontend/mobile/ios/Flutter/OAuth.xcconfig.example`
- Modify: `frontend/mobile/.gitignore`

**Interfaces:**
- Consumes: 로컬 Gradle property, 환경 변수, iOS optional xcconfig
- Produces: Kakao·Google·Naver SDK가 후속 이슈에서 재사용할 Native 설정

- [x] **Step 1: OAuth 설정 계약 실패 테스트 추가**

```dart
test('OAuth Native 설정은 환경 변수 참조와 URL Scheme을 제공한다', () {
  final androidGradle = File('android/app/build.gradle.kts').readAsStringSync();
  final androidManifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
  final gitignore = File('.gitignore').readAsStringSync();

  expect(androidGradle, contains('KAKAO_NATIVE_APP_KEY'));
  expect(androidGradle, contains('NAVER_CLIENT_SECRET'));
  expect(androidManifest, contains(r'${kakaoScheme}'));
  expect(androidManifest, contains(r'${naverClientId}'));
  expect(iosInfo, contains(r'kakao$(KAKAO_NATIVE_APP_KEY)'));
  expect(iosInfo, contains(r'$(GOOGLE_REVERSED_CLIENT_ID)'));
  expect(iosInfo, contains(r'$(NAVER_URL_SCHEME)'));
  expect(gitignore, contains('/android/oauth.properties'));
  expect(gitignore, contains('/ios/Flutter/OAuth.xcconfig'));
});

test('Repository에 실제 OAuth Credential 값이 포함되지 않는다', () {
  final trackedExamples = [
    File('android/oauth.properties.example').readAsStringSync(),
    File('ios/Flutter/OAuth.xcconfig.example').readAsStringSync(),
  ].join('\n');

  expect(trackedExamples, contains('KAKAO_NATIVE_APP_KEY=your-'));
  expect(trackedExamples, contains('GOOGLE_IOS_CLIENT_ID=your-'));
  expect(trackedExamples, contains('GOOGLE_SERVER_CLIENT_ID=your-'));
  expect(trackedExamples, contains('NAVER_CLIENT_ID=your-'));
  expect(trackedExamples, contains('NAVER_CLIENT_SECRET=your-'));
  expect(trackedExamples, isNot(contains('apps.googleusercontent.com')));
});
```

- [x] **Step 2: 테스트가 Native 설정 부재로 실패하는지 확인**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat test test/platform/oauth_native_config_test.dart
```

Expected: 필요한 placeholder, URL Scheme 또는 예시 파일이 없어 실패한다.

- [x] **Step 3: Android 설정 주입 구현**

`build.gradle.kts`는 `android/oauth.properties` 또는 같은 이름의 환경 변수를 읽고
Manifest placeholder에 전달한다. 실제 값이 없을 때는 빌드는 가능하지만 OAuth 호출이
불가능한 명시적 `missing-*` 값을 사용한다.

```kotlin
val oauthProperties = java.util.Properties().apply {
    val oauthFile = rootProject.file("oauth.properties")
    if (oauthFile.exists()) {
        oauthFile.inputStream().use(::load)
    }
}

fun oauthValue(name: String): String =
    System.getenv(name)
        ?: oauthProperties.getProperty(name)
        ?: "missing-${name.lowercase().replace('_', '-')}"
```

`defaultConfig`에는 다음 placeholder를 추가한다.

```kotlin
manifestPlaceholders["kakaoScheme"] = "kakao${oauthValue("KAKAO_NATIVE_APP_KEY")}"
manifestPlaceholders["naverClientId"] = oauthValue("NAVER_CLIENT_ID")
manifestPlaceholders["naverClientSecret"] = oauthValue("NAVER_CLIENT_SECRET")
manifestPlaceholders["naverClientName"] = oauthValue("NAVER_APP_NAME")
```

- [x] **Step 4: Android Manifest OAuth 항목 추가**

Application에 Naver metadata를 추가하고 Kakao callback Activity를 등록한다.

```xml
<meta-data
    android:name="com.naver.sdk.clientId"
    android:value="${naverClientId}" />
<meta-data
    android:name="com.naver.sdk.clientSecret"
    android:value="${naverClientSecret}" />
<meta-data
    android:name="com.naver.sdk.clientName"
    android:value="${naverClientName}" />

<activity
    android:name="com.kakao.sdk.flutter.auth.AuthCodeHandlerActivity"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:host="oauth" android:scheme="${kakaoScheme}" />
    </intent-filter>
</activity>
```

- [x] **Step 5: iOS optional Build Configuration 추가**

`Debug.xcconfig`와 `Release.xcconfig`에 다음 optional include를 추가한다.

```text
#include? "OAuth.xcconfig"
```

`OAuth.xcconfig.example`은 다음 변수 이름만 제공한다.

```text
KAKAO_NATIVE_APP_KEY=your-kakao-native-app-key
GOOGLE_IOS_CLIENT_ID=your-google-ios-client-id
GOOGLE_SERVER_CLIENT_ID=your-google-web-server-client-id
GOOGLE_REVERSED_CLIENT_ID=your-google-reversed-client-id
NAVER_CLIENT_ID=your-naver-client-id
NAVER_CLIENT_SECRET=your-naver-client-secret
NAVER_APP_NAME=Dodam
NAVER_URL_SCHEME=your-naver-url-scheme
```

- [x] **Step 6: iOS Info.plist OAuth Scheme 추가**

`Info.plist`에 Kakao, Google, Naver URL Scheme과 Provider App 조회 Scheme을 하나의
`CFBundleURLTypes` 배열로 구성한다. Google Server Client ID와 Naver 설정은
Build Setting 변수를 참조한다.

```xml
<key>GIDClientID</key>
<string>$(GOOGLE_IOS_CLIENT_ID)</string>
<key>GIDServerClientID</key>
<string>$(GOOGLE_SERVER_CLIENT_ID)</string>
<key>NidUrlScheme</key>
<string>$(NAVER_URL_SCHEME)</string>
<key>NidClientID</key>
<string>$(NAVER_CLIENT_ID)</string>
<key>NidClientSecret</key>
<string>$(NAVER_CLIENT_SECRET)</string>
<key>NidAppName</key>
<string>$(NAVER_APP_NAME)</string>
```

URL Scheme은 `kakao$(KAKAO_NATIVE_APP_KEY)`, `$(GOOGLE_REVERSED_CLIENT_ID)`,
`$(NAVER_URL_SCHEME)` 세 항목을 각각 등록한다. `LSApplicationQueriesSchemes`에는
Kakao와 Naver SDK가 조회하는 Scheme을 등록한다.

- [x] **Step 7: 로컬 설정 파일 Git 제외**

`.gitignore`에 다음을 추가한다.

```text
/android/oauth.properties
/ios/Flutter/OAuth.xcconfig
```

- [x] **Step 8: OAuth 설정 계약 테스트 통과 확인**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat test test/platform/oauth_native_config_test.dart
```

Expected: PASS.

- [x] **Step 9: 변경 Commit**

```powershell
git add frontend/mobile/.gitignore frontend/mobile/android frontend/mobile/ios frontend/mobile/test/platform/oauth_native_config_test.dart
git commit -m "feat(auth): S15P11B209-380 모바일 OAuth Native 설정 추가"
```

### Task 2.5: Provider Console 플랫폼 등록

- [x] Kakao 앱 이름을 `Dodam`으로 정리하고 모바일 Native App Key에 Android package와
      iOS Bundle ID `com.dodam.app`을 등록한다.
- [x] Google Cloud에 `Dodam iOS` OAuth Client를 생성하고 Bundle ID
      `com.dodam.app`을 등록한다.
- [x] Naver `Dodam` 앱에 iOS 환경을 추가하고 URL Scheme `dodamnaver`를 등록한다.
- [x] 실제 Client ID, Client Secret, Native App Key는 Repository 문서나 예시 파일에
      기록하지 않는다.

### Task 3: 설정 문서와 전체 검증

**Files:**
- Modify: `frontend/mobile/README.md`
- Modify: `docs/superpowers/plans/2026-07-23-oauth-platform-ios.md`

**Interfaces:**
- Consumes: Task 1·2의 플랫폼 설정
- Produces: 로컬 개발·CI·macOS 검증자가 재현 가능한 설정 안내

- [x] **Step 1: README에 설정 절차 작성**

다음 항목을 실제 파일명과 함께 기록한다.

- Android: `android/oauth.properties.example`을 `android/oauth.properties`로 복사
- iOS: `ios/Flutter/OAuth.xcconfig.example`을 `OAuth.xcconfig`로 복사
- CI: 동일한 변수 이름을 환경 변수 또는 생성된 비추적 파일로 주입
- Release: Google Play App Signing SHA-1과 Kakao Release Key Hash 추가
- iOS: macOS에서 `flutter pub get`, `cd ios`, `pod install`, `flutter build ios --no-codesign`
- 실제 Credential 파일은 Git에 추가하지 않음

- [x] **Step 2: Secret 추적 여부 확인**

Run:

```powershell
git ls-files frontend/mobile/android/oauth.properties frontend/mobile/ios/Flutter/OAuth.xcconfig
git status --short --ignored frontend/mobile/android/oauth.properties frontend/mobile/ios/Flutter/OAuth.xcconfig
```

Expected: 첫 명령은 출력이 없고 두 번째 명령은 로컬 Credential 파일이 ignored
상태임을 보여준다.

- [x] **Step 3: Flutter 정적 분석과 테스트**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test
```

Expected: `No issues found`, 모든 테스트 PASS.

- [x] **Step 4: Android Debug APK 빌드**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat build apk --debug
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` 생성.

- [x] **Step 5: iOS 정적 설정 확인**

Run:

```powershell
cd frontend/mobile
C:\src\flutter\bin\flutter.bat test test/platform/oauth_native_config_test.dart
Select-String -Path ios/Runner.xcodeproj/project.pbxproj -Pattern "PRODUCT_BUNDLE_IDENTIFIER = com.dodam.app;"
Select-String -Path ios/Runner/Info.plist -Pattern "KAKAO_NATIVE_APP_KEY|GOOGLE_REVERSED_CLIENT_ID|NAVER_URL_SCHEME"
```

Expected: 플랫폼 계약 테스트 PASS와 설정 항목 출력. Windows에서는 iOS build 명령을
실행하지 않는다.

- [x] **Step 6: 계획 체크 상태와 README Commit**

완료된 체크박스를 `[x]`로 변경한 뒤 다음 Commit을 생성한다.

```powershell
git add frontend/mobile/README.md docs/superpowers/plans/2026-07-23-oauth-platform-ios.md
git commit -m "docs(auth): S15P11B209-380 OAuth 플랫폼 설정 안내 추가"
```

- [x] **Step 7: Branch 최종 검증**

Run:

```powershell
git status --short
git log --oneline origin/develop..HEAD
git diff --check origin/develop...HEAD
```

Expected: 작업 트리가 깨끗하고 모든 Commit Message에 `S15P11B209-380`이 포함되며
공백 오류가 없다.
