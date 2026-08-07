# infra/cron — 컷백(k3s → docker-compose) 기간 정기작업

> 작성 2026-08-07 · 관련: 컷백 계획 `_workspace/cutback_infra_compose-plan.md` §6-1 · 원본 `infra/k8s/base/cronjobs.yaml`
>
> **한 줄 요약: k3s 를 내리면 백업 3종과 TLS 갱신이 함께 멈춘다. 이 디렉터리가 그 자리를 호스트 cron 으로 메운다.**

컷백은 배포 형태만 바꾸는 일이 아니다. k8s CronJob 은 클러스터와 **함께** 멈추므로,
아무 조치 없이 컷백하면 그날부터 아동 데이터의 백업이 남지 않는다(CLAUDE.md 9절 —
데이터 수명주기·복구력). 이 디렉터리는 그 공백을 없애기 위한 것이다.

---

## 1. 무엇을 무엇으로 옮겼나

| k8s CronJob | 스케줄(원본) | → 대체 스크립트 | 스케줄(호스트 cron) |
|---|---|---|---|
| `db-backup` | KST 04:00 (`timeZone: Asia/Seoul`) | `dodam-db-backup.sh` | KST 04:00 — **동일** |
| `mongo-backup` | KST 04:30 | `dodam-mongo-backup.sh` | KST 04:30 — **동일** |
| `minio-backup` | KST 00:30·06:30·12:30·18:30 | `dodam-minio-backup.sh` | 동일 |
| `certbot-renew` | `17 3,15` (**UTC** = KST 12:17·00:17) | `dodam-certbot-renew.sh` | `17 3,15` (KST 03:17·15:17) |
| `manifest-drift-check` | 매시 | **이관 안 함** — §5 | — |

### 그대로 보존한 계약

산출물의 **이름·내용·암호화 파라미터가 원본과 완전히 같아야** 기존 복원 절차가 그대로 먹는다.
그래서 아래는 한 글자도 바꾸지 않았다:

- 파일명 `b209-<STAMP>.sql.gz.enc` · `mongo-<STAMP>.tar.gz.enc` · `minio-<STAMP>.tar.gz.enc`
- `STAMP = date +%F-%H%M`, TZ=Asia/Seoul
- 암호화 `openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000`
- 저장 경로 `/var/backups/dodam` (root 700) · 보관 `-mtime +14 -delete`
- mongo 3분기 판정 — `collections=0` FAIL / `bytes<200` FAIL / `documents=0` **WARN(성공)**
- minio `--exclude "tts-cache/*"` · tar 레이아웃(`-C <stage> .`, mongo 는 `-C <work> dump`)

### 바뀐 것은 "어떻게 닿는가"뿐

| | k8s CronJob | 컷백 스크립트 |
|---|---|---|
| MySQL | 파드에서 `mysqldump -h mysql` | `docker exec dodam-mysql` → 컨테이너 안 127.0.0.1 |
| Mongo | 파드에서 `mongodump --host mongodb` | `docker exec dodam-mongodb` → 127.0.0.1 |
| MinIO | initContainer(mc) → 클러스터 DNS | `docker run --network dodam_dodam-net` 일회용 mc |
| 자격증명 | k8s Secret 참조 | **돌고 있는 컨테이너의 env** 에서 직접 읽음 |
| 암호 | Secret `dodam-backup` → `-pass env:` | 호스트 파일 → `-pass file:` (§2) |

---

## 2. ⚠️ 선행 조건 — 백업 패스프레이즈

`BACKUP_PASSPHRASE` 는 k8s Secret `dodam-backup` 에만 있었다. **k3s 를 내리면 kubectl 로
꺼낼 수 없다.** 컷오버 전에 호스트로 빼 둔 파일을 스크립트가 읽는다:

```
PASS_FILE 기본값 = /home/kr/.dodam-backup-pass   (600, 44바이트)
```

- `-pass file:` 은 **첫 줄만** 읽고 줄바꿈을 버린다 → Secret 값(개행 없는 44바이트)과 같은 키가 된다.
  기존 복원 스크립트(`mysql-restore.sh`·`minio-restore.sh`)도 같은 `file:` 방식을 쓴다.
- 파일이 없거나 첫 줄이 비어 있으면 스크립트는 **즉시 실패한다(exit 3).**
  무암호 백업으로 폴백하지 않는다 — 아동 그림·음성·발화 원문이 들어가는 파일이다.
- 이 값을 잃으면 **기존 백업 전부가 복호화 불가**가 된다. 앱 비밀과 수명주기가 다른 이유다.

### ★ 설치 전에 반드시 1회: 이 패스프레이즈가 옛 백업을 여는가

