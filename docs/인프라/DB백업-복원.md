# DB 백업·복원 운영 규정 (S15P11B209-353)

> 대상: k3s `dodam/statefulset/mysql`(MySQL 8.4.10) · DB `b209` · EC2 `i15b209.p.ssafy.io`
> ⚠️ 2026-07-30(S15P11B209-732)부터 대상이 Docker 컨테이너가 아니라 k3s 워크로드다.
> 스크립트: `infra/scripts/mysql-backup.sh` · `infra/scripts/mysql-restore.sh`
> ⚠️ **백업 파일 = 아동 민감정보. 복사·전송 금지.** (CLAUDE.md 9절 가드레일)

---

## 1. 설계 요약 — 왜 이렇게 하는가

| 결정 | 이유 |
|------|------|
| **mysqldump `--single-transaction --routines --triggers --databases b209`** | 8.4 업그레이드 전 수동 백업 전례와 동일 방식. InnoDB를 잠금 없이 일관 스냅샷으로 덤프(운영 무중단), 프로시저·트리거 포함, `--databases`로 CREATE DATABASE/USE 포함 → 빈 서버에도 복원 가능 |
| **비밀번호 비노출(`MYSQL_PWD` 컨테이너 env 재사용)** | 스크립트·crontab·프로세스 목록(`ps`) 어디에도 비밀번호가 남지 않음. 컨테이너 안에 이미 있는 `MYSQL_ROOT_PASSWORD`를 그대로 사용 |
| **왜 암호화(AES-256-CBC + PBKDF2)** | 백업 파일은 아동의 그림·대화·리포트 원본이 통째로 담긴 평문 SQL. 디스크·스냅샷·실수 유출 어느 경로로 새어도 패스프레이즈 없이는 읽을 수 없어야 함(가드레일 9절: 개인정보 암호화·접근제어). `-pbkdf2`는 openssl 구식 키 유도의 알려진 약점 회피 |
| **패스프레이즈를 `/etc/dodam/backup-passphrase` 파일(root 600)로** | 명령 인자·환경변수로 넘기면 프로세스 목록·셸 히스토리에 노출됨. root 전용 파일 + `-pass file:` 방식이면 노출면이 0. git 저장소 밖이라 커밋 사고도 원천 차단 |
| **왜 14일 보관** | 가드레일 9절 "보관 기간 경과 시 자동 삭제"의 백업판. 주간 릴리즈 2회분을 되돌릴 수 있는 최소선이면서, 아동 데이터 사본이 무한히 쌓이는 것과 디스크 고갈을 방지 |
| **저장 위치 `/var/backups/dodam` (root 700)** | 컨테이너·볼륨과 분리된 호스트 경로 — 컨테이너를 지워도 백업은 남음. root 700으로 다른 계정은 목록 열람도 불가 |
| **실패 시 명확한 종료코드(2~6)** | cron 메일·후속 알림(MM 웹훅 등)에서 실패 지점을 코드로 구분하기 위함. 부분 파일(`.part`)은 자동 삭제 — 깨진 백업이 정상으로 오인되는 것 방지 |

---

## 2. 사전 준비 (1회, root로 실행)

```bash
# 1) 패스프레이즈 파일 — 값은 무작위 32바이트(base64). 절대 다른 곳에 기록·전송하지 않는다.
sudo install -d -m 700 -o root -g root /etc/dodam
sudo sh -c 'openssl rand -base64 32 > /etc/dodam/backup-passphrase'
sudo chmod 600 /etc/dodam/backup-passphrase
sudo chown root:root /etc/dodam/backup-passphrase

# 2) 백업 디렉토리 (root 700)
sudo install -d -m 700 -o root -g root /var/backups/dodam

# 3) 스크립트 실행 권한
chmod +x /home/kr/S15P11B209/infra/scripts/mysql-backup.sh /home/kr/S15P11B209/infra/scripts/mysql-restore.sh
```

> ⚠️ 패스프레이즈 파일을 잃어버리면 **모든 백업이 영구히 복원 불가**가 된다.
> 분실 대비가 필요하면 값 자체를 안전한 오프라인 수단(팀 금고 등)에만 보관 — 채팅·노션·git 금지.

---

## 3. 스케줄 — k3s CronJob (2026-07-30 전환 완료, S15P11B209-733)

**호스트 cron 은 제거됐다.** 스케줄은 k3s CronJob 이 담당한다.

| CronJob | 시각 (KST) | 산출물 |
|---------|-----------|--------|
| `db-backup` | 04:00 | `/var/backups/dodam/b209-<stamp>.sql.gz.enc` |
| `mongo-backup` | 04:30 | `mongo-<stamp>.tar.gz.enc` |
| `minio-backup` | 05:00 | `minio-<stamp>.tar.gz.enc` (호스트 cron 시절 04:30 에서 옮김) |

