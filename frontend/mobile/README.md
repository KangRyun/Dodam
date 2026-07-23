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
변수로 주입한다. 예시 파일을 복사한 뒤 각 팀 환경의 값을 입력한다.

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
C:\src\flutter\bin\flutter.bat build apk --debug
```

iOS 의존성 설치, 서명, Simulator 및 실기기 빌드 검증에는 macOS와 Xcode가
필요하다. Windows에서는 프로젝트 파일과 설정 계약까지만 검증한다.

```bash
flutter pub get
cd ios
pod install
cd ..
flutter build ios --no-codesign
```

Release 배포 전에는 Google Play App Signing 인증서의 SHA-1을 Google
Android OAuth Client에 추가하고, 같은 인증서의 Kakao Release Key Hash를
Kakao Native App Key에 추가해야 한다.

현재 단계는 Android와 iOS 플랫폼 및 Native 설정을 제공한다. 실제 Provider SDK 로그인,
Provider Token 획득, Backend OAuth API 호출은 후속 이슈에서 구현한다.
