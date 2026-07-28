# MinIO 스토리지 컷오버 런북

> Jira: `S15P11B209-369` (MinIO 구성) · 관련 `370`(BE S3 전환, 완료)·`371`(그림 조회 API, 완료)·`374`(백업)
> 실행일: **2026-07-28** · 담당: 이강륜
> 설계 근거: `docs/database/저장소-아키텍처.md`

## 0. 무엇을 한 작업인가

아동 그림·음성 파일을 **백엔드 컨테이너 볼륨 → MinIO 오브젝트 스토리지**로 옮기고,
백엔드가 MinIO 를 쓰도록 스위치를 켠 작업.

전환 전에는 파일이 `dodam-backend` 컨테이너의 `backend-storage` 볼륨에만 있었다.
컨테이너를 지우면 아이들 그림이 함께 사라지고, AI 서비스도 파일에 접근할 수 없었다.

**코드는 이미 준비돼 있었다** — `S3ImageStorage`/`S3AudioStorage`, `ImageStorage.read()`,
그림 조회 API(`DrawingAssetFileController`)까지 370·371 에서 완료. 남은 것은
**파일 이관 + 스위치 + 검증**뿐이었다.

## 1. 사전 확인 (여기가 틀리면 전부 헛일)

### key 정합성 — DB 변경 0건의 근거

```
DB  drawing_assets.storage_key : 2026/07/26/fcd0c494-….png      (프리픽스 없음)
BE  S3ImageStorage.objectKey() : prefix + "/" + storage_key
                                → images/2026/07/26/fcd0c494-….png
로컬 실제 파일                  : /app/storage/images/2026/07/26/fcd0c494-….png
                                            └──────── 여기부터 정확히 대응 ────────┘
```

**`/app/storage/images/` 아래를 통째로 `dodam/images/` 로 복사하면 key 가 그대로 맞는다.**
그래서 DB 를 한 줄도 고칠 필요가 없다. 이 대응이 깨져 있으면 이관해도 못 읽는다 — 먼저 확인할 것.

### MinIO 계정·버킷

```bash
docker exec dodam-minio sh -c \
  'mc alias set m http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null &&
   mc admin user list m && mc ls m/'
# 기대: dodam-be-rw · dodam-ai-ro 계정, dodam 버킷
```

## 2. 실행 절차

컨테이너 이름·볼륨명·네트워크명은 compose 프로젝트 접두사(`dodam_`)가 붙는다.
`docker volume ls` / `docker network ls` 로 실제 이름을 먼저 확인할 것.

### A. 원본 백업 (필수 — 1주 보존)

```bash
mkdir -p /home/kr/backups
docker run --rm -v dodam_backend-storage:/data:ro -v /home/kr/backups:/out alpine \
  tar czf /out/backend-storage-$(date +%Y%m%d).tar.gz -C /data .
tar tzf /home/kr/backups/backend-storage-$(date +%Y%m%d).tar.gz | grep -c '\.png$'
```

### B. 이관

`mc` 컨테이너에 백엔드 볼륨을 **읽기 전용**으로 붙여 복사한다.
(백엔드 컨테이너엔 `mc` 가 없고, MinIO 컨테이너엔 파일이 없다)

```bash
set -a; . infra/.env; set +a
docker run --rm --network dodam_dodam-net -v dodam_backend-storage:/data:ro \
  -e U="$MINIO_BE_USER" -e P="$MINIO_BE_PASSWORD" \
  --entrypoint sh minio/mc:latest -c '
    mc alias set m http://minio:9000 "$U" "$P" >/dev/null &&
    mc cp --recursive /data/images/ m/dodam/images/'
```

오디오 파일이 있으면 `audio/` 도 같은 방식으로.

### C. 대조 — 개수·크기·md5 전수

⚠️ **`minio/mc` 이미지에는 `find`·`awk`·`md5sum` 이 없다.** 그 안에서 검증 루프를 돌리면
명령이 조용히 실패하고 "전부 일치" 같은 **거짓 통과**가 찍힌다(2026-07-28 실제로 겪음).
로컬 목록은 `alpine` 에서, 원격 목록은 `mc ls --json` 의 etag 로 뽑아 **호스트에서 대조**한다.

```bash
# 로컬: key md5 size
docker run --rm -v dodam_backend-storage:/data:ro alpine sh -c \
  'cd /data/images && find . -type f | sed "s|^\./||" | sort | while read -r k; do
     printf "%s %s %s\n" "$k" "$(md5sum "$k" | cut -d" " -f1)" "$(stat -c %s "$k")"; done' > /tmp/local.txt

# 원격: mc ls --json 의 etag(단일파트 업로드는 etag == md5)
docker run --rm --network dodam_dodam-net -e U="$MINIO_BE_USER" -e P="$MINIO_BE_PASSWORD" \
  --entrypoint sh minio/mc:latest -c \
  'mc alias set m http://minio:9000 "$U" "$P" >/dev/null && mc ls --recursive --json m/dodam/images/' \
  | jq -r '[.key, (.etag|gsub("\"";"")), (.size|tostring)] | join(" ")' | sort > /tmp/remote.txt

diff /tmp/local.txt /tmp/remote.txt && echo "일치"
```

**`diff` 가 비어야만 다음 단계로 간다.**

> A~C 는 실행 중인 서비스를 건드리지 않는다. MinIO 에 사본이 하나 더 생길 뿐이다.

### D~E. 스위치 + 백엔드만 재생성