매니페스트: `infra/k8s/base/cronjobs.yaml` · 활성화: `infra/k8s/overlays/prod/cronjobs-enable.yaml`

```bash
kubectl -n dodam get cronjob                    # SUSPEND 가 False 여야 한다
kubectl -n dodam get job | grep backup          # 실행 이력
kubectl -n dodam logs job/db-backup-<id>        # 결과 한 줄
```

### ⚠️ `timeZone` 이 없으면 UTC 로 해석된다

CronJob 의 `schedule` 은 **호스트 TZ 가 아니라 컨트롤러 시간대(UTC)** 로 해석된다.
파드도 기본이 UTC 다. 2026-07-30 실측: host `KST 09:45` / pod `UTC 00:45`.

`timeZone` 없이 `0 4 * * *` 를 두면 **04:00 UTC = 13:00 KST**, 한낮에 백업이 돈다.
그래서 두 가지를 **둘 다** 넣었다 — 하나만으로는 부족하다.

| 설정 | 없으면 | 고치는 대상 |
|------|--------|-------------|
| `spec.timeZone: "Asia/Seoul"` | 13:00 KST 에 실행 | **스케줄 해석** |
| `env: TZ=Asia/Seoul` | 파일명이 `b209-…-0038`(실제 09:38) | **컨테이너의 `date`** |

`kubectl get cronjob` 의 `TIMEZONE` 열이 `<none>` 이면 UTC 다. 확인 지점으로 쓸 것.

### ⚠️ suspend 를 풀면 놓친 스케줄을 따라잡는다

`startingDeadlineSeconds` 를 두지 않았으므로, suspend 해제 시 컨트롤러가 **미실행 스케줄을
즉시 보충 실행**한다. 2026-07-30 컷오버 때 10:46 에 04:00·04:30 분이 따라 돌았다.
의도한 동작이다 — 노드가 04:00 에 죽어 있었다면 복구 후에라도 백업이 남는 게 낫다.
다만 "왜 지금 백업이 돌지?" 하고 놀라지 말 것.

### 실패 알림

`docs/인프라/` 밖 이야기지만 여기 적어 둔다 — 이 백업의 실패를 아는 유일한 경로다.
Prometheus 룰 3종(`infra/k8s/base/monitoring-prometheus.yaml` 의 `backup.yml`) →
Alertmanager → Mattermost.

| 룰 | 잡는 것 |
|----|---------|
| `BackupJobFailed` | 잡이 돌았고 실패했다 |
| `BackupMissing` | **잡이 아예 돌지 않았다** — 25시간 내 성공 없음. 2026-07-30 새벽 양상 |
| `BackupSuspended` | 점검 창에서 끄고 되돌리지 않았다(24시간 초과) |

> 733 이전에는 실패가 `/var/log/dodam-backup.log` 에만 남았고, 아무도 보지 않아
> **백업 4종이 전부 죽을 예정인 것을 몰랐다.** "깨끗한 실패"가 곧 "모르는 실패"였다.

### 수동 백업 / 복원 스크립트는 그대로 쓴다

`infra/scripts/{mysql,minio}-{backup,restore}.sh` 는 **없애지 않았다.**
없앤 것은 cron 등록뿐이다. 특히 `mysql-restore.sh` 는 §5 의 정식 복원 경로다.

```bash
sudo /home/kr/S15P11B209/infra/scripts/mysql-backup.sh    # 임의 시점 수동 백업
```

---

## 4. 백업 검증 (--dry-run)

복원까지 가지 않고 "이 백업이 정말 열리는 파일인가"(복호화 + gzip 무결성)만 확인:

```bash
sudo /home/kr/S15P11B209/infra/scripts/mysql-restore.sh --dry-run /var/backups/dodam/b209-<날짜>.sql.gz.enc
# → [mysql-restore] DRY-RUN OK ... 이면 패스프레이즈 일치 + 파일 무손상까지 보장. DB는 건드리지 않음.
```

첫 수동 백업 직후 반드시 1회 실행해 패스프레이즈 파일이 올바른지 확인한다.

---

## 5. 복원 절차

```bash
# 1) 백업 목록 확인
sudo ls -lh /var/backups/dodam/

# 2) (권장) 복원 직전, 현재 상태도 한 번 백업 — 복원 자체를 되돌릴 수단 확보
sudo /home/kr/S15P11B209/infra/scripts/mysql-backup.sh

# 3) 복원 — 확인 프롬프트에서 워크로드명(statefulset/mysql)을 직접 입력해야 진행됨
sudo /home/kr/S15P11B209/infra/scripts/mysql-restore.sh /var/backups/dodam/b209-<날짜>.sql.gz.enc
# 다른 대상(스테이징 등)으로 복원하려면 두 번째 인자로 워크로드 지정:
# sudo .../mysql-restore.sh <파일> statefulset/mysql-staging

# 4) 복원 확인
/usr/local/bin/kubectl -n dodam exec statefulset/mysql -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "SHOW TABLES IN b209;"'
# + backend 헬스체크·로그인 등 스모크 테스트
```

