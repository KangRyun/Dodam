# MinIO 운영 가이드 (mc CLI)

> Jira: `S15P11B209-369` · 관련 `370`(BE S3 전환) · `374`(백업) · `622`(백업 스크립트)
> 대상: Infra 담당 · 갱신일 2026-07-28
> 함께 볼 것: `docs/database/저장소-아키텍처.md`(설계) · `docs/인프라/minio-스토리지-컷오버.md`(전환 절차)

## 0. 이 문서의 전제

MinIO 는 **아동의 그림·음성 파일을 담는 저장소**다. 여기서 하는 모든 조작은
아동 민감정보를 다루는 행위다(CLAUDE.md 9절).

- **외부 노출면 0** — `ports` 미개방. 접근은 내부망(`minio:9000`) 또는 SSH 터널뿐이다.
- **파일을 서버 밖으로 내보내지 않는다.** 검증·디버깅은 서버 안에서 끝낸다.
- **버킷 익명 접근은 `private`** 를 유지한다(`mc anonymous get` 으로 확인 가능).

## 1. 계정 2벌 — 무엇을 쓸지부터 정한다

| 계정 | 용도 | 권한 |
|---|---|---|
| `MINIO_ROOT_USER` | 프로비저닝·계정/정책 관리 | 전체 |
| `MINIO_BE_USER` (= `dodam-be-rw`) | 백엔드 · 조회/이관/백업 | 버킷 `dodam` 읽기·쓰기 |

> `dodam-ai-ro`(AI 읽기전용)는 **2026-08-02 회수했다(S15P11B209-673)** — AI 이미지 접근이
> BE 프록시 1회용 토큰(402)으로 구현돼, 만들기만 하고 아무 서비스도 쓰지 않는 유휴
> 자격증명이었다. 과거 프로비저닝된 서버에 남아 있으면 `mc admin user remove` 로 지운다.

**조회·이관·백업은 `be-rw` 로 한다.** root 는 계정·정책을 건드릴 때만 쓴다.
값은 `infra/.env` 에만 있다(저장소에는 없음).

⚠️ **계정 이름은 최초 프로비저닝 때 쓴 이름과 반드시 일치해야 한다.** 이름이 어긋나면
백엔드는 기동 시 MinIO 를 호출하지 않으므로 **healthy 로 뜨고 파일 저장·조회 시점에야 실패**한다.
2026-07-28 에 `dodam-be-rw` → `dodam-be` 로 어긋나 조용한 장애가 났다.
확인: `mc admin user list <alias>`

## 2. 기본 사용법 — mc 는 컨테이너로 쓴다

서버에 mc 를 설치하지 않는다. 필요할 때 일회성 컨테이너로 띄운다.

```bash
cd /home/kr/S15P11B209/infra && set -a && . ./.env && set +a

docker run --rm --network dodam_dodam-net \
  -e U="$MINIO_BE_USER" -e P="$MINIO_BE_PASSWORD" \
  --entrypoint sh minio/mc:latest -c '
    mc alias set m http://minio:9000 "$U" "$P" >/dev/null
    mc ls --recursive m/dodam/images/ | head'
```

⚠️ **네트워크 이름은 `dodam_dodam-net`** 이다. compose 프로젝트명(`dodam`)이 접두로 붙는다.
`dodam-net` 은 존재하지 않으며 `docker run` 이 즉시 실패한다(622 에서 실제로 겪음).

⚠️ **`minio/mc` 이미지에는 `find`·`awk`·`md5sum`·`sha256sum` 이 없다.**
그 안에서 검증 루프를 돌리면 명령이 조용히 실패하고 **"전부 일치" 같은 거짓 통과**가 찍힌다.
계산이 필요한 검증은 `alpine` 컨테이너나 호스트에서 한다(§5 참조).

## 3. 자주 쓰는 명령

```bash
# 객체 목록 / 개수
mc ls --recursive m/dodam/images/
mc ls --recursive m/dodam/images/ | wc -l

# 프리픽스별 용량
mc du m/dodam/images/

# 계정·정책 확인 (root 필요)
mc admin user list m
mc admin policy list m

# 버킷 공개 여부 — 반드시 private 이어야 한다
mc anonymous get m/dodam

# 수명주기(ILM) 규칙 — tts-cache 자동 만료
mc ilm rule ls m/dodam

# 특정 아동의 파일을 지울 때(동의 철회·탈퇴) — §6 먼저 읽을 것
mc rm m/dodam/images/2026/07/28/<uuid>.png
```

## 4. 웹 콘솔 접속 (SSH 터널)

콘솔(9001)도 외부에 열려 있지 않다. 포트를 열지 말고 터널을 쓴다.

```bash
# 컨테이너 IP 확인 (재생성 시 바뀐다)
docker inspect dodam-minio --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

# 로컬에서
ssh -L 9001:<컨테이너IP>:9001 kr@i15b209.p.ssafy.io
# → 브라우저 http://localhost:9001  (root 계정으로 로그인)
```

S3 GUI 클라이언트(Cyberduck·WinSCP 등)를 쓰려면 9000 으로 터널을 뚫고
**path-style access 를 반드시 켠다.** 끄면 `dodam.localhost:9000`(virtual-host style)으로
접속하려다 실패한다.

