# Mobile OAuth Runtime Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kakao·Google·Naver 로그인 버튼이 공식 브랜드 SVG를 일관된 레이아웃으로 표시하고, 올바른 OAuth 설정을 사용해 Provider 인증과 Backend Token 교환을 수행하게 한다.

**Architecture:** 기존 Provider SDK Gateway → Login Client → Coordinator → `RemoteAuthRepository` 흐름과 Provider Token API 계약은 유지한다. 설정 누락을 별도 Domain 실패로 전달하고, Android 빌드 시 설정을 검증하며, 로고 표현은 공통 `SocialLoginButton`에 한정한다.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, `flutter_svg`, Kakao Flutter SDK, Google Sign-In, Flutter Naver Login, Spring Boot 3.5.16

## Global Constraints

- Kakao·Naver는 `accessToken`, Google은 `idToken`을 Backend에 전달한다.
- 실제 Key, Client ID, Client Secret과 Token을 Git·Jira·로그에 기록하지 않는다.
- Android Package와 iOS Bundle ID는 `com.dodam.app`을 유지한다.
- Provider 공식 SVG의 색상, 비율과 `viewBox`를 변형하지 않는다.
- Backend API가 실제 Token 테스트에서 실패한 경우에만 Backend를 수정한다.
- iOS 실제 빌드는 macOS와 Xcode에서만 완료 여부를 판단한다.

---

### Task 1: 공식 SVG 버튼 레이아웃

**Files:**
- Create: `frontend/mobile/assets/branding/kakao_symbol.svg`
- Create: `frontend/mobile/assets/branding/google_g.svg`
- Create: `frontend/mobile/assets/branding/naver_n.svg`
- Modify: `frontend/mobile/pubspec.yaml`
- Modify: `frontend/mobile/lib/design_system/components/buttons/social_login_button.dart`
- Test: `frontend/mobile/test/design_system/social_login_button_test.dart`

**Interfaces:**
- Consumes: `SocialLoginProvider`, `AppSizes.buttonHeight`
- Produces: 각 Provider별 `SocialLoginButton`과 `social-login-<provider>-icon` Key

- [ ] **Step 1: SVG와 공통 간격을 요구하는 실패 Widget 테스트 작성**

```dart
testWidgets('세 소셜 버튼은 동일한 SVG 영역과 레이블 간격을 사용한다', (tester) async {
  for (final provider in SocialLoginProvider.values) {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SocialLoginButton(provider: provider, onPressed: () {}),
        ),
      ),
    );
    final icon = find.byKey(ValueKey('social-login-${provider.name}-icon'));
    final label = find.text(socialLoginLabel(provider));
    expect(tester.getSize(icon), const Size.square(20));
    expect(tester.getTopLeft(label).dx - tester.getTopRight(icon).dx, 10);
    expect(tester.widget<Text>(label).style?.fontSize, 16);
  }
});
```

- [ ] **Step 2: 테스트가 기존 PNG·Stack 구현 때문에 실패하는지 확인**

Run: `flutter test test/design_system/social_login_button_test.dart`

Expected: FAIL because the icon Key and SVG-based common layout do not exist.

- [ ] **Step 3: 공식 벡터 자산과 `flutter_svg` 직접 의존성 추가**

Provider 공식 배포물에서 추출한 SVG 세 개를 `assets/branding/`에 추가하고
`pubspec.yaml`의 dependencies에 다음을 선언한다.

```yaml
flutter_svg: ^2.2.3
```

- [ ] **Step 4: `Stack`을 고정 규격 `Row`로 교체**

```dart
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox.square(
      key: ValueKey('social-login-${provider.name}-icon'),
      dimension: 20,
      child: SvgPicture.asset(visual.iconAsset),
    ),
    const SizedBox(width: 10),
    Text(
      visual.label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  ],
)
```

`_SocialVisual`의 PNG 경로, Provider별 icon size와 horizontal padding은 제거하고
공통 버튼 padding을 사용한다.

- [ ] **Step 5: 버튼 테스트 통과 확인**

Run: `flutter test test/design_system/social_login_button_test.dart`

Expected: PASS.