주의: 복원은 덤프 시점 상태로 **덮어쓰기**다. 덤프 이후의 데이터는 사라진다.
복원 중에는 backend가 쓰기 요청을 보내지 않도록 필요 시 backend 컨테이너를 잠시 정지하는 것을 권장
(`docker stop dodam-backend` → 복원 → `docker start dodam-backend` — 실행은 Infra 담당 판단).

---

## 6. 복원 드릴 규정

백업은 "복원해 본 백업"만 신뢰할 수 있다.

- **월 1회** 복원 드릴 수행 — 최신 백업으로 `--dry-run` + **임시 파드 실복원**까지.
- 드릴 결과(일시·파일명·성공 여부·대조 결과)는 아래 표에 한 줄씩 기록.

| 회차 | 일시 | 백업 파일 | 결과 | 비고 |
|------|------|-----------|------|------|
| 1 | 2026-07-30 10:1x | `b209-2026-07-30-1005.sql.gz.enc` (884KB) | **성공** | CronJob 산출물 · 69/69 테이블 · 55576/55847행 (차이는 백업 후 유입분) |

### 1회차 드릴 상세 (S15P11B209-733)

무엇을 확인했는가 — "백업이 돌았다"가 아니라 **복원된다**는 것:

| # | 검증 | 방법 | 결과 |
|---|------|------|------|
| ① | 복호화된다 | Secret 의 `-pass env:` 경로 | OK |
| ② | **기존 절차와 같은 방식으로** 복원된다 | DB명을 지정하지 않고 `mysql` 에 흘려보냄 | OK |
| ③ | 내용이 맞는다 | 69개 테이블 전수 `COUNT(*)` 대조 | 63개 정확히 일치 |

②가 핵심이다. `mysql-restore.sh` 는 *"덤프가 `--databases` 로 만들어져 CREATE DATABASE/USE 가
포함돼 있으므로 DB명을 지정하지 않고 흘려보낸다"* 는 전제로 짜여 있다(그 스크립트 109행).
CronJob 매니페스트에는 원래 **`--databases` 가 없었고**, 그대로 켰으면 새 백업이 기존 복원
절차로 복원되지 않아 절차가 두 벌이 됐을 것이다. 733 에서 플래그를 맞췄다.

행 수 차이 6건은 전부 **복원 ≤ 원본**이고 백업 시각(10:05) 이후 유입분으로 확인됐다:

```
drawing_sessions     -1     analyses  -3     drawing_assets       -3
stroke_batches       -3     stroke_events -3  stroke_event_points -258
```

그리기 세션 1건이 만든 인과 한 줄이다. 결함 신호(**복원 > 원본**, 빈 테이블)는 없었다.

### 드릴 방법 (운영 DB 를 건드리지 않는다)

운영 `mysql-0` 에는 `SELECT COUNT(*)` 만 던지고, 복원은 임시 파드에만 한다.

```bash
# 요지: 임시 mysql 파드(emptyDir) + 백업 hostPath 를 readOnly 로 마운트 + Secret 주입
kubectl -n dodam run <임시> --image=mysql:8.4.10 ...   # 상세는 733 이슈의 드릴 스크립트
# 복원 후 행 수 대조 → 파드 즉시 삭제
```

⚠️ **가드레일:** 복원 순간 임시 파드 안에 **아동 데이터 실물**이 만들어진다.
`emptyDir`(파드와 함께 소멸) · 백업 볼륨 `readOnly` · **Service 를 만들지 않음** ·
드릴 종료 시 즉시 삭제. 이 네 가지를 지키지 않으면 드릴 자체가 유출 경로가 된다.

⚠️ **준비 판정에 `mysqladmin ping` 을 쓰지 말 것.** mysql 이미지는 초기화 중 소켓 전용
임시 서버를 먼저 띄우고, 그 서버는 **root 비밀번호가 설정되기 전에도 ping 에 alive 로 답한다.**
1회차 드릴에서 그 상태를 "준비됨"으로 읽고 복원을 던져 `ERROR 1045` 를 받았다.
`SELECT 1` 이 **인증까지 통과**하는지로 판정한다.

---

## 7. 취급 규정 (타협 불가)

- 백업 파일·패스프레이즈의 **복사·전송 금지** — scp/이메일/채팅/클라우드 업로드 전부 금지.
  아동 민감정보 원본이며, 반출 시점부터 수명주기(자동 삭제) 통제를 벗어난다.
