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

## 백업 (자동 — cron)

```
# /etc/cron.d/dodam-backup  (root)
0  4 * * *  root  /경로/infra/scripts/mysql-backup.sh  >> /var/log/dodam-backup.log 2>&1
30 4 * * *  root  /경로/infra/scripts/minio-backup.sh  >> /var/log/dodam-backup.log 2>&1
```
- MinIO는 MySQL과 **시차(04:30)** — 동시 I/O·CPU 경합 회피.
- 수동 1회: `sudo infra/scripts/minio-backup.sh`
- 성공 로그: `[minio-backup] OK bucket=dodam file=... size=... retention=14d exclude=tts-cache/*`

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

최신 백업으로 `--dry-run` 실행해 "복원 가능한 파일인지" 확인 → 결과를 팀 로그에 기록.
백업이 존재하는 것과 **복원되는 것**은 다르다 — 드릴로만 보장된다.

## ⚠️ 첫 실행 시 검증 필요 (리눅스 세션서 미검증 항목)

- `mc mirror --exclude "tts-cache/*"` 가 실제로 tts-cache를 건너뛰는지 (스테이지에 없어야 함)
- `mc ilm import` 지원 여부 (미지원 시 init 로그 WARN + 수동 적용 안내)
- 백업→`--dry-run` 복원 왕복 1회 성공

## 종료 코드

`0` 성공 / `2` root 아님·인자 / `3` 패스프레이즈 / `4` 백업 디렉토리·파일 / `5` minio 컨테이너 미기동 / `6` mirror·암복호화 파이프라인
