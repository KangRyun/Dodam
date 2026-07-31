# 원스토어(ONE Store) 등록 런북

> **목적** — 원스토어 등록용 릴리스 APK 를 굽고 검증해 개발자센터에 올리기까지의 절차.
> 코드(빌드 경로)는 이 저장소에 있고, 남은 일은 **실서명 APK 를 뽑아 업로드하는 것**이다.
>
> **지라 키** — `S15P11B209-765` [INFRA][P0] 원스토어 Release APK 빌드 Pipeline 구성.
> ⚠️ 이 문서의 초안이 적고 있던 `S15P11B209-651` 은 **다른 이슈**다
> (`fix/S15P11B209-651-google-signin-logging`, Provider SDK 진단 로깅 · develop 머지 완료).

---

## 0. 한 줄 요약

- **패키지 이름**: `com.dodam.app` ← 원스토어 개발자센터에 이걸로 등록 (한 번 정하면 못 바꾼다)
- **산출물**: 릴리스 키로 서명된 `build-artifacts/app-release.apk`
- **빌드 명령**: `infra/mobile/build-apk.sh` (4번)
- **빌드 머신**: `~/dodam-secrets/` 가 있는 곳. **현재 EC2 서버(i15b209)가 그 머신이다** —
  AAB 를 여기서 구웠고 keystore·oauth 가 여기 있다. 별도 노트북으로 옮길 필요가 없다.
- **왜 APK 인가**: 원스토어에는 Play App Signing(재서명 위탁)이 없어 **내가 서명한 키가 곧 앱 신원**.
  APK 는 내 릴리스 키로 서명한 그대로 올라가고, 그 자체가 설치 파일이라 `adb install` 로 검증된다.

---

## 1. 빌드 경로 (저장소에 있는 것)

| 파일 | 역할 |
|---|---|
| `infra/mobile/build-apk.sh` | 원스토어용 APK 진입점. `BUILD_FORMAT=apk` 만 정하는 얇은 래퍼 |
| `infra/mobile/build-aab.sh` | Play 용 AAB 진입점. 동일 구조(`BUILD_FORMAT=appbundle`) |
| `infra/mobile/build-android.sh` | **공용 코어** — 컨테이너 수명·시크릿 주입·버전 산출·산출물 회수 |
| `infra/mobile/ci-build.sh` | 컨테이너 안 빌드 절차. `BUILD_FORMAT` 으로 형식·검증 도구를 가른다 |
| `frontend/mobile/android/app/build.gradle.kts` | (기존) `applicationId = "com.dodam.app"`, 릴리스 `signingConfig` |

> **AAB 경로는 동작이 그대로다.** `build-aab.sh` 의 이름·사용법·환경변수는 바뀌지 않았고
> 내부 구현만 `build-android.sh` 로 옮겼다. Jenkins 의 `BUILD_ANDROID_AAB` 스테이지도 무변경.
> 두 형식이 **같은 코드**를 타므로 한쪽만 고쳐져 갈라지는 일이 없다.

---

## 2. 사전 준비물

`build-aab.sh` 와 **완전히 동일한** 3종. AAB 를 한 번이라도 구웠으면 이미 갖춰져 있다.

```
~/dodam-secrets/
├── upload-keystore.jks   # 릴리스 서명 키 (README 2절로 생성)
├── key.properties        # storeFile/storePassword/keyAlias/keyPassword
└── oauth.env             # KAKAO_NATIVE_APP_KEY 등 5개
```

빌더 이미지:

```bash
docker image inspect dodam-flutter-builder:3.44.7 >/dev/null 2>&1 \
  || docker build -t dodam-flutter-builder:3.44.7 infra/mobile
```

> ⚠️ **keystore 백업이 곧 앱의 수명이다.** 원스토어는 이 키를 잃으면 **이후 업데이트를 영원히
> 못 올린다**(구글처럼 대신 보관해 주지 않는다). keystore + 비밀번호를 팀 비밀 저장소와
> 오프라인 매체에 이중 보관할 것.
>
> ⚠️ `docker image prune -af` / `docker system prune -a` 는 이 빌더 이미지를 지운다
> (2026-07-28 실제 소실, 재빌드 10~20분). 정리 명령을 쓸 때 확인할 것.

---

## 3. 빌드 전 확인

