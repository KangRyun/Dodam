# infra/secrets — 런타임 비밀 파일 (git 비추적)

이 폴더의 실제 비밀 파일(`*.json` 등)은 **`.gitignore`(`secrets/`)로 무시**된다. 이 `README.md`만 커밋된다.
compose(`docker-compose.yml`)의 top-level `secrets:` 가 여기 파일을 읽어 컨테이너에 read-only로 주입한다.

## fcm-service-account.json — FCM 푸시 발송용 (S15P11B209-619)

백엔드가 Firebase로 푸시를 보낼 때 인증하는 **Service Account 개인키**. Firebase 콘솔(616)에서 발급.

발급 위치: Firebase 콘솔 → ⚙️ 프로젝트 설정 → **서비스 계정** → `새 비공개 키 생성` → JSON 다운로드.

### 활성화 절차 (616 발급 + BE 556 머지 후)

1. 발급받은 JSON을 이 폴더에 둔다: `infra/secrets/fcm-service-account.json`
2. `infra/.env` 에 두 줄 추가:
   ```
   APP_PUSH_FCM_ENABLED=true
   FCM_CREDENTIALS_HOST_PATH=./secrets/fcm-service-account.json
   ```
3. 재배포. 컨테이너 내부 `/run/secrets/fcm-service-account.json` 로 마운트된다.

미설정 상태(기본)에서는 소스가 `/dev/null`(빈 파일)이고 `APP_PUSH_FCM_ENABLED=false` 라
backend 가 이 파일을 읽지 않고 정상 부팅한다.

### ⚠️ 가드레일

- 이 JSON은 **절대 커밋 금지** (개인키 포함). 유출 시 즉시 콘솔에서 키 폐기·재발급.
- 푸시 페이로드에 **아동 원본(그림·음성·대화) 금지** — "분석 완료됐어요" + 딥링크 식별자만 (BE 556 소관).
