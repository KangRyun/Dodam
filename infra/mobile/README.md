# Android 릴리스 AAB 빌드 파이프라인 (S15P11B209-623)

Play Console 에 올릴 **AAB(Android App Bundle)** 를 재현 가능하게 굽는 경로.
호스트에서도 Jenkins 에서도 같은 명령으로 같은 결과가 나오는 것이 목표다.

```
infra/mobile/
├── Dockerfile      # Flutter 3.44.7 + JDK 17 + Android SDK 36 툴체인 이미지
├── build-aab.sh    # 호스트/Jenkins 공용 진입점 (컨테이너 수명·자재 주입·산출물 회수)
├── ci-build.sh     # 컨테이너 **안에서** 도는 실제 빌드 절차
└── README.md
```

---

## 왜 자체 이미지인가 (기성 이미지를 검토했고, 못 쓴다)

| 후보 | 결과 |
|---|---|
| `ghcr.io/cirruslabs/flutter:3.44.7` | **404** — 존재하지 않음 (3.44.3·3.44.5·3.44.6 도 전부 404) |
| `ghcr.io/cirruslabs/flutter:3.44.0` | 존재하나 **Dart 3.12.0**. `pubspec.yaml` 이 `sdk: ^3.12.2` 라 `flutter pub get` 이 거절 |
| `ghcr.io/cirruslabs/flutter:stable` | 떠다니는 태그 — "어제 성공한 빌드가 오늘 실패"를 만든다. 재현성이 목적이라 배제 |

→ 팀·개발 호스트가 쓰는 **3.44.7 을 고정**한 이미지를 직접 만든다.
Flutter 태그 `3.44.7` = 커밋 `84fc5cbb22` (호스트 `flutter --version` 과 동일함을 확인).

---

## 1. 툴체인 이미지 빌드 (최초 1회 / 버전 올릴 때)

```bash
docker build -t dodam-flutter-builder:3.44.7 infra/mobile
```

이미지 빌드 마지막 단계에서 `flutter doctor` 의 **Android toolchain 이 ✓ 인지 검사**한다.
✓ 가 아니면 이미지가 만들어지지 않는다 — "설치는 됐는데 동작 안 함"을 파이프라인이 아니라
이미지 단계에서 잡기 위해서다.

> NDK 는 일부러 넣지 않았다(약 1.5GB 절약). 네이티브 모듈을 쓰는 플러그인이 추가되면
> `Dockerfile` 의 `sdkmanager --install` 줄에 `"ndk;28.2.13676358"` 을 더한다.

---

## 2. 릴리스 keystore 만들기 (강륜님이 직접 — 1회, 되돌릴 수 없음)

> ⚠️ **이 키를 잃어버리면 이 앱은 영원히 업데이트할 수 없다.**
> Play App Signing 에 등록하면 앱 서명 키는 구글이 보관하지만, **업로드 키는 여전히 본인 책임**이다.
> 비밀번호를 잊는 것도 분실과 같다.

```bash
mkdir -p ~/dodam-secrets && chmod 700 ~/dodam-secrets

docker run --rm -it -v ~/dodam-secrets:/keys eclipse-temurin:17-jdk-noble \
  keytool -genkeypair -v \
    -keystore /keys/upload-keystore.jks \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -alias dodam-upload
```

- `-validity 10000`(약 27년) — Play 는 2033-10-22 이후까지 유효한 키를 요구한다.
- 대화형으로 이름·조직·비밀번호를 묻는다. **비밀번호는 본인만 알아야 한다.**
- 생성 후 `chmod 600 ~/dodam-secrets/upload-keystore.jks`

이어서 `~/dodam-secrets/key.properties` 를 만든다:

```properties
storeFile=upload-keystore.jks
storePassword=<위에서 정한 keystore 비밀번호>
keyAlias=dodam-upload
keyPassword=<위에서 정한 키 비밀번호>
```

> `storeFile` 은 **컨테이너 안 경로 기준의 상대경로**다. `build-aab.sh` 가 keystore 를
> `/src/android/upload-keystore.jks` 로 넣고, gradle 이 `rootProject`(= `android/`) 기준으로 푼다.
> 호스트 절대경로를 적으면 컨테이너 안에서 못 찾는다.

`~/dodam-secrets/` 는 저장소 밖이다. 저장소 쪽은 `.gitignore` 가
`key.properties`·`**/*.jks`·`**/*.keystore` 를 이미 막고 있다.

**백업**: keystore 와 비밀번호를 팀 비밀 저장소(또는 오프라인 매체)에 이중 보관할 것.
이 서버 한 곳에만 있으면 인스턴스와 함께 사라진다.

---

## 3. OAuth 값 파일

`android/build.gradle.kts` 의 `preReleaseBuild` 가드가 아래 5개를 검사한다.
하나라도 비면 빌드가 즉시 실패한다(빈 값으로 서명된 앱이 나가는 것보다 낫다).

