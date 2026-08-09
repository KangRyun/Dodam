# Google Play 데이터 안전(Data safety) 선언 초안

> **상태: 초안.** 콘솔에 입력하기 전에 3절(결정 필요)·4절(선언 전 해소)을 팀에서 확정해야 한다.
> 조사 기준: 2026-07-29, `develop` `b8424c3` 코드 실측. 추정이 아니라 코드·스키마에서 뽑았다.
> 관련 이슈: S15P11B209-627(스토어 등록 자산) · 626(Play 업로드) · 373(파일 수명주기)

---

## 1. 앱 기본 정보

| 항목 | 값 | 확인처 |
|---|---|---|
| 패키지명 | `com.dodam.app` | `android/app/build.gradle.kts` |
| targetSdk / compileSdk / minSdk | 36 / 36 / 24 | Flutter 3.44.7 기본값 |
| 개인정보처리방침 URL | `https://i15b209.p.ssafy.io/legal/privacy` | 200 응답 확인 |
| 이용약관 URL | `https://i15b209.p.ssafy.io/legal/terms` | 200 응답 확인 |
| 계정 삭제 요청 URL | **없음** | 4절 참조 |
| 업로드 키 | RSA 4096 · SHA384withRSA · 2053년까지 유효 | `signing-report.txt` |

---

## 2. 수집하는 데이터

Play 콘솔의 데이터 유형 분류에 맞춰 정리했다. "동의 코드"는 우리 `consent_terms` 테이블의 항목이다.

| Play 데이터 유형 | 실제 수집 항목 | 저장 위치 | 목적 | 필수/선택 (동의 코드) |
|---|---|---|---|---|
| 개인 정보 › 이름 | 보호자 닉네임, **아동 닉네임** | MySQL `users.nickname` · `children.nickname` | 앱 기능 | 필수 / 선택(`CHILD_PERSONAL_INFO`) |
| 개인 정보 › 이메일 | 계정 이메일, 소셜 제공자 이메일 | MySQL `users.email` · `auth_accounts.provider_email` | 계정 관리 | 필수(`SERVICE_TOS`) |
| 개인 정보 › 기타 | **아동 생년월일** | MySQL `children.birth_date` | 연령별 질문 난이도 산정 | 선택(`CHILD_PERSONAL_INFO`) |
| 사진 및 동영상 › 사진 | **아동이 그린 그림 이미지** | MinIO `dodam/images/` | 앱 기능 · 분석 | 선택(`DRAWING_ANALYSIS`) |
| 오디오 › 음성 녹음 | **아동 음성 답변** | MinIO `dodam/audio/` | 앱 기능(STT) | 선택(`VOICE_PROCESSING`) |
| 앱 활동 › 기타 사용자 생성 콘텐츠 | 대화 로그(질문·답변 텍스트), 감정 선택, 획(스트로크) 이벤트 | MySQL `conversation_messages` · `drawing_session_emotions` · `stroke_events` | 앱 기능 · 분석 | 선택(`DRAWING_ANALYSIS`) |
| 앱 활동 › 기타 사용자 생성 콘텐츠 | 커뮤니티 게시글·댓글 | MySQL `community_posts` · `comments` | 앱 기능 | 필수(`SERVICE_TOS`) |
| 기기 또는 기타 ID | 기기 식별자, 푸시 토큰 | MySQL `notification_device_tokens` | 알림 발송 | 선택(`MARKETING`) |
| 앱 정보 및 성능 | 앱 버전 | MySQL `notification_device_tokens.app_version` | 알림 호환성 | 선택 |

**파생 데이터**(선언 대상 아님 — 원본에서 생성): 분석 결과(`analyses` 계열), 관찰 리포트(`reports`), TTS 캐시(MinIO `dodam/tts-cache/`), 동의 증빙(MinIO `dodam/evidences/`).

### 보안 관련 (긍정 항목)

- **전송 중 암호화**: 전 구간 HTTPS(TLS). "예"로 선언 가능
- **푸시 토큰은 저장 시 암호화**: `token_ciphertext` + 조회용 `token_hash`(SHA-256) 분리 저장
- **동의 버전 관리**: `consent_terms`에 `version`·`effective_at` 보유, 필수/선택 분리(7종)

---

## 3. 팀이 결정해야 할 항목 (3건)

### 3-1. 대상 연령대 — 가장 무거운 결정

계정 주체는 보호자지만 **아동 모드에서 아이가 직접 사용**한다. "만 13세 미만 포함"으로 선언하면
Google Play **Families 정책**이 통째로 적용된다 — 광고·SDK 제한, 콘텐츠 등급 재산정,
데이터 안전 심사 강화. 잘못 선언하면 심사 반려 또는 사후 정정 대상이다.

