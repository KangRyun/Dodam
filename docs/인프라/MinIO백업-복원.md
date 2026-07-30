# MinIO 파일 스토리지 백업·복원 운영 (S15P11B209-622)

> 대상: 버킷 `dodam`(그림·음성·리포트·동의증빙). 담당: Infra(root).
> 스크립트: `infra/scripts/minio-backup.sh` · `infra/scripts/minio-restore.sh`
> 설계 근거: `docs/database/저장소-아키텍처.md` §2·§7 / 정책 표: `docs/인프라/파일-수명주기-정책.md`

⚠️ **백업 파일 = 아동 민감정보.** 서버 밖 반출·복사·전송 금지. 열람·복원은 Infra(root)만. (CLAUDE.md 9절)

---

## 무엇을 / 어떻게

- 버킷 `dodam` 을 `mc mirror` 로 받아(**`tts-cache/` 제외** — 재생성 파생물) tar+gzip+**AES-256 암호화** → `/var/backups/dodam/minio-<STAMP>.tar.gz.enc`, **14일** 초과분 삭제.
- 암호화 파라미터·패스프레이즈·보관 규정은 **MySQL 백업(353)과 공용·동일** — 운영 일관성.

## 사전 준비 (최초 1회, root)

MySQL 백업이 이미 구성돼 있으면 1·2는 갖춰져 있음(공용).

1. **패스프레이즈** `/etc/dodam/backup-passphrase` (root:root, 600)
   ```
   openssl rand -base64 32 > /etc/dodam/backup-passphrase
   chown root:root /etc/dodam/backup-passphrase && chmod 600 /etc/dodam/backup-passphrase
   ```
2. **백업 디렉토리** `/var/backups/dodam` (root:root, 700)
   ```
   install -d -m 700 -o root -g root /var/backups/dodam
   ```
3. **mc 이미지** — `minio/mc:RELEASE.2025-04-16T18-13-26Z` (minio-init 빌드로 이미 pull됨)

## 백업 (자동 — k3s CronJob)

**호스트 cron 은 제거됐다** (2026-07-30, S15P11B209-733). 매니페스트: `infra/k8s/base/cronjobs.yaml`

| CronJob | 시각 (KST) | 비고 |
|---------|-----------|------|
| `minio-backup` | **00:30 · 06:30 · 12:30 · 18:30** | 6시간 주기 |
| `db-backup` | 04:00 | 하루 1회 |
| `mongo-backup` | 04:30 | 하루 1회 |

- **6시간 주기인 이유** — 하루 1회면 최대 24시간의 백업 공백이 생긴다.
  2026-07-28 하루에만 파일이 30 → 70개로 늘었다. 낮에 디스크가 나가면 그날 그린 그림이
  전부 사라진다. MySQL 은 잃어도 계정·설정이지만 **MinIO 는 재생성할 수 없는 원본**이다.
  데이터도 작아(2026-07-30 기준 8MB) 주기를 올리는 비용이 거의 없다.
- MySQL·Mongo 와 **시차(:30)** — 같은 hostPath·같은 노드 디스크를 쓰므로 겹치지 않게 띄운다.
- 수동 1회: `sudo infra/scripts/minio-backup.sh` (스크립트는 그대로 유지된다 — cron 등록만 없앴다)
- 성공 로그: `[minio-backup] OK file=... objects=225 bytes=4284000 retention=14d exclude=tts-cache/*`

> ⚠️ **이 6시간 주기는 374(2026-07-28)에 이 문서로 결정됐지만 2026-07-30 까지 실제로는
> 적용된 적이 없었다.** 서버의 호스트 cron 은 `30 4 * * *`(하루 1회)였고, `30 */6` 은 git 의
> 어떤 cron 파일에도 들어간 적이 없다. 733 에서 CronJob 으로 옮기며 문서 쪽으로 맞췄다.
> **문서가 결정을 적어도 배선이 따라오지 않으면 결정이 아니다.**

### ★ 컨테이너 두 개인 이유 (CronJob)

`minio/mc` 이미지에는 **`mc` 와 `stat` 밖에 없다** — `tar`·`gzip`·`openssl`·`find` 가 전부 없다
(2026-07-30 실측). 한 컨테이너로 "받아서 묶고 암호화"를 끝낼 수 없다.

```
initContainer(minio/mc)   버킷 → /stage 로 mc mirror
container(mysql:8.4.10)   /stage → tar+gzip+AES-256   ← 이 이미지엔 네 도구가 다 있다
```

호스트 스크립트가 쓰던 `kubectl port-forward` 는 필요 없다 — 클러스터 안에서 `minio:9000` 에
직접 붙는다. 그 다리를 없애는 것이 CronJob 으로 옮긴 실익이다.