⚠️ **디스크 `.env` 만 고치면 다음 배포에서 원복된다.** 배포 정본은 **Jenkins Credential
`dodam-env`** 이고, 파이프라인이 `docker compose --env-file <dodam-env>` 로 주입한다.
디스크 `infra/.env` 는 수동 배포에서만 쓰이는 사본이다(`infra/.env.example` 머리말 참조).

**반드시 둘 다 바꾼다:**

1. **Jenkins Credential `dodam-env`** 의 `STORAGE_MODE=s3` — Jenkins UI 에서 수정
2. 디스크 `infra/.env` — 수동 배포·즉시 반영용

```bash
cp infra/.env infra/.env.bak-$(date +%Y%m%d-%H%M)
sed -i 's/^STORAGE_MODE=local$/STORAGE_MODE=s3/' infra/.env
cd infra && docker compose up -d backend
```

> 2026-07-28: 디스크 `.env` 만 고치고 끝냈다가, 그날 develop 머지로 Jenkins 배포가 돌면서
> `STORAGE_MODE=local` 로 되돌아갔다. 그 사이 저장된 파일 8개가 MinIO 가 아닌 로컬 볼륨에만
> 쌓였고, 백업은 그 파일들을 담지 못했다. **컨테이너의 실제 환경변수로 확인할 것**:
> `docker exec dodam-backend printenv | grep STORAGE_MODE`

### F. 검증

```bash
docker inspect dodam-backend --format '{{.State.Health.Status}} {{.RestartCount}}'   # healthy 0
docker logs dodam-backend 2>&1 | grep -c ' ERROR '                                   # 0
docker exec dodam-backend sh -c 'curl -s -o /dev/null -w "%{http_code}\n" http://minio:9000/minio/health/live'  # 200
```

⚠️ **기동 성공은 증거가 되지 못한다.** 백엔드는 기동 시 MinIO 를 호출하지 않으므로,
자격증명이 틀려도 healthy 로 뜬다. **반드시 실제 쓰기까지 확인할 것**:

```bash
# 앱에서 그림 1장 저장 후
docker exec dodam-mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N \
  -e "SELECT id, drawing_session_id, storage_key FROM drawing_assets ORDER BY id DESC LIMIT 3;" b209'
# → 새 행의 storage_key 가 MinIO 객체 목록에 있으면 성공
```

## 3. 롤백

```bash
sed -i 's/^STORAGE_MODE=s3$/STORAGE_MODE=local/' infra/.env
cd infra && docker compose up -d backend
```

⚠️ **롤백 창은 좁다.** 전환 전 파일은 로컬·MinIO 양쪽에 있어 안전하지만,
**전환 이후 저장된 파일은 MinIO 에만 있다.** 되돌리면 그 파일들은 읽을 수 없다.
문제가 보이면 새 파일이 쌓이기 전에 빨리 되돌리고, 이미 쌓였다면 되돌리기 전에
MinIO → 로컬 볼륨으로 역이관해야 한다.

## 4. 이번에 실제로 겪은 함정 (2026-07-28)

| 함정 | 증상 | 원인·교훈 |
|---|---|---|
| `.env` 를 템플릿으로 갱신하며 **서버 고유값이 덮임** | 백엔드 크래시 루프(`Access denied ... to database 'dodam'`) | `MYSQL_DATABASE` 가 `b209`→`dodam`. compose 가 `DB_NAME: ${MYSQL_DATABASE}` 로 파생한다. **1044(DB 접근 거부)와 1045(인증 실패)를 구분하면 원인이 좁혀진다** — 1044 였으므로 계정·비번은 맞고 DB명만 틀렸다 |
| MinIO **사용자명**이 템플릿 기본값으로 덮임 | 기동은 healthy, **파일 저장·조회만 조용히 실패** | `MINIO_BE_USER` 가 `dodam-be-rw`→`dodam-be`. 기동 시 MinIO 를 안 부르므로 헬스체크로는 절대 안 잡힌다 |
| `.env` 값 뒤 **탭 + 주석** | 주석이 값에 섞여 들어감 | compose dotenv 는 인라인 주석 구분자로 **공백만** 인식한다(v5.3.1 실측). 탭을 쓰면 `KEY="value\t# 주석"`. 정렬하려고 탭 넣지 말 것 |
| `mc` 컨테이너에서 검증 루프 | "전부 일치" 거짓 통과 | `minio/mc` 에 `find`·`awk`·`md5sum` 없음. 검증은 `alpine` + 호스트에서 |
| `docker run --network dodam-net` | `network dodam-net not found` | compose 네트워크는 프로젝트 접두사가 붙어 `dodam_dodam-net` |

## 5. 남은 일

- **374 백업 CronJob** — MinIO 단일노드라 디스크 장애 = 파일 전체 유실.
  `mc mirror` 백업이 아직 없다. `tts-cache/` 제외, `evidences/` 필수 포함.
- **오디오 파일 이관** — 현재 로컬에 오디오가 0개라 이관 대상이 없었다.
  STT/TTS 가 실제로 쓰이기 시작하면 같은 절차로 한 번 더.
- **구 로컬 파일 정리** — 전환 전 30개가 `backend-storage` 볼륨에 그대로 있다.
  1주 관찰 후 정리(백업 tar 는 보존).
- **at-rest 암호화** — EBS 볼륨 암호화 여부는 OS 안에서 판별 불가. AWS/SSAFY 콘솔 확인 필요.