"백업이 돌았다"는 검증이 아니다. **복원되는 것만이 검증이다.**
새 cron 을 믿기 전에 기존 산출물로 키가 맞는지 확인한다(읽기 전용):

```bash
LAST=$(sudo ls -1t /var/backups/dodam/b209-*.sql.gz.enc | head -1)
sudo openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 \
  -pass file:/home/kr/.dodam-backup-pass -in "$LAST" | gzip -t && echo "PASSPHRASE OK"
```

`gzip -t` 가 통과하면 키가 맞는 것이다. 실패하면 **설치를 멈추고** 패스프레이즈 출처부터 다시 볼 것.

> 하드닝(권장): 패스프레이즈를 root 소유로 옮기고 스크립트에 경로를 지정한다.
> ```bash
> sudo install -d -m 700 -o root -g root /etc/dodam/secrets
> sudo install -m 600 -o root -g root /home/kr/.dodam-backup-pass /etc/dodam/secrets/backup-passphrase
> # 이후 cron 줄에 PASS_FILE=/etc/dodam/secrets/backup-passphrase 를 앞에 붙이거나
> # 스크립트의 기본값을 그 경로로 바꾼다. 옮긴 뒤에도 위 검증을 한 번 더 돌릴 것.
> ```

---

## 3. 설치 (컷오버 직후 · 사람이 실행)

```bash
cd /home/kr/S15P11B209

# 3-1. 스크립트를 root 소유 경로로 복사한다.
#      리포지토리에서 직접 실행하지 않는 이유: cron 이 도는 도중 git checkout·머지가
#      스크립트를 바꿔치기할 수 있고, root 가 일반 계정 소유 파일을 실행하게 된다.
sudo install -d -m 755 -o root -g root /opt/dodam/cron
sudo install -m 755 -o root -g root infra/cron/lib.sh                 /opt/dodam/cron/lib.sh
sudo install -m 755 -o root -g root infra/cron/dodam-db-backup.sh     /opt/dodam/cron/
sudo install -m 755 -o root -g root infra/cron/dodam-mongo-backup.sh  /opt/dodam/cron/
sudo install -m 755 -o root -g root infra/cron/dodam-minio-backup.sh  /opt/dodam/cron/
sudo install -m 755 -o root -g root infra/cron/dodam-certbot-renew.sh /opt/dodam/cron/

# 3-2. 로그 디렉터리
sudo install -d -m 750 -o root -g root /var/log/dodam

# 3-3. 백업 디렉터리(이미 있음 — 없을 때만)
sudo install -d -m 700 -o root -g root /var/backups/dodam

# 3-4. 손으로 1회씩 돌려 본다 — cron 에 걸기 전에. (--verify 는 복호화까지 확인)
sudo /opt/dodam/cron/dodam-db-backup.sh    --verify
sudo /opt/dodam/cron/dodam-mongo-backup.sh --verify
sudo /opt/dodam/cron/dodam-minio-backup.sh --verify
sudo /opt/dodam/cron/dodam-certbot-renew.sh --dry-run

# 3-5. 위 4개가 전부 통과한 뒤에만 cron 에 건다.
sudo install -m 644 -o root -g root infra/cron/dodam-compose.cron /etc/cron.d/dodam-compose

# 3-6. 확인
sudo systemctl status cron --no-pager | head -5
sudo run-parts --test /etc/cron.d 2>/dev/null || true    # 파일이 파싱되는지(선택)
journalctl -t dodam-db-backup -n 20 --no-pager
```

> ⚠️ 3-4 를 건너뛰지 말 것. 원본 `mongo-backup` CronJob 은 작성 이후 **한 번도 돈 적이 없었고,
> 그 사이 1행에서 죽는 상태**였다(dash 에 `pipefail` 이 없어서). suspend 로 잠겨 있어 아무도
> 몰랐다 — "존재한다"와 "동작한다"는 다르다.

---

## 4. 롤백 (k3s 로 되돌릴 때)

```bash
# 1) 호스트 cron 을 먼저 끈다  ← 순서가 중요하다
sudo rm -f /etc/cron.d/dodam-compose

# 2) 그 다음 k3s 를 올린다. prod overlay 의 cronjobs-enable.yaml 이 CronJob 3종을 다시 켠다.
sudo systemctl enable --now k3s
kubectl -n dodam get cronjob
```

**두 벌을 동시에 켜지 말 것.** 같은 04:00 에 두 벌이 돌면 DB 부하가 두 배인 것으로 끝나지
않는다. STAMP 형식이 같아 **같은 파일명**을 두고 경쟁하고, 한쪽의 `.part → mv` 가 다른 쪽
산출물을 덮어쓴다. (원본 `overlays/prod/cronjobs-enable.yaml` 의 경고와 같은 사유 — 방향만 반대)

---

## 5. 이관하지 않은 것 · 컷백 중 꺼지는 것