판단 근거가 될 사실: 아동 프로필에 생년월일을 수집하고(`children.birth_date`),
질문 난이도를 연령별로 조절하며(`question_difficulty`), 아동 전용 전체화면 모드가 존재한다.

### 3-2. 제3자 전송을 "공유"로 신고할지

그림 이미지·음성·대화 텍스트가 **외부로 나간다.**

```
앱 → 백엔드 → AI 서버 → GMS(https://gms.ssafy.io/gmsapi/api.openai.com/v1) → OpenAI
```

Google의 데이터 안전 정의상 **"위탁 처리하는 서비스 제공업체로의 전송"은 '공유'에서 제외**되지만,
GMS/OpenAI가 위탁 처리자 관계로 성립하는지 확인이 필요하다. 제외되더라도 **수집 자체는 선언 대상**이다.
개인정보처리방침에 이 전송 경로가 명시돼 있는지도 함께 대조할 것.

### 3-3. `AI_TRAINING` 동의를 실제로 사용하는지

`consent_terms`에 'AI 학습 데이터 활용'(선택) 항목이 있다. 실제로 아동 데이터를 학습에 쓴다면
데이터 안전의 목적에 '앱 기능' 외 항목을 추가해야 한다. **현재 코드에서 학습 파이프라인이
이 동의를 참조하는 곳은 확인되지 않았다** — 동의만 받고 쓰지 않는 상태인지 확정 필요.

---

## 4. 선언 전에 반드시 해소해야 할 것 (2건)

지금 상태로 "데이터 삭제 요청 가능"에 체크하면 **사실과 다른 신고**가 된다.

### 4-1. ⚠️ 회원 탈퇴가 아동 데이터를 지우지 않는다 — 가드레일 위반 소지

`UserDeletionService.delete()`는 `userRepository.deleteById(userId)` **한 줄**이다.
스키마상 연쇄 삭제 범위는 다음과 같다.

| 대상 | 동작 | 결과 |
|---|---|---|
| `auth_accounts` · `refresh_tokens` · `notifications` · `post_likes` | CASCADE | 삭제됨 |
| `guardian_child_relations` | CASCADE | **관계만** 삭제됨 |
| **`children`** | FK 없음 | **남는다 — 보호자와 끊긴 고아 레코드** |
| `drawing_sessions` · 대화·분석·리포트 | `child_id`가 RESTRICT | **남는다** |
| MinIO 그림 이미지·음성 파일 | 삭제 로직 없음 | **남는다** |
| `community_posts` · `comments` · `audit_logs` | SET NULL | 익명화되어 남음 |
| `expert_profiles` | **RESTRICT** | 전문가 계정은 **탈퇴 자체가 실패**한다 |

즉 탈퇴 후 아동 프로필·그림·음성·대화가 **소유자만 사라진 채 전부 남는다.**
CLAUDE.md 9절의 *"회원 탈퇴 시 아동 데이터 함께 삭제"* 원칙과 어긋난다.

→ **별도 이슈로 처리 필요.** 이건 스토어 선언 이전에 서비스 요건 자체의 문제다.

### 4-2. 계정 삭제 요청 URL이 없다

Play는 계정 생성이 가능한 앱에 대해 **앱 내 삭제 경로 + 웹에서 접근 가능한 삭제 요청 URL**을 함께 요구한다.

- 앱 내 경로: `DELETE /api/v1/users/me` — **있음**
- 웹 URL: **없음.** `/legal/delete`·`/legal/account-deletion` 등은 200을 주지만
  **랜딩 페이지를 그대로 돌려주는 catch-all**이다(제목이 `도담 — 아이의 마음을 그림으로 만나요`).
  존재하는 것처럼 보이지만 삭제 안내 페이지가 아니다

→ `infra/nginx/html/legal/`에 `privacy`·`terms`와 같은 방식으로 삭제 안내 페이지를 추가하면 된다.
   단, 4-1이 해결되기 전에는 "요청하면 지웁니다"라고 쓸 수 없다.

---

## 5. 콘솔 입력 순서 (권장)

1. 앱 등록(`com.dodam.app`) 및 업로드 키 지문 확인
2. 서비스 계정 JSON 발급 → 권한 부여 (**전파 지연이 있어 가장 먼저 시작**)
3. 4-1·4-2 해소
4. 3절 3건 결정
5. 앱 콘텐츠 선언(대상 연령 · 데이터 안전 · 콘텐츠 등급 · 정책 URL)
6. 내부 테스트 트랙 업로드

---

## 참고

- 저장소 매핑: `docs/database/저장소-아키텍처.md`
- 동의 항목 시드: `backend/src/main/resources/db/migration/V17__seed_consent_terms.sql`
- 가드레일 원칙: `CLAUDE.md` 9절