- 열람·복원은 **Infra 담당(root)** 만. 다른 팀원에게 필요한 건 백업 "존재 여부"뿐, 내용이 아니다.
- 보관 기간(14일) 초과분은 자동 삭제 — 수동으로 따로 빼두지 않는다.
  파일명 규약을 CronJob 도 `b209-*` 로 맞췄기 때문에 **호스트 cron 시절 산출물도 같은 규칙으로
  정리된다.** 이름이 갈리면 옛 파일을 아무도 지우지 않고 무한 적재된다.
- **k3s CronJob 이전 완료** (2026-07-30, S15P11B209-733). root crontab ·
  `/etc/cron.d/dodam-minio-backup` 제거됨. 제거 전 원본은 `/etc/dodam/733-cron-backup/` 에 보관.

### 패스프레이즈는 노드 로컬 파일 + k8s Secret **둘 다** 있다

이전 시점에 재결정한 결과: **노드 로컬 파일(`/etc/dodam/backup-passphrase`)을 원본으로 유지**하고,
CronJob 용 Secret `dodam-backup` 을 그 값에서 만든다. 스크립트(수동·복원)와 CronJob 이
같은 키를 쓰게 하려면 두 곳에 있어야 한다.

```bash
# 만드는 법 — ★ 꼬리 개행을 반드시 떼고 넣는다
sudo sh -c 'umask 077; printf %s "$(cat /etc/dodam/backup-passphrase)" > /tmp/.bp \
  && kubectl -n dodam create secret generic dodam-backup --from-file=BACKUP_PASSPHRASE=/tmp/.bp; rm -f /tmp/.bp'
```

⚠️ **`--from-file` 을 파일에 그대로 걸면 안 된다.** 패스프레이즈 파일은
`openssl rand -base64 32 > 파일` 로 만들어져 **꼬리 개행이 있다**(45바이트 = 값 44 + 개행 1).

| 경로 | 전달 방식 | 실제 키 |
|------|-----------|---------|
| 스크립트(기존 백업) | `-pass file:` | **44바이트** — `file:` 은 첫 줄만 읽고 개행을 버린다 |
| CronJob | `-pass env:` | Secret 값 **그대로** |

개행이 섞인 45바이트를 Secret 에 넣으면 **다른 키**가 되어, 새 백업은 잘 만들어지는데
**기존 `b209-*`·`minio-*` 백업을 복호화할 수 없다.** 복호화가 필요한 날에야 안다.

교체·재생성 후에는 **눈으로 대조하지 말고** 반드시 실제로 확인한다(S15P11B209-730 과 같은 결):

```bash
# ① 길이 대조
sudo kubectl -n dodam get secret dodam-backup -o jsonpath='{.data.BACKUP_PASSPHRASE}' | base64 -d | wc -c
# ② ★ 진짜 검증 — 기존 백업이 env: 경로로 복호화되는가 (gzip -t 까지)
```

---

## 8. 장애 시 빠른 참조

| 증상 | 종료코드 | 조치 |
|------|----------|------|
| `root로 실행해야` | 2 | `sudo`로 재실행 / root cron 확인 |
| `패스프레이즈 파일이 없습니다` | 3 | §2 사전 준비 수행 |
| `패스프레이즈 파일 권한 오류` | 3 | `chown root:root` + `chmod 600` |
| `백업 디렉토리가 없습니다/권한 오류` | 4 | `install -d -m 700 -o root -g root /var/backups/dodam` |
| 워크로드가 준비되지 않았습니다 | 5 | `kubectl -n dodam get sts mysql` — `docker ps` 가 아니다(732 에서 k3s 로 전환). 옛 compose 컨테이너를 되살리지 말 것 |
| 파이프라인 실패(덤프/복호화) | 6 | 로그 확인 — 디스크 용량(`df -h`), 패스프레이즈 일치 여부(`--dry-run`) 순서로 점검 |

### CronJob 쪽 문제

| 증상 | 확인 |
|------|------|
| 백업이 한낮에 돈다 | `kubectl get cronjob` 의 `TIMEZONE` 열. `<none>` 이면 UTC 다 → `spec.timeZone` 확인 |
| 파일명 시각이 9시간 어긋난다 | 컨테이너 `env: TZ`. `timeZone` 은 스케줄만 바꾼다 |
| 잡이 생성조차 안 된다 | `kubectl -n dodam describe cronjob <이름>` · `suspend` 값 · hostPath `/var/backups/dodam` 존재 여부(`type: Directory` 라 없으면 파드가 뜨지 않는다) |
| `mongo-backup` 이 WARN | `documents=0` 이면 정상 — 앱이 아직 Mongo 에 쓰지 않는다(365). `collections=0` 이면 **실제 결함**(DB명·자격증명·접속) |
| `Illegal option -o pipefail` | `command` 가 `/bin/sh` 로 되어 있다. `mongo` 이미지의 sh 는 dash 다 → `/bin/bash` 로 |