```bash
ls -l ~/dodam-secrets/upload-keystore.jks ~/dodam-secrets/key.properties ~/dodam-secrets/oauth.env

infra/mobile/app-version.sh
#  → BUILD_NAME=1.0.0
#    BUILD_NUMBER=<커밋 수>   ← 이전 업로드보다 커야 업데이트가 승인된다
```

---

## 4. APK 빌드

```bash
KEYSTORE_FILE=~/dodam-secrets/upload-keystore.jks \
KEY_PROPERTIES_FILE=~/dodam-secrets/key.properties \
OAUTH_ENV_FILE=~/dodam-secrets/oauth.env \
infra/mobile/build-apk.sh
```

- 산출물: `build-artifacts/app-release.apk` + `build-artifacts/signing-report.txt`
- 첫 회는 gradle 배포판·의존성을 내려받느라 오래 걸린다(캐시가 named volume 에 남아 2회차부터 빠르다).
- 메모리 관문(`--need 7168`)이 앞에서 막으면 무거운 프로세스를 내리고 재실행한다.
  **관문을 끄지 말 것** — 2026-07-28 에 이 빌드로 호스트가 응답 불능이 됐다.

> ⚠️ AAB 와 APK 가 `signing-report.txt` **같은 파일**에 쓴다. 연달아 구우면 나중 것이 덮어쓴다.

---

## 5. 서명 검증 (반드시 확인)

```bash
cat build-artifacts/signing-report.txt
```

- ✅ **정상**: `Signer #1 certificate DN: CN=<keytool 로 넣은 이름>, ...`
- ❌ **실패**: `CN=Android Debug` → debug 키로 서명된 것. 원스토어 업로드 불가.
  `key.properties` 가 실제로 적용됐는지, `build.gradle.kts` 의 release `signingConfig` 배선을 확인.

> `ci-build.sh` 가 컨테이너 안에서 이미 이 검사를 하고 `CN=Android Debug` 면 빌드를 실패시킨다.
> 그래도 최종 산출물을 눈으로 한 번 더 본다 — "검사가 돌았다"와 "검사가 옳았다"는 다르다.

**★ APK 는 `keytool` 로 검증하지 않는다.** 최신 APK 는 v2/v3 서명 스킴만 쓸 수 있고 그때는
v1(JAR) 서명 블록이 없어서, `keytool -printcert -jarfile` 이 **제대로 서명된 APK 를
"서명되지 않았다"고 잘못 판정한다.** 그래서 APK 경로는 `apksigner verify --print-certs` 를 쓴다.
`apksigner` 는 build-tools 안에 있고 PATH 에 없어(이미지 PATH 에는 cmdline-tools·platform-tools 만
있다) 스크립트가 설치된 것 중 가장 높은 버전을 직접 찾는다.

(선택) 실기기 스모크 — APK 는 설치 파일이라 바로 얹어볼 수 있다:

```bash
adb install -r build-artifacts/app-release.apk
```

---

## 6. 원스토어 개발자센터 등록 체크리스트

1. **앱 등록** → 패키지 이름 `com.dodam.app` (한 번 정하면 못 바꾼다)
2. **APK 업로드** → `build-artifacts/app-release.apk` (versionCode 가 이전보다 커야 한다)
3. **콘텐츠/등급·개인정보·권한 고지** 등 스토어 정책 항목 작성
   - ⚠️ 이 앱은 **아동의 그림·음성·대화**를 다룬다. 개인정보 처리방침·수집 항목 고지를
     CLAUDE.md 9절 가드레일과 어긋나지 않게 쓸 것.
4. **푸시(FCM)** — 앱은 FCM 을 쓴다(`google-services.json`). 대부분의 국내 안드로이드 기기에는
   Google Play 서비스가 있어 원스토어 배포본에서도 FCM 이 동작한다. Play 서비스가 없는 특수
   기기만 푸시 미수신 — 등록 자체에는 영향 없다.
5. **심사 제출**

---

## 7. 아직 안 한 것

- **Jenkins 자동화 없음.** README 5절의 `BUILD_ANDROID_AAB` 스테이지는 AAB 전용이다.
  APK 도 CI 에서 뽑으려면 Jenkinsfile 에 스테이지를 추가해야 한다(호스트 실행은 지금도 된다).
- **원스토어 업로드 API 자동화 없음.** 수동 업로드 전제.
- **Play 와 병행 배포 시**: Play=AAB(`build-aab.sh`), 원스토어=APK(`build-apk.sh`).
  같은 keystore·같은 버전을 공유하므로 두 스토어에 같은 versionCode 를 각각 올려도 무방하다.
