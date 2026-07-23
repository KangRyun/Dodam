# 모바일 OAuth 실연동 및 iOS 지원 설계

## 1. 목적

Flutter 모바일 앱의 Kakao·Google·Naver Mock 로그인을 실제 Provider SDK 로그인과
백엔드 Token 교환 방식으로 전환한다. Android와 iOS가 같은 Domain 계약을 사용하도록
구성하되, 플랫폼별 설정과 Provider SDK 구현을 분리해 변경 영향을 인증 모듈 내부로
제한한다.

관련 Jira:

- Epic: `S15P11B209-379`
- 플랫폼 선행 작업: `S15P11B209-380`
- 실제 로그인 및 백엔드 연동: `S15P11B209-381`
- Sign in with Apple 후속 검토: `S15P11B209-382`

## 2. 현재 상태

- Flutter 프로젝트에는 Android 플랫폼만 존재한다.
- Android `namespace`와 `applicationId`는 기본 예제 값에서 `com.dodam.app`으로
  변경 중이다.
- `KakaoLoginClientImpl`, `GoogleLoginClientImpl`, `NaverLoginClientImpl`은
  Mock Token을 반환한다.
- 기본 앱 런타임의 `AuthRepositoryImpl`은 백엔드를 호출하지 않고 Mock 사용자와
  서비스 Token을 생성한다.
- 백엔드는 `POST /api/v1/auth/oauth/{provider}`에서 Provider Token을 검증하고
  서비스 Access·Refresh Token을 발급한다.

## 3. 확정 계약

| Provider | 모바일이 받는 Credential | 백엔드 요청 필드 |
| --- | --- | --- |
| Kakao | Provider Access Token | `accessToken` |
| Google | ID Token | `idToken` |
| Naver | Provider Access Token | `accessToken` |

모든 요청은 앱 설치 단위 `deviceId`를 포함한다. 사용하지 않는 Token 필드는
`null`로 보내며 Provider Token, Authorization Header, 사용자 개인정보와 요청
전체를 로그에 기록하지 않는다.

## 4. 작업 분리

### 4.1 플랫폼 설정

`S15P11B209-380`에서 다음을 수행한다.

- Flutter iOS 플랫폼 생성
- Android Package와 iOS Bundle ID를 `com.dodam.app`으로 통일
- iOS Deployment Target을 13.0 이상으로 설정
- Kakao·Google·Naver URL Scheme과 Query Scheme 구성
- Android Manifest와 iOS `Info.plist`가 로컬·CI 설정값을 참조하도록 구성
- 실제 Secret을 제외한 설정 예시와 검증 절차 문서화

이 작업은 인증 화면, Coordinator, Repository 동작을 변경하지 않는다.

### 4.2 Provider SDK 및 백엔드 연동

`S15P11B209-381`에서 다음을 수행한다.

- Kakao 공식 `kakao_flutter_sdk_user`를 Client Adapter 뒤에 연결
- Google 공식 `google_sign_in`을 Client Adapter 뒤에 연결
- Naver `flutter_naver_login`을 Client Adapter 뒤에 연결
- Provider SDK 취소·거부·Token 누락을 기존 `AuthFailure`로 변환
- 실제 OAuth 로그인, Onboarding, Token 재발급, 로그아웃 Repository 구현
- 기본 앱 런타임에서 Mock 인증 의존성 제거

SDK 세부 API는 Adapter 내부에만 존재하며 기존 Coordinator와 Domain 인터페이스는
유지한다.

## 5. 설정 및 Secret 관리

- Kakao Native App Key와 Google Client ID는 Git에 직접 작성하지 않는다.
- Naver Client Secret은 Git에 커밋하지 않고 Android 로컬 속성 또는 CI 환경 변수,
  iOS Build Configuration으로 주입한다.
- Git에는 필요한 변수 이름과 예시 파일만 기록한다.
- 누락된 필수 설정은 SDK 호출 전에 검증해 식별 가능한 구성 오류로 처리한다.
- Release 서명용 Google SHA-1과 Kakao Key Hash는 출시 인증서 확정 후 별도로 등록한다.

## 6. 오류 처리

- 사용자가 Provider 화면을 닫으면 `cancelled` 결과로 처리한다.
- Provider가 로그인을 거부하거나 SDK가 실패하면 `providerRejected`로 처리한다.
- 성공 응답에 필요한 Token이 없으면 `invalidCredential`로 처리한다.
- 백엔드 연결 실패는 `network`, 인증 거부는 `invalidCredential`, 계정 제한은
  `accountSuspended`, 만료된 Refresh Token은 `tokenExpired`로 기존 정책에 맞춰
  변환한다.
- 오류 메시지에는 Token, Provider 원문 응답, 사용자 식별자와 서버 내부 정보가
  포함되지 않는다.

## 7. 테스트 및 검증

- Provider SDK Gateway를 주입해 Adapter 성공·취소·실패·Token 누락을 단위 테스트한다.
- 백엔드 요청 JSON에서 Provider별 Token 필드 조합과 `deviceId`를 검증한다.
- 로그인 응답, Session 저장·복원, Refresh Token 재발급, 로그아웃을 테스트한다.
- `flutter analyze`, `flutter test`, Android Debug APK 빌드를 실행한다.
- Windows에서는 iOS 프로젝트 정적 설정까지만 검증한다.
- iOS 실제 빌드, CocoaPods 설치와 실기기 Provider 콜백은 macOS·Xcode에서 최종
  검증해야 한다.

## 8. 출시 제약

App Store Review Guideline 4.8 적용 가능성 때문에 Sign in with Apple을
`S15P11B209-382`로 분리한다. `S15P11B209-380`과 `S15P11B209-381`에서는 백엔드에
정의되지 않은 `APPLE` Provider를 임의로 추가하지 않는다.