`/stage` 는 **emptyDir** 다. mirror 직후 그 안에는 **아이 그림·음성이 평문으로** 놓이므로,
파드와 함께 사라지는 볼륨을 쓴다. 호스트 스크립트는 `/var/backups/dodam/.minio-stage-*` 에
풀어서 실패 시 평문이 남았다.

### ⚠️ 로그의 `OK` 를 그대로 믿지 말 것

2026-07-27·28 백업이 **이틀 연속 `OK size=4.0K` 로 성공 기록**을 남겼지만 실제로는
**내용이 빈 백업**이었다(당시 버킷이 비어 있었음). 종료 코드도 0이었고, 크기가 4.0K 로
고정이라 오히려 *안정적*으로 보였다.

그래서 로그에 **`objects=`(담긴 객체 수)** 를 함께 남긴다. 확인 기준은 두 가지다.

| 볼 것 | 정상 판정 |
|---|---|
| `objects=` | DB `drawing_assets` 개수와 일치하거나 그 이상 |
| `objects=0` | `WARN` 이 함께 출력된다 — 버킷·자격증명·프리픽스를 확인할 것 |

```bash
# 대조용 — DB 가 기억하는 파일 수
/usr/local/bin/kubectl -n dodam exec statefulset/mysql -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N \
  -e "SELECT COUNT(*) FROM drawing_assets;" b209'
```

## 복원

**항상 `--dry-run` 먼저** (운영 버킷 미변경, 백업 무결성만 검증):
```
sudo infra/scripts/minio-restore.sh --dry-run /var/backups/dodam/minio-2026-07-26-0430.tar.gz.enc
```
실복원 (확인 문자열 `RESTORE` 입력 강제):
```
sudo infra/scripts/minio-restore.sh /var/backups/dodam/minio-2026-07-26-0430.tar.gz.enc
```
- **비파괴 overwrite**: 백업에 담긴 객체만 되돌려 덮어씀. 백업 이후 신규 객체·`tts-cache/`는 **지우지 않음**(mirror --remove 미사용).
- 되돌리는 프리픽스: `images/ audio/ reports/ evidences/`.

## 월 1회 복구 드릴 (권장)

백업이 존재하는 것과 **복원되는 것**은 다르다 — 드릴로만 보장된다.
그리고 "복호화가 되는 것"과 **"쓸모 있는 내용이 담긴 것"** 도 다르다.

```bash
# 1) 최신 백업 확인
#    ⚠️ glob(*)은 sudo 이전에 "현재 사용자" shell 이 확장한다. 백업 디렉토리는 700 root 라
#       일반 계정이 읽지 못해 zsh 에서 `no matches found` 로 실패한다(파일이 없어서가 아니다).
#       그래서 확장을 root 쪽으로 넘긴다.
sudo sh -c 'ls -lt /var/backups/dodam/minio-*.tar.gz.enc | head -3'

# 2) 드릴 — 운영 버킷은 건드리지 않는다
sudo /home/kr/S15P11B209/infra/scripts/minio-restore.sh --dry-run \
  /var/backups/dodam/minio-<날짜>-<시각>.tar.gz.enc

# 3) 대조 — 담긴 개수가 DB·현재 버킷과 맞는지
/usr/local/bin/kubectl -n dodam exec statefulset/mysql -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N \
  -e "SELECT COUNT(*) FROM drawing_assets;" b209'
```

드릴 출력에 `objects=` 와 프리픽스별 개수가 나온다. **세 숫자(백업·버킷·DB)가 맞아야 통과**다.
개수가 맞아도 내용이 다를 수 있으므로, 더 강한 검증이 필요하면
`docs/인프라/MinIO-운영.md` §5 의 sha256 전수 대조를 쓴다
(`drawing_assets.checksum_sha256` 이 전 행에 채워져 있어 별도 기준이 필요 없다).

결과는 팀 로그에 기록한다 — 언제 드릴했고 몇 개였는지가 다음 드릴의 비교 기준이 된다.

## 검증 현황

| 항목 | 상태 |
|------|------|
| `mc mirror --exclude "tts-cache/*"` 가 tts-cache 를 건너뛰는지 | **검증됨** (2026-07-30) |
| CronJob 경로로 산출물 생성 | **검증됨** (2026-07-30) |
| 백업 → 복호화 왕복 | **검증됨** (2026-07-30) |
| CronJob **스케줄** 경로(컨트롤러가 잡을 만드는 것) | **검증됨** (2026-07-30 12:30, S15P11B209-733) |
| **복원 드릴** (객체를 실제로 되돌리기) | **검증됨** (2026-07-30, S15P11B209-737) ↓ |
| `mc ilm import` 지원 여부 | 미검증 (미지원 시 init 로그 WARN + 수동 적용 안내) |

---

## 복원 드릴 기록

| 회차 | 일시 | 백업 파일 | 결과 |
|------|------|-----------|------|
| 1 | 2026-07-30 13:0x | `minio-2026-07-30-1230.tar.gz.enc` (4.46MB) | **성공** — 251객체 복원, 운영 253개 대비 −2(백업 후 유입) |

