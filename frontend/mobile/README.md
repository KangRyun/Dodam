# dodam

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Mobile platform configuration

Android `applicationId`와 iOS `Bundle Identifier`는 모두 `com.dodam.app`을
사용한다. Provider 콘솔에도 같은 식별자를 등록해야 한다.

OAuth 설정은 실제 값을 Git에 기록하지 않고 로컬 설정 파일이나 CI/CD
변수로 주입한다. 로컬에서는 예시 파일을 복사한 뒤 각 팀 환경의 값을
입력할 수 있다.

```powershell
# Windows
Copy-Item android/oauth.properties.example android/oauth.properties
Copy-Item ios/Flutter/OAuth.xcconfig.example ios/Flutter/OAuth.xcconfig
```

```bash
# macOS / Linux
cp android/oauth.properties.example android/oauth.properties
cp ios/Flutter/OAuth.xcconfig.example ios/Flutter/OAuth.xcconfig
```

두 로컬 설정 파일은 `.gitignore`에 포함되어 있다. 실제 Key, Client ID,
Client Secret을 예시 파일이나 다른 추적 파일에 작성하지 않는다.

CI/CD에서는 필요한 값을 보호 환경 변수로 등록하고 다음 명령으로 빌드
직전에 비추적 설정 파일을 생성한다. 값은 로그에 출력되지 않으며,
placeholder 또는 누락된 값이 있으면 명령이 실패한다.

```bash
dart run tool/configure_oauth.dart --platform=android
dart run tool/configure_oauth.dart --platform=ios
# 두 플랫폼을 함께 생성할 때
dart run tool/configure_oauth.dart --platform=all
```

앱 실행과 빌드에는 생성된 Dart define 파일을 함께 전달한다.

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define-from-file=oauth_defines.json
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define-from-file=oauth_defines.json
```

위 주소는 Android Emulator에서 PC의 로컬 Backend로 접속하는 예시다.
실기기와 iOS Simulator에서는 실행 환경에 맞는 Backend origin으로 교체한다.

Naver Mobile SDK 특성상 `NAVER_CLIENT_SECRET`은 앱 패키지에 포함되므로
역공학으로 추출될 수 있다. `.gitignore`는 소스 관리 노출만 방지한다.
Provider 콘솔의 package·Bundle ID 제한과 Release 서명 정보를 함께
등록하고, 해당 값을 서버 비밀 정보와 같은 수준의 장기 Secret으로
간주하지 않는다.

| 변수 | 용도 |
| --- | --- |
| `KAKAO_NATIVE_APP_KEY` | Kakao SDK 초기화와 Kakao Login URL Scheme |
| `GOOGLE_IOS_CLIENT_ID` | Google iOS OAuth Client ID |
| `GOOGLE_SERVER_CLIENT_ID` | Backend 검증용 Google Web Server Client ID |
| `GOOGLE_REVERSED_CLIENT_ID` | Google iOS callback URL Scheme |
| `NAVER_CLIENT_ID` | Naver Login Client ID |
| `NAVER_CLIENT_SECRET` | Naver Login Client Secret |
| `NAVER_APP_NAME` | Naver 동의 화면에 표시할 앱 이름 |
| `NAVER_URL_SCHEME` | Naver iOS callback URL Scheme |

Provider 콘솔은 다음 값과 일치해야 한다.

- Kakao Android package 및 iOS Bundle ID: `com.dodam.app`
- Google Android package 및 iOS Bundle ID: `com.dodam.app`
- Naver Android package: `com.dodam.app`
- Naver iOS URL Scheme: `dodamnaver`

Android 빌드는 Windows에서도 검증할 수 있다.

```powershell
C:\src\flutter\bin\flutter.bat build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define-from-file=oauth_defines.json
```

iOS 의존성 설치, 서명, Simulator 및 실기기 빌드 검증에는 macOS와 Xcode가
필요하다. Windows에서는 프로젝트 파일과 설정 계약까지만 검증한다.

```bash
flutter pub get
flutter build ios --no-codesign --dart-define=API_BASE_URL=http://localhost:8080 --dart-define-from-file=oauth_defines.json
```

Google·Kakao Plugin은 Flutter Swift Package Manager 구성을 따르지만
`flutter_naver_login`은 Naver iOS SDK를 CocoaPods로 연결한다. macOS에서
Flutter가 `ios/Podfile`을 생성한 뒤 `cd ios && pod install`을 실행하고,
Xcode Workspace로 최종 빌드한다. Windows에서는 이 과정을 검증할 수 없다.

Release 배포 전에는 Google Play App Signing 인증서의 SHA-1을 Google
Android OAuth Client에 추가하고, 같은 인증서의 Kakao Release Key Hash를
Kakao Native App Key에 추가해야 한다.

현재 앱은 Kakao·Naver Access Token과 Google ID Token을 Provider SDK에서 획득하고,
Backend OAuth API에서 서비스 Access·Refresh Token으로 교환한다. 실제 Key는
Repository에 저장하지 않고 로컬 설정 파일이나 CI/CD Secret으로 주입한다.