| 항목 | 상태 | 왜 / 대응 |
|---|---|---|
| `manifest-drift-check` CronJob | **비활성** | git 매니페스트와 **클러스터 상태**의 차이를 감시하는 잡이다. 클러스터가 없으면 감시 대상 자체가 없다. 컷백 중 compose 쪽 드리프트는 `docker compose config` 와 `.env.compose` 로만 관리된다 — 즉 **자동 감시가 없는 상태**임을 알고 있을 것. (원본 잡은 최근 3회 Error 상태이기도 하다 — 계획서 R13) |
| Prometheus·Grafana·Alertmanager | 비활성 | 컷백 범위 밖(계획서 R7). 백업 실패는 경보가 아니라 **로그로만** 드러난다 → 아침에 `journalctl -t dodam-db-backup -S -1d` 를 한 번 볼 것 |
| `mysql-restore.sh` · `minio-restore.sh` | **컷백 중 동작 안 함** | 두 스크립트는 `kubectl port-forward`·`statefulset/…` 를 전제한다. 컷백 기간의 복원은 §6 수동 절차로 한다 |

---

## 6. 컷백 기간의 복원 (수동 · 필요할 때만)

> 아래는 **제안 절차**다. 실행 전 반드시 현재 데이터를 먼저 백업할 것(복원은 되돌릴 수 없다).

```bash
# ── MySQL ───────────────────────────────────────────────────────────────────
F=/var/backups/dodam/b209-<STAMP>.sql.gz.enc
sudo openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 \
  -pass file:/home/kr/.dodam-backup-pass -in "$F" | gzip -t          # ① 먼저 무결성만 확인
sudo openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 \
  -pass file:/home/kr/.dodam-backup-pass -in "$F" | gunzip \
  | docker exec -i dodam-mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root'
#   ★ DB명을 지정하지 않는다 — 덤프에 --databases 로 CREATE/USE 가 들어 있다.

# ── MinIO ───────────────────────────────────────────────────────────────────
F=/var/backups/dodam/minio-<STAMP>.tar.gz.enc
S=$(mktemp -d); sudo chmod 700 "$S"
sudo openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 \
  -pass file:/home/kr/.dodam-backup-pass -in "$F" | sudo tar -C "$S" -xzf -
#   그 뒤 mc 로 되돌린다(비파괴 overwrite). 자격증명은 컨테이너에서 읽는다:
#   docker run --rm --network dodam_dodam-net -v "$S:/stage" --entrypoint /bin/bash \
#     minio/mc:RELEASE.2025-04-16T18-13-26Z -c 'mc alias set dst http://minio:9000 "$U" "$P"; mc mirror --overwrite /stage dst/dodam'
sudo rm -rf "$S"     # ★ 평문 아동 데이터 — 반드시 지운다

# ── MongoDB ─────────────────────────────────────────────────────────────────
#   복호화 → tar 해제 → docker cp → mongorestore. 평문 덤프를 호스트에 남기지 말 것.
```

---

## 7. 남은 리스크

| # | 리스크 | 대응 |
|---|---|---|
| C1 | 패스프레이즈 파일이 `/home/kr` 에 있다(소유자 kr) — root cron 이 일반 계정 소유 파일을 읽는다 | §2 하드닝으로 `/etc/dodam/secrets` 로 이전 권장. (kr 은 docker 그룹 = 사실상 root 라 **새로운** 권한 상승은 아니다) |
| C2 | 백업 실패가 **경보로 오지 않는다**(모니터링 정지) | 매일 `journalctl -t dodam-db-backup -t dodam-mongo-backup -t dodam-minio-backup -S -1d` 확인. 컷백이 하루를 넘기면 필수 |
| C3 | 컷백 중 복원 스크립트가 안 돈다 | §6 수동 절차. 컷백이 하루를 넘기면 산출물 1개로 **복원 드릴 1회** 수행(733 과 같은 규정) |
| C4 | `/var/log/dodam/*.log` 무한 증가 | 한 줄짜리 logrotate 로 충분: `sudo tee /etc/logrotate.d/dodam <<<'/var/log/dodam/*.log { weekly rotate 8 compress missingok notifempty }'` |
| C5 | certbot 갱신 경로가 **컷백 중 한 번도 실증되지 않는다**(만료 2026-10-20, 갱신 창 진입 2026-09-20) | 설치 시 `--dry-run` 으로 배선만 확인. 컷백이 9월까지 이어질 계획이면 그 전에 실 갱신 1회를 확인할 것 |
| C6 | mongodump 가 `--password` 를 argv 로 받는다(컨테이너 안 `ps` 노출) | 원본 CronJob 과 동일한 제약. 실질 통제는 호스트 docker 접근 최소화 |
