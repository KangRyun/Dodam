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

### 실기기 스모크 — **제출 전 필수** (S15P11B209-632)

APK 는 설치 파일이라 바로 얹어볼 수 있다. **제출할 바로 그 APK 로** 한 번 훑는다(10~15분):

```bash
adb install -r build-artifacts/app-release.apk
```

체크리스트: **`docs/출시/RC-스모크-체크리스트.md`**

★ 표시(아동 가드레일) 항목이 하나라도 어긋나면 **제출하지 않는다.** 결과는 그 문서 §7 표에
기록해 Jira 에 남긴다 — "이상 없음"도 기록이다.

---

## 6. 원스토어 개발자센터 등록 절차 (2026-08-02 실등록 기준 상세)

> 실제 등록을 진행하며 확인한 콘솔 흐름이다. 메뉴 명칭은 개편에 따라 다를 수 있으나
> STEP 골격은 유지된다. 요건 근거: 개발자센터 공식 가이드(gitbook) FAQ · targetSdk 공지.

### 6-0. 우리 APK 의 요건 충족 (사전 검증 완료)

| 요건 | 우리 상태 |
|---|---|
| targetSdkVersion ≥ 23 (2023-09~) | ✅ Flutter 기본(34+), minSdk 24 |
| versionCode 이전보다 높게 | ✅ **1238** — `aapt dump badging` 으로 APK 실물에서 추출한 값. 커밋 수 기반이라 다음 빌드는 자동으로 더 크다 |
| 패키지명 중복 불가 | `com.dodam.app` — 등록 시 중복확인 버튼으로 확정. **한 번 정하면 영구 고정** |
| 권한 최소화 (과도 권한 = 공식 반려 사유) | 4종뿐: INTERNET·CAMERA·RECORD_AUDIO·POST_NOTIFICATIONS — 전부 실기능 대응 |

### 6-1. 콘솔 STEP 흐름

1. https://dev.onestore.co.kr **무료 가입** (무료 앱은 정산정보·서류 불필요)
2. **[APPS] → [신규 상품 등록]** — 상품 제목(도담) + 패키지네임 `com.dodam.app` 중복확인
3. **STEP1 기본정보** — 외부결제 미사용 · 검색용 제목 · 카테고리(라이프스타일/교육) ·
   이용등급 **전체이용가** · 위치정보 **미전송**(위치 권한 없음, 매니페스트 확인됨) ·
   **개인정보 URL `https://i15b209.p.ssafy.io/legal/privacy/`** (383 웹 전환 때 살려둔 정적 페이지)
4. **STEP2 판매정보** — 규격: 한줄설명 100자 · 상품설명 3,000자 · 그래픽 1024×578 ·
   아이콘 512×512 · 스크린샷 2~8장 · 키워드. **확정 카피와 자산은 6-2·6-3절.**
5. **STEP3 가격** — 무료 체크 (정산정보 생략됨)
6. **STEP4 라이선스 관리** — 기본값 통과
7. **STEP5 신규 바이너리** — 유형 **APK** 선택 → `build-artifacts/app-release.apk` 업로드.
   ★ APK 경로에는 **서명키 등록 화면이 원래 없다** — 이미 서명된 파일을 그대로 올리는
   것이고, "서명키 위탁" 옵션은 AAB 전용이다. 없다고 찾아 헤매지 말 것(2026-08-01 실경험).
   업로드 후 콘솔 표시 versionCode **1238** 대조 · **지원 단말 최소 1개** 지정(필수).
8. **STEP6 In-App** — 인앱 상품 없음, 생략
9. **STEP7 검증요청** — 판매 옵션 "즉시 적용" 권장. 심사는 통상 1~2시간(공식 보장치 아님),
   결과 이메일 통보, `검증중 → 검증완료 → 판매중`

⚠️ 반려 주의(공식 사유 + 우리 특이점): 필수정보 미비 · 패키지명 중복 · **과도한 권한** ·
**청소년 보호 기준**. 아동 데이터 앱이므로 상품설명·고지의 수집 항목(그림·음성·대화)을
처리방침 문서와 **같은 표현**으로 쓰고, **"검사·진단·치료" 단어는 절대 쓰지 않는다**
(07/17 방향 전환 + 의료성 주장 반려 리스크).

