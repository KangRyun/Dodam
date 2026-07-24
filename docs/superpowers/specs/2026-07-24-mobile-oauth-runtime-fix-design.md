# S15P11B209-394 모바일 OAuth 실행 설정 및 연동 오류 수정 설계

## 1. 문제와 근거

Android Emulator에 설치된 `com.dodam.app`에서 Kakao·Google·Naver 로그인 버튼이
모두 Provider 화면을 열지 못하고 즉시 실패한다.

확인 결과 설치된 APK의 Kakao callback scheme은
`kakaomissing-kakao-native-app-key`였고, 다음 비추적 설정 파일은 생성되지 않은
상태였다.

- `frontend/mobile/android/oauth.properties`
- `frontend/mobile/oauth_defines.json`
- `frontend/mobile/ios/Flutter/OAuth.xcconfig`

현재 Android Gradle 설정은 Release·Profile 빌드만 OAuth 값 누락을 검사한다.
따라서 Debug APK는 누락된 값을 placeholder로 패키징할 수 있다. Dart 코드는
누락된 `KAKAO_NATIVE_APP_KEY`와 `GOOGLE_SERVER_CLIENT_ID`를 실행 시점에 발견하지만
설정 오류를 Provider 거부 오류와 동일하게 표시한다. iOS
`Flutter/Debug.xcconfig`에는 `#include? "OAuth.xcconfig"`라는 잘못된 문법도 있다.

Flutter와 Backend의 Token 계약은 이미 일치한다.

- Kakao: Provider `accessToken`
- Google: Provider `idToken`
- Naver: Provider `accessToken`
- Backend: `POST /api/v1/auth/oauth/{provider}`에서 Provider Token을 검증한 뒤
  서비스 Access·Refresh Token 발급

따라서 API를 새로 만들거나 Authorization Code 방식으로 되돌리지 않는다.

## 2. 목표

- 설정이 누락된 실행 불가능한 Android Debug APK 생성을 차단한다.
- OAuth 설정 오류를 사용자 취소, Provider 거부, Backend 거부와 구분한다.
- Android와 iOS가 동일한 OAuth 설정 계약을 사용하게 한다.
- 실제 Provider 설정은 비추적 파일과 환경 변수로만 주입한다.
- 세 Provider의 모바일 SDK Token을 기존 Backend 계약으로 교환한다.

## 3. 구현 설계

### 3.1 네이티브 빌드 설정 검증

Android `preDebugBuild`, `preProfileBuild`, `preReleaseBuild`가 모두 실제 앱 실행에
필요한 네이티브 OAuth 값을 검증하게 한다. 검증 대상은 다음과 같다.

- `KAKAO_NATIVE_APP_KEY`
- `NAVER_CLIENT_ID`
- `NAVER_CLIENT_SECRET`
- `NAVER_APP_NAME`

`GOOGLE_SERVER_CLIENT_ID`는 Android Manifest placeholder가 아니라 Dart SDK
초기화 값이므로 Gradle 네이티브 검증과 분리한다. Dart define 전체 값은 기존
`tool/configure_oauth.dart`가 생성하는 `oauth_defines.json`으로 관리한다.

테스트와 정적 분석은 Provider Secret 없이 실행 가능해야 한다. OAuth 값 검증은
Android APK를 실제로 조립할 때만 수행한다.

### 3.2 런타임 오류 구분

`AuthFailureType`에 OAuth 실행 설정 오류를 표현하는 값을 추가한다. Provider SDK
Gateway가 설정 누락을 보고하면 각 SDK Login Client가 이를 Provider 거부가 아닌
설정 오류로 변환한다.

화면에는 Secret이나 환경 변수 값을 표시하지 않고, 개발 또는 배포 설정을
확인해야 한다는 일반적인 안내만 제공한다. Token, Client Secret, Provider 응답
본문은 로그에 남기지 않는다.

### 3.3 iOS 설정

`Flutter/Debug.xcconfig`의 OAuth 설정 include를 정상 문법으로 수정한다. 실제
`OAuth.xcconfig`는 계속 `.gitignore` 대상으로 유지하며 Windows에서는 설정 계약과
파일 구조까지만 검증한다. 실제 iOS 빌드와 Provider callback 검증은 macOS와
Xcode가 필요하다.

### 3.4 로컬 실제 설정

Provider Console에서 `com.dodam.app`에 연결된 값을 확인한 뒤
`tool/configure_oauth.dart`를 사용해 비추적 설정 파일을 생성한다.

Backend의 `KAKAO_APP_ID`는 Kakao Native App Key와 다른 값이므로 서로 대체하지
않는다. `GOOGLE_CLIENT_ID`는 모바일의 `GOOGLE_SERVER_CLIENT_ID`와 동일한 Web
Client ID를 사용한다. Naver Provider Token 검증은 Backend가 Naver 사용자 정보
API를 호출하는 현재 구조를 유지한다.

### 3.5 Backend 변경 기준

현재 URI, 요청 필드와 Provider별 Token 종류는 일치하므로 Backend 코드를 선제
수정하지 않는다. 실제 Token 교환 테스트에서 다음 중 하나가 확인될 때만 관련
테스트를 먼저 추가하고 최소 범위로 수정한다.

- Google `aud`와 서버 `GOOGLE_CLIENT_ID` 불일치
- Kakao Token의 App ID와 서버 `KAKAO_APP_ID` 불일치
- Provider 정상 Token이 공통 오류 응답으로 잘못 변환됨

## 4. 테스트 전략

1. 설정 오류가 전용 `AuthFailureType`으로 변환되는 실패 테스트를 먼저 작성한다.
2. 로그인 화면이 설정 오류 안내를 표시하는 Widget 실패 테스트를 작성한다.
3. Android Debug 빌드 검증 대상에 OAuth 설정이 포함되는 정적 계약 테스트를
   작성한다.
4. iOS Debug config가 정상 include 문법을 사용하는 정적 계약 테스트를 작성한다.
5. 변경 후 `flutter analyze`, `flutter test`를 실행한다.
6. 실제 비추적 설정을 생성하고 Android Debug APK를 빌드·설치한다.
7. 세 버튼이 Provider 인증 화면으로 진입하는지 확인한다.
8. 사용자 인증 후 Backend Token 교환과 세션 저장을 확인한다.
9. Backend를 수정한 경우 `clean test`, `spotlessCheck`, `javadoc`을 추가 실행한다.

## 5. 제외 범위

- Authorization Code OAuth 재도입
- 자체 로그인 추가
- Apple 로그인 구현
- Provider Key 또는 Token의 Git·Jira 저장
- 관련 없는 인증 화면 디자인 변경
- Windows에서의 iOS 실제 빌드 성공 주장

## 6. 완료 조건

- 설정 누락 Android Debug APK가 조립되지 않는다.
- 설정 오류가 Provider 거부나 Token 오류와 구분된다.
- iOS Debug OAuth include 문법이 올바르다.
- Android에서 Kakao·Google·Naver Provider 인증 화면에 진입한다.
- Provider Token이 기존 Backend 계약으로 교환되고 서비스 세션이 저장된다.
- 실제 Secret이 Git 변경사항에 포함되지 않는다.
- 실행한 검증 결과와 플랫폼 제한 사항을 정확히 보고한다.