`~/dodam-secrets/oauth.env`:

```
KAKAO_NATIVE_APP_KEY=...
GOOGLE_SERVER_CLIENT_ID=...
NAVER_CLIENT_ID=...
NAVER_CLIENT_SECRET=...
NAVER_APP_NAME=...
```

값은 `frontend/mobile/android/oauth.properties`(각자 로컬, gitignore 대상)와 같다.

---

## 4. 빌드

```bash
KEYSTORE_FILE=~/dodam-secrets/upload-keystore.jks \
KEY_PROPERTIES_FILE=~/dodam-secrets/key.properties \
OAUTH_ENV_FILE=~/dodam-secrets/oauth.env \
infra/mobile/build-aab.sh
```

산출물: `build-artifacts/app-release.aab` + `build-artifacts/signing-report.txt`

`BUILD_NUMBER=<n>` 를 주면 versionCode 가 그 값이 된다(Play 는 같은 versionCode 재업로드를 거절).

### 서명 없이 툴체인만 확인하고 싶을 때

```bash
REQUIRE_RELEASE_SIGNING=false OAUTH_ENV_FILE=~/dodam-secrets/oauth.env \
infra/mobile/build-aab.sh
```

debug 키로 서명된 AAB 가 나온다. **Play 에 올릴 수 없다** — 툴체인 점검 전용이다.

---

## 5. Jenkins

`BUILD_ANDROID_AAB` 파라미터를 체크한 빌드에서만 `Build — android AAB` 스테이지가 돈다.
배포(Deploy·Healthcheck) **뒤에** 있어 AAB 빌드가 서버 배포를 지연시키지 않는다.

필요한 Credentials 3종(전부 **Secret file**):

| ID | 내용 |
|---|---|
| `dodam-android-keystore` | `upload-keystore.jks` |
| `dodam-android-key-properties` | 위 `key.properties` |
| `dodam-mobile-oauth-env` | 위 `oauth.env` |

> Multibranch 잡은 `parameters {}` 블록을 **한 번 실행한 뒤에야** 파라미터를 인식한다.
> 이 커밋 후 첫 빌드에는 체크박스가 안 보이는 게 정상이고, 그 다음 빌드부터 나온다.

---

## 설계상 반드시 지켜야 할 것

### bind mount 를 쓰지 않는다

Jenkins 는 컨테이너 안에서 **호스트** 도커 소켓을 부른다(Docker-out-of-Docker).
`-v "$PWD:/src"` 를 쓰면 경로 해석은 Jenkins 컨테이너 안에서, 실제 마운트는 호스트가 한다.
`jenkins_home` 은 named volume 이라 `/var/jenkins_home/workspace/...` 는 호스트에 **없고**,
도커는 없는 경로에 **빈 디렉터리를 만들어 붙인다.** 소스가 사라진 채 빌드된다.

> 이 저장소에서 실제로 두 번 터졌다 — 2026-07-22 nginx 빈 conf, 2026-07-26 minio-init exit 127.

그래서 소스·서명자재는 `docker cp` 로 넣고 산출물도 `docker cp` 로 꺼낸다(둘 다 클라이언트 측
스트리밍이라 호스트 경로 해석이 끼어들지 않는다). gradle·pub 캐시만 **named volume** 으로
붙인다 — 이건 데몬이 관리하므로 DooD 에서도 안전하다.

### debug 서명 폴백은 CI 에서 금지한다

로컬에서 `flutter run --release` 를 막지 않으려고 keystore 가 없으면 debug 로 폴백한다.
그러나 CI 는 `REQUIRE_RELEASE_SIGNING=true` 로 돌아 두 겹으로 막는다:

1. `build.gradle.kts` 의 `preReleaseBuild` 가드 — 키가 없으면 빌드 자체를 세운다
2. `ci-build.sh` 의 `keytool -printcert -jarfile` — **나온 AAB 를 실제로 열어** 인증서 주체가
   `CN=Android Debug` 면 실패시킨다

"설정은 켜져 있는데 실제로는 동작하지 않는" 상태를 여러 번 겪은 저장소라, **존재 검사와
동작 검사를 따로** 둔다.

### 호스트 잔재

`docker cp` 는 `.gitignore` 를 모른다 — 작업 트리를 통째로 가져온다.
특히 `android/local.properties` 에는 **호스트의** `flutter.sdk` 경로가 박혀 있어 컨테이너 안에서는
없는 경로를 가리킨다. `ci-build.sh` 가 시작할 때 이것과 `build/`·`.dart_tool` 을 지운다.

---

## 아직 안 한 것

- **Play Console 업로드 자동화** — 계정·서비스 계정 키가 필요하다. 별도 이슈.
- **iOS(IPA)** — macOS 빌더가 필요해 이 서버에서 불가능하다.
- **versionName 정책** — 지금은 `pubspec.yaml` 의 `1.0.0` 고정. 태그 연동은 미정.