### 6-2. 확정 카피 (그대로 사용)

- **한줄설명**: "아이가 그린 그림과 나눈 이야기로, 아이 마음을 이해하는 실마리를 전해 드려요."
- **키워드**: 아이 마음, 아동 그림, 그림일기, 감정표현, 육아, 부모, 자녀 대화, 미술놀이,
  관찰 리포트, AI 그림친구
- **상품설명 전문**: 인트로 → "도담과 함께하는 방법" 3단계 → **"도담의 약속"(진단 아님 고지 —
  9절, 처리방침과 표현 일치)** → 추천 대상 → **권한 4종 용도 선제 고지**(반려 예방).
  전문은 등록 이력 참조 — 랜딩 페이지(`frontend/web/src/app/page.tsx`)와 동일 톤·문구.

### 6-3. 스토어 그래픽 자산

| 파일 | 규격 | 내용 |
|---|---|---|
| `build-artifacts/store/feature-graphic-1024x578.png` | 1024×578 | "도담" 로고 + 태그라인 + 도담이 캐릭터 + 두들 배경 |
| `build-artifacts/store/icon-512.png` | 512×512 | brandYellow(#F2D765) 풀블리드 + 도담이 중앙 |
| `build-artifacts/store/compose.py` | — | **재생성 스크립트.** 문구·배치 수정 후 python:3-alpine + pillow 로 재실행 |

- 재료는 전부 앱 실자산 — `assets/characters/dodami_yellow.png`(투명 배경)·두들 4종,
  팔레트는 `app_colors.dart` 토큰, 폰트는 번들 NanumSquareNeo. 스토어→웹→앱 첫인상 통일.
- ⚠️ `dodami.png`(파랑 스카프 1254²)는 **불투명 흰 배경**이라 합성용이 아니다.
- **스크린샷 구성안(6장, 사용 흐름 순)**: 아동 홈 → 캔버스(가로) → 캐릭터 대화(가로) →
  감정 선택 → 관찰 리포트 → 보호자 홈. 상단 캡션 띠 프레임 권장, 가로 캡처는 세로 프레임에
  기기 목업으로. **캡처는 반드시 데모 데이터** — 실제 아동 그림·이름·리포트 절대 금지(9절).
  리포트 장은 하단 AI 한계 고지가 보이게 찍는다.

### 6-4. 기타

- **푸시(FCM)** — 대부분의 국내 안드로이드 기기에는 Play 서비스가 있어 원스토어 배포본에서도
  FCM 이 동작한다. Play 서비스 없는 특수 기기만 미수신 — 등록에는 영향 없다.
- 파일 반출: 서버에서 `scp "kr@i15b209.p.ssafy.io:~/S15P11B209/build-artifacts/store/*.png" .`

---

## 7. 아직 안 한 것

- **설치 아이콘이 Flutter 기본값이다** (2026-08-02 발견). `ic_launcher.png`(1.4KB)가 기본
  아이콘 그대로라, 스토어 대표 아이콘(6-3)과 달리 **설치 후 홈 화면에는 Flutter 로고**가 뜬다.
  `icon-512.png` 디자인으로 런처 아이콘을 교체하고 재빌드(versionCode 자동 증가 → 재업로드)하는
  후속 작업이 필요하다.
- **스크린샷 미캡처.** 6-3 구성안대로 에뮬레이터/실기기에서 데모 데이터로 캡처해야 한다.
- **Jenkins 자동화 없음.** README 5절의 `BUILD_ANDROID_AAB` 스테이지는 AAB 전용이다.
  APK 도 CI 에서 뽑으려면 Jenkinsfile 에 스테이지를 추가해야 한다(호스트 실행은 지금도 된다).
- **원스토어 업로드 API 자동화 없음.** 수동 업로드 전제.
- **Play 와 병행 배포 시**: Play=AAB(`build-aab.sh`), 원스토어=APK(`build-apk.sh`).
  같은 keystore·같은 버전을 공유하므로 두 스토어에 같은 versionCode 를 각각 올려도 무방하다.