### Task 2: OAuth 설정 오류 Domain 전달

**Files:**
- Modify: `frontend/mobile/lib/features/auth/domain/failures/auth_failure.dart`
- Modify: `frontend/mobile/lib/features/auth/data/clients/kakao_sdk_login_client.dart`
- Modify: `frontend/mobile/lib/features/auth/data/clients/google_sdk_login_client.dart`
- Modify: `frontend/mobile/lib/features/auth/data/clients/naver_sdk_login_client.dart`
- Modify: `frontend/mobile/lib/features/auth/presentation/screens/social_login_screen.dart`
- Test: `frontend/mobile/test/features/auth/oauth_sdk_login_client_test.dart`
- Test: `frontend/mobile/test/features/auth/social_login_screen_test.dart`

**Interfaces:**
- Produces: `AuthFailureType.configuration`
- Consumes: `ProviderSdkFailureType.configuration`

- [ ] **Step 1: 세 Provider 설정 오류가 `configuration`으로 매핑되는 실패 테스트 작성**

```dart
for (final client in [KakaoSdkLoginClient(gateway: gateway), GoogleSdkLoginClient(gateway: gateway), NaverSdkLoginClient(gateway: gateway)]) {
  await expectLater(
    client.signIn(),
    throwsA(isA<AuthFailure>().having((failure) => failure.type, 'type', AuthFailureType.configuration)),
  );
}
```

- [ ] **Step 2: 전용 안내 문구 Widget 실패 테스트 작성**

```dart
expect(
  find.textContaining('앱 로그인 설정을 확인해 주세요'),
  findsOneWidget,
);
```

- [ ] **Step 3: 두 테스트가 `configuration` 값 부재로 실패하는지 확인**

Run: `flutter test test/features/auth/oauth_sdk_login_client_test.dart test/features/auth/social_login_screen_test.dart`

Expected: compilation/test FAIL for missing `AuthFailureType.configuration`.

- [ ] **Step 4: 최소 Domain 매핑과 화면 문구 구현**

`AuthFailureType.configuration`을 추가하고 각 SDK Client의 configuration 분기에서
해당 타입을 사용한다. 화면 메시지는 다음으로 고정한다.

```dart
AuthFailureType.configuration =>
  '앱 로그인 설정을 확인해 주세요. 문제가 계속되면 관리자에게 문의해 주세요.',
```

설정 오류는 사용자 재시도로 해결되지 않으므로 `canRetry`는 `false`로 유지한다.

- [ ] **Step 5: 인증 단위 테스트 통과 확인**

Run: `flutter test test/features/auth/oauth_sdk_login_client_test.dart test/features/auth/social_login_screen_test.dart`

Expected: PASS.

### Task 3: Android Debug 및 iOS Debug 설정 검증

**Files:**
- Modify: `frontend/mobile/android/app/build.gradle.kts`
- Modify: `frontend/mobile/ios/Flutter/Debug.xcconfig`
- Modify: `frontend/mobile/test/platform/oauth_native_config_test.dart`

**Interfaces:**
- Consumes: 기존 `requireOAuthValue(String)`
- Produces: Debug·Profile·Release 공통 OAuth 설정 검증

- [ ] **Step 1: Debug 검증과 iOS include를 요구하는 실패 테스트 작성**

```dart
expect(androidGradle, contains('preDebugBuild'));
expect(iosDebugConfig, contains('#include "OAuth.xcconfig"'));
expect(iosDebugConfig, isNot(contains('#include? "OAuth.xcconfig"')));
```

- [ ] **Step 2: 테스트가 현재 설정에서 실패하는지 확인**

Run: `flutter test test/platform/oauth_native_config_test.dart`

Expected: FAIL for missing `preDebugBuild` and malformed iOS include.

- [ ] **Step 3: 세 빌드 타입에 같은 검증 적용**

```kotlin
tasks
    .matching {
        it.name == "preDebugBuild" ||
            it.name == "preProfileBuild" ||
            it.name == "preReleaseBuild"
    }
```

iOS Debug 설정은 다음 두 줄로 수정한다.