### 1회차 상세 (S15P11B209-737)

```
[unpack] OK files=251 bytes=5187450 tts_cache_dirs=0
[loader] RESTORED total=251 images=238 audio=13 tts_cache=0   (4.9MiB)
```

| | 복원본 | 운영(드릴 시점) | |
|---|---|---|---|
| 백업 대상 전체 | 251 | 253 | −2 = 백업(12:30) 이후 유입 |
| `images/` | 238 | 239 | |
| `audio/` | 13 | 14 | |
| `tts-cache/` | **0** | 79 | 백업 제외 대상이라 0 이 정답 |

세 가지를 확인했다:

1. **해제 파일 수(251) == 적재 객체 수(251)** — tar 에서 풀린 것이 하나도 빠짐없이 올라갔다
2. **`tts-cache` 0건** — 재생성 가능한 파생물이 백업에서 제외되는 것이 실제로 지켜졌다
3. **복원본 ≤ 운영**, 차이가 백업 이후 유입분과 맞는다 — 복원본이 더 많거나 비어 있으면 결함이다

드릴 전후로 **운영 버킷은 332개 그대로**였다.

### ★ 임시 "버킷" 이 아니라 임시 **인스턴스**를 쓴다

처음 계획은 운영 MinIO 안에 `drill-restore` 버킷을 만드는 것이었는데 바꿨다.

같은 인스턴스 안에 만들면 **아동 데이터 사본이 운영 저장소 안에 생기고**, 명령 한 줄 잘못
치면 운영 버킷에 쓸 여지가 남는다. 대신 **임시 MinIO 파드를 띄워** 거기에 복원한다 —
733 의 MySQL 드릴과 같은 구조다. 운영 MinIO 에는 `mc ls`(읽기)만 던진다.

지켜야 할 네 가지(733 과 동일):

| | |
|---|---|
| 복원본 저장소 | **emptyDir** — 파드와 함께 사라진다 |
| 백업 볼륨 | **readOnly** — 드릴이 운영 백업을 덮어쓸 수 없다 |
| 외부 노출 | **Service 를 만들지 않는다** |
| 정리 | 종료 시 즉시 파드 삭제(`trap` — 중간에 죽어도 정리된다) |

객체 키(파일명)는 화면에 찍지 않는다. **개수와 용량까지만** 본다.

### 파드 구성 — 왜 컨테이너가 셋인가

이미지마다 가진 도구가 달라서 한 컨테이너로는 끝나지 않는다(2026-07-30 실측).

| 이미지 | 가진 것 | 없는 것 |
|---|---|---|
| `minio/minio` | `mc` · `curl` | `tar` · `gzip` · `openssl` · `grep` · `awk` |
| `minio/mc` | `mc` · `wc` · `sort` · `head` | `tar` · `gzip` · `openssl` · `curl` · `grep` |
| `mysql:8.4.10` | `tar` · `gzip` · `openssl` · `find` | `mc` |

```
initContainer  unpack  (mysql)  복호화 + tar 해제 → emptyDir /stage
container      minio   (minio)  드릴 전용 인스턴스 (emptyDir /data)
container      loader  (mc)     /stage → 임시 버킷 적재 + 개수 집계
```

> ⚠️ **`mc alias set` 이 성공할 때까지 기다린다.** "파드가 떴다"와 "MinIO 가 요청을 받는다"는
> 다르다. 733 MySQL 드릴에서 `mysqladmin ping` 이 인증 설정 전에도 alive 를 답해
> `ERROR 1045` 를 받은 적이 있다 — 준비 판정은 **실제로 되는 동작**으로 한다.

### 다시 돌리려면

드릴 스크립트는 이 저장소에 커밋하지 않았다(일회성 검증 도구이고, 운영 파드를 만드는
스크립트를 상비해 두면 실수로 도는 편이 더 위험하다). 절차는 위 구성 그대로이고,
핵심은 **`tar -C /stage -czf - .` 로 만든 것을 `tar -xzf - -C /stage` 로 되돌린다**는 점이다.
이 레이아웃이 어긋나면 `minio-restore.sh` 와 절차가 두 벌이 된다.

## 종료 코드 (호스트 스크립트 — 수동 실행 경로)

`0` 성공 / `2` root 아님·인자 / `3` 패스프레이즈 / `4` 백업 디렉토리·파일 /
`5` minio 워크로드 미준비(`kubectl -n dodam get sts minio` — 732 에서 docker→k3s 전환) /
`6` mirror·암복호화 파이프라인

CronJob 쪽은 종료 코드가 아니라 잡 상태로 본다: `kubectl -n dodam get job | grep minio-backup`.
실패 시 Mattermost 알림이 온다(`BackupJobFailed`·`BackupMissing` — DB백업-복원.md §3 참조).
