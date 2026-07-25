# infra/secrets — 런타임 비밀 파일 (git 비추적)

이 폴더의 실제 비밀 파일(`*.json` 등)은 **`.gitignore`(`secrets/`)로 무시**된다. 이 `README.md`만 커밋된다.
compose(`docker-compose.yml`)의 top-level `secrets:` 가 파일을 읽어 컨테이너에 read-only로 주입한다.

## ⚠️ 배포 서버의 실제 파일은 이 폴더가 아니라 `/etc/dodam/secrets/` 에 둔다

Jenkins 파이프라인은 **Jenkins 컨테이너 안에서 호스트 도커 데몬을 호출**한다(Docker-out-of-Docker).
compose의 상대경로(`./secrets/...`)는 Jenkins 컨테이너 안 워크스페이스 기준으로 해석되지만
실제 마운트는 호스트 데몬이 수행한다 → 호스트에 없는 경로엔 **빈 디렉터리가 붙고 비밀 파일이 사라진다.**

같은 함정으로 실제 장애가 두 번 났다: 2026-07-22 nginx 빈 conf, 2026-07-26 minio-init exit 127(서비스 전면 중단 2회, S15P11B209-641).
그래서 **호스트 마운트 소스는 워크스페이스 밖 절대경로만 사용한다.** 파이프라인의 `Compose Preflight` ·
`Secrets Preflight` 스테이지가 상대경로를 발견하면 빌드를 실패시킨다.

이 폴더는 **로컬 개발용**(호스트에서 직접 `docker compose` 를 돌릴 때)이다.

경로를 `/etc/dodam/` 아래로 두는 이유: 이 서버의 운영 비밀 파일은 이미
`/etc/dodam/backup-passphrase`(DB 백업 암호, S15P11B209-353)를 쓰고 있다. 같은 규칙에 맞춰
**서버 운영 비밀 = `/etc/dodam/`** 로 통일한다 — 위치가 갈리면 백업·권한 점검에서 빠뜨리기 쉽다.

## fcm-service-account.json — FCM 푸시 발송용 (S15P11B209-619)

백엔드가 Firebase로 푸시를 보낼 때 인증하는 **Service Account 개인키**. Firebase 콘솔(616)에서 발급.

발급 위치: Firebase 콘솔 → ⚙️ 프로젝트 설정 → **서비스 계정** → `새 비공개 키 생성` → JSON 다운로드.

### 활성화 절차 (616 발급 + BE 556 머지 후)

**배포 서버(EC2):**

1. 워크스페이스 밖 경로에 폴더를 만들고 JSON을 둔다 (권한은 소유자만 읽기):
   ```
   sudo mkdir -p /etc/dodam/secrets
   sudo install -m 600 -o root -g root fcm-service-account.json /etc/dodam/secrets/
   ```
2. Jenkins 크리덴셜 `dodam-env` 에 두 줄 추가 — **절대경로**로 (교체가 아니라 기존 키 + 신규 키 병합, S15P11B209-386):
   ```
   APP_PUSH_FCM_ENABLED=true
   FCM_CREDENTIALS_HOST_PATH=/etc/dodam/secrets/fcm-service-account.json
   ```
3. 재배포. 컨테이너 내부 `/run/secrets/fcm-service-account.json` 로 마운트된다.

**로컬 개발(호스트에서 직접 compose 실행):** JSON을 이 폴더에 두고 `infra/.env` 에
`FCM_CREDENTIALS_HOST_PATH=/home/<user>/S15P11B209/infra/secrets/fcm-service-account.json` 처럼
**절대경로**로 지정한다(상대경로는 preflight가 막는다).

미설정 상태(기본)에서는 소스가 `/dev/null`(빈 파일)이고 `APP_PUSH_FCM_ENABLED=false` 라
backend 가 이 파일을 읽지 않고 정상 부팅한다.

### ⚠️ 가드레일

- 이 JSON은 **절대 커밋 금지** (개인키 포함). 유출 시 즉시 콘솔에서 키 폐기·재발급.
- 푸시 페이로드에 **아동 원본(그림·음성·대화) 금지** — "분석 완료됐어요" + 딥링크 식별자만 (BE 556 소관).