```text
#include "Generated.xcconfig"
#include "OAuth.xcconfig"
```

- [ ] **Step 4: 플랫폼 계약 테스트 통과 확인**

Run: `flutter test test/platform/oauth_native_config_test.dart`

Expected: PASS.

### Task 4: 실제 비추적 설정과 Android 실행 검증

**Files:**
- Generate, do not commit: `frontend/mobile/android/oauth.properties`
- Generate, do not commit: `frontend/mobile/oauth_defines.json`
- Generate, do not commit: `frontend/mobile/ios/Flutter/OAuth.xcconfig`

**Interfaces:**
- Consumes: Provider Console의 `com.dodam.app` 등록 값
- Produces: Android/iOS 네이티브 설정과 Dart define 파일

- [ ] **Step 1: Provider Console 값과 Backend 환경 변수의 식별자 일치 확인**

값 자체는 출력하지 않고 다음 관계만 확인한다.

```text
Kakao Native App Key -> KAKAO_NATIVE_APP_KEY
Kakao numeric App ID -> Backend KAKAO_APP_ID
Google Web Client ID -> GOOGLE_SERVER_CLIENT_ID == Backend GOOGLE_CLIENT_ID
Naver mobile values -> NAVER_CLIENT_ID, NAVER_CLIENT_SECRET, NAVER_APP_NAME
```

- [ ] **Step 2: 기존 생성기로 비추적 설정 파일 생성**

Run: `dart run tool/configure_oauth.dart --platform=all`

Expected: `OAuth 설정 파일 생성 완료.` and no secret values in stdout.

- [ ] **Step 3: 설정이 없는 빌드가 명확히 실패하는지 별도 임시 환경에서 확인**

Run: `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080`

Expected: Gradle failure naming missing OAuth variable names but not values.

- [ ] **Step 4: 실제 설정으로 Debug APK 빌드·설치**

Run:

```powershell
flutter build apk --debug `
  --dart-define=API_BASE_URL=http://10.0.2.2:8080 `
  --dart-define-from-file=oauth_defines.json
flutter install -d emulator-5554
```

Expected: build and install exit code 0.

- [ ] **Step 5: 세 Provider 버튼과 Backend Token 교환 검증**

각 버튼이 Provider 인증 화면으로 진입하고, 인증 완료 후 앱이 서비스 세션을
저장하는지 확인한다. 사용자 취소가 필요하면 취소 후 오류 패널이 표시되지 않는지도
확인한다.

### Task 5: 전체 회귀 검증과 통합

**Files:**
- Modify: `frontend/mobile/README.md`

**Interfaces:**
- Produces: 재현 가능한 OAuth 로컬 실행·검증 절차

- [ ] **Step 1: README에 Debug fail-fast와 공식 SVG 출처 원칙 추가**

실제 Secret이나 개인 PC 경로 없이 `configure_oauth.dart`와
`--dart-define-from-file` 사용 순서, 설정 누락 시 빌드 실패를 설명한다.

- [ ] **Step 2: Flutter 전체 검증**

Run:

```powershell
flutter analyze
flutter test
flutter build apk --debug `
  --dart-define=API_BASE_URL=http://10.0.2.2:8080 `
  --dart-define-from-file=oauth_defines.json
```

Expected: all commands exit code 0.

- [ ] **Step 3: Git 안전성 확인**

Run:

```powershell
git status --short
git diff --check
git ls-files frontend/mobile/android/oauth.properties frontend/mobile/oauth_defines.json frontend/mobile/ios/Flutter/OAuth.xcconfig
```

Expected: 비추적 Secret 파일이 staged/tracked 목록에 나타나지 않는다.

- [ ] **Step 4: 이슈 코드가 포함된 구현 커밋**

```powershell
git commit -m "fix: S15P11B209-394 restore mobile OAuth runtime integration"
```

- [ ] **Step 5: Push, Merge Request, Merge와 Jira 완료 처리**

브랜치를 Push하고 `develop` 대상 Merge Request를 생성한다. 검증 결과와 iOS
미실행 제한을 MR에 기록하고 병합 성공 후 Jira 이슈를 완료로 전환한다.