> 설계 문서에는 *"2025년 이후 커뮤니티 릴리스는 웹 콘솔 대부분 제거 — 콘솔 의존 금지"* 라고
> 적혀 있는데, 현재 쓰는 `RELEASE.2025-04-22` 는 그 변경 **이전** 버전이라 콘솔이 동작한다.
> 다만 이미지를 올리면 사라질 수 있으므로 **운영 절차는 mc 기준**으로 둔다.

## 5. 무결성 검증 — DB 가 기준이다

파일명은 UUID 라 그 자체로는 아무 정보가 없다. 무엇이 있어야 하는지는 **MySQL 이 안다.**

```
MinIO 객체 key : images/2026/07/28/<uuid>.png
                 └prefix┘└─ drawing_assets.storage_key ─┘
```

`drawing_assets` 에는 `checksum_sha256` 이 전 행에 채워져 있다. 별도 기준을 만들 필요 없이
이 값과 실제 파일 해시를 대조하면 된다.

```bash
# 1) DB 기준: "storage_key sha256"
docker exec dodam-mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e \
  "SELECT CONCAT(storage_key,\" \",LOWER(checksum_sha256)) FROM drawing_assets ORDER BY storage_key;" b209' \
  | sort > /tmp/db_sha.txt

# 2) MinIO 실제: 임시 볼륨에 받아 alpine 에서 계산 → 계산 후 즉시 삭제
docker volume create dodam-verify-tmp
docker run --rm --network dodam_dodam-net -v dodam-verify-tmp:/out \
  -e U="$MINIO_BE_USER" -e P="$MINIO_BE_PASSWORD" --entrypoint sh minio/mc:latest -c \
  'mc alias set m http://minio:9000 "$U" "$P" >/dev/null && mc cp --recursive m/dodam/images/ /out/'
docker run --rm -v dodam-verify-tmp:/data alpine sh -c \
  'cd /data && find . -type f | sed "s|^\./||" | sort | while read -r k; do
     printf "%s %s\n" "$k" "$(sha256sum "$k" | cut -d" " -f1)"; done' > /tmp/minio_sha.txt
docker volume rm dodam-verify-tmp

# 3) 대조 — 비어야 정상
diff /tmp/db_sha.txt /tmp/minio_sha.txt && echo "일치"
```

⚠️ **개수만 비교하지 말 것.** 2026-07-28 에 "30 → 32 로 늘었으니 성공"이라 판단했다가,
실제로는 다른 파일 2개였고 정작 확인하려던 4개는 저장되지 않은 상태였다.
**키 단위로 대조**해야 한다.

## 6. 삭제할 때 (동의 철회·탈퇴)

아동 데이터 삭제는 DB 와 MinIO 양쪽에서 일어나야 한다. **MinIO 만 지우면 DB 에 유령 레코드가,
DB 만 지우면 MinIO 에 고아 객체가 남는다.**

삭제 대상 산출:
```sql
SELECT CONCAT('images/', a.storage_key)
FROM drawing_assets a
JOIN drawing_sessions s ON s.id = a.drawing_session_id
WHERE s.child_id = <childId>;
```

고아 객체 점검(정기):
```bash
# DB 키 목록과 MinIO 목록을 뽑아 comm 으로 양방향 비교 (§5 의 1)·2) 재사용)
```

⚠️ `evidences/`(동의 증빙)는 **법적 보존 대상**이라 TTL·자동삭제에서 구조적으로 제외한다.
탈퇴 시 처리 방침은 아직 미정이다(`저장소-아키텍처.md` §9 열린 질문 1).

## 7. 백업

`infra/scripts/minio-backup.sh`(root, cron 매일 04:30) · `minio-restore.sh`.
자세한 절차와 함정은 `docs/인프라/minio-스토리지-컷오버.md` 와 스크립트 헤더 주석 참조.

```bash
sudo /home/kr/S15P11B209/infra/scripts/minio-backup.sh          # 수동 실행
sudo /home/kr/S15P11B209/infra/scripts/minio-restore.sh --dry-run <백업파일>   # 복원 드릴
```

⚠️ **로그의 `OK` 를 그대로 믿지 말 것.** 2026-07-27·28 백업은 `OK ... size=4.0K` 로
이틀 연속 성공 기록을 남겼지만 **내용이 빈 백업**이었다(당시 버킷이 비어 있었음).
`size` 가 직전 대비 급감했는지, 객체 수가 DB 와 맞는지 함께 봐야 한다.

## 8. 모니터링

Prometheus job `minio` — `minio:9000/minio/v2/metrics/cluster` (S15P11B209-369).
무인증 스크레이프는 compose 의 `MINIO_PROMETHEUS_AUTH_TYPE=public` 에 의존한다.
타깃이 down 이면 그 환경변수부터 확인한다(기본값 `jwt` 이면 403).

## 9. 알려진 한계 (2026-07-28 기준)

| 항목 | 상태 |
|---|---|
| 단일 노드·단일 드라이브 | erasure coding 불가 — 디스크 장애 시 백업이 유일한 복구 수단 |
| 백업 저장 위치 | **원본과 같은 디스크**(`/dev/root`) — 디스크 장애에는 무력. 오프사이트 필요 |
| at-rest 암호화 | EBS 볼륨 암호화 여부 **미확인**(OS 내부에서 판별 불가 — AWS/SSAFY 콘솔 확인 필요) |
| k8s 전환 | 미실행. 현재는 compose 운영 — k3s 컷오버(360) 시 StatefulSet·PVC 로 이전 |
| 파일 열람 감사 로그 | 미구현(누가 어떤 아동 그림을 언제 봤는지) — 4차 후보 |
