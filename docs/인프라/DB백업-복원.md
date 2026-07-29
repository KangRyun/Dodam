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

## 3. cron 등록 (매일 04:00 KST)

서버 타임존 확인부터 — cron은 **서버 로컬 시간** 기준으로 돈다.

```bash
timedatectl | grep "Time zone"   # → Asia/Seoul (KST, +0900) 이어야 아래 04:00이 새벽 4시
```

(2026-07-23 확인: 이 서버는 `Asia/Seoul` — 그대로 진행. UTC라면 `0 19 * * *`로 환산 필요.)

root crontab에 등록 (패스프레이즈·백업 디렉토리가 root 전용이므로 root cron 필수):

```bash
sudo crontab -e
# 아래 한 줄 추가 — 새벽 4시: 트래픽 최저 시간대 + Jenkins 배포와 겹치지 않음
0 4 * * * /home/kr/S15P11B209/infra/scripts/mysql-backup.sh >> /var/log/dodam-backup.log 2>&1
```

등록 확인: `sudo crontab -l` · 로그 확인: `sudo tail /var/log/dodam-backup.log`
(성공 시 `[mysql-backup] OK db=b209 file=... size=... elapsed=...s` 한 줄이 남는다.)

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

- **월 1회** 복원 드릴 수행 — 최신 백업으로 `--dry-run` + 스테이징(별도 컨테이너) 실복원까지.
- **1회차 = Day 5 스테이징 복원** (k3s 컷오버 Day 6 전날). 컷오버 안전망이 실제로 작동하는지
  본번 전에 검증하는 것이 이 드릴의 존재 이유.
- 드릴 결과(일시·파일명·성공 여부·소요 시간)는 본 문서 하단이나 팀 노션에 한 줄씩 기록.

| 회차 | 일시 | 백업 파일 | 결과 | 비고 |
|------|------|-----------|------|------|
| 1 | (Day 5 예정) | | | k3s 컷오버 전 스테이징 복원 |

---

## 7. 취급 규정 (타협 불가)

- 백업 파일·패스프레이즈의 **복사·전송 금지** — scp/이메일/채팅/클라우드 업로드 전부 금지.
  아동 민감정보 원본이며, 반출 시점부터 수명주기(자동 삭제) 통제를 벗어난다.
- 열람·복원은 **Infra 담당(root)** 만. 다른 팀원에게 필요한 건 백업 "존재 여부"뿐, 내용이 아니다.
- 보관 기간(14일) 초과분은 스크립트가 자동 삭제 — 수동으로 따로 빼두지 않는다.
- **k3s 전환 시(Day 6 이후)**: 이 cron 체계는 k3s **CronJob으로 이전 예정**. 이전 완료 전까지는
  현행 cron을 유지하고, 이전 후 root crontab에서 제거한다. 패스프레이즈는 k8s Secret이 아닌
  노드 로컬 파일 유지 여부를 이전 시점에 재결정(etcd 평문 저장 이슈 검토).

---

## 8. 장애 시 빠른 참조

| 증상 | 종료코드 | 조치 |
|------|----------|------|
| `root로 실행해야` | 2 | `sudo`로 재실행 / root cron 확인 |
| `패스프레이즈 파일이 없습니다` | 3 | §2 사전 준비 수행 |
| `패스프레이즈 파일 권한 오류` | 3 | `chown root:root` + `chmod 600` |
| `백업 디렉토리가 없습니다/권한 오류` | 4 | `install -d -m 700 -o root -g root /var/backups/dodam` |
| `컨테이너가 실행 중이 아닙니다` | 5 | `docker ps` 확인, compose 기동 후 재시도 |
| 파이프라인 실패(덤프/복호화) | 6 | 로그 확인 — 디스크 용량(`df -h`), 패스프레이즈 일치 여부(`--dry-run`) 순서로 점검 |
