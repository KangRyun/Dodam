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
0  4    * * *  root  /경로/infra/scripts/mysql-backup.sh  >> /var/log/dodam-backup.log 2>&1
30 */6  * * *  root  /경로/infra/scripts/minio-backup.sh  >> /var/log/dodam-backup.log 2>&1
```
- MinIO는 MySQL과 **시차(:30)** — 동시 I/O·CPU 경합 회피.
- **6시간 주기(00:30·06:30·12:30·18:30)** — 하루 1회면 최대 24시간의 백업 공백이 생긴다.
  2026-07-28 하루에만 파일이 30 → 70개로 늘었다. 낮에 디스크가 나가면 그날 그린 그림이
  전부 사라진다. 데이터가 작아(수백 KB) 주기를 올려도 부담이 거의 없다.
- 수동 1회: `sudo infra/scripts/minio-backup.sh`
- 성공 로그: `[minio-backup] OK bucket=dodam file=... objects=70 size=228K retention=14d exclude=tts-cache/*`

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

## ⚠️ 첫 실행 시 검증 필요 (리눅스 세션서 미검증 항목)

- `mc mirror --exclude "tts-cache/*"` 가 실제로 tts-cache를 건너뛰는지 (스테이지에 없어야 함)
- `mc ilm import` 지원 여부 (미지원 시 init 로그 WARN + 수동 적용 안내)
- 백업→`--dry-run` 복원 왕복 1회 성공

## 종료 코드

`0` 성공 / `2` root 아님·인자 / `3` 패스프레이즈 / `4` 백업 디렉토리·파일 / `5` minio 컨테이너 미기동 / `6` mirror·암복호화 파이프라인
