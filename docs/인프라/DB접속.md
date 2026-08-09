# DB·저장소 접속 가이드 (docker-compose 컷백 기준)

> 대상: EC2 `i15b209.p.ssafy.io` 의 docker-compose 스택 —
> `dodam-mysql`(MySQL 8.4.10) · `dodam-mongodb`(MongoDB 8.0.4) · `dodam-redis`(Redis 7.4.8) · `dodam-minio`(MinIO RELEASE.2025-04-22)
> 관련 문서: 백업·복원은 [DB백업-복원.md](DB백업-복원.md) · [MinIO백업-복원.md](MinIO백업-복원.md), 저장소 설계는 [../database/저장소-아키텍처.md](../database/저장소-아키텍처.md)
> ⚠️ **이 DB의 내용 = 아동의 그림·대화·감정 기록.** 조회 자체가 민감정보 열람이다. (CLAUDE.md 9절 가드레일)

---

> ## ⚠️ 이 문서는 **compose 컷백 기간** 기준이다
>
> **2026-08-07 컷백(S15P11B209, `feature/infra-compose-cutback-bluegreen`):** 운영을
> **k3s → docker-compose 로 컷백**했다. 저장소 4종은 이제 **k3s StatefulSet 이 아니라
> docker-compose 컨테이너**로 뜬다. 그래서 접근 방식이 바뀌었다 — `kubectl exec` / `kubectl
> port-forward` / NodePort 는 **더 이상 동작하지 않는다.** 지금은 `docker exec` 또는 **SSH 터널**이다.
>
> **이 컷백은 발표용 임시 상태이고, 팀 운영 기준은 여전히 k3s 다.** k3s 로 롤백하면 접근법이
> `kubectl` 기반으로 되돌아간다 — 그 절차는 삭제하지 않고 **[부록 A: k3s 롤백 시 접근법](#부록-a-k3s-롤백-시-접근법)** 에 보존했다.
> 데이터는 컷백/롤백 양쪽이 **같은 호스트 디렉터리**를 쓰므로 이어진다.

---

## 0. 무엇이 열려 있고 무엇이 닫혀 있는가

**저장소 4종 어느 것도 호스트에 포트를 열지 않는다.** compose 에서 `mysql·mongodb·redis·minio`
는 `expose` 만 있고 `ports:`(호스트 publish)가 **없다**. 외부에 열린 포트는 **게이트웨이(nginx)의
80/443 과 SSH 의 22 뿐**이다.

```
$ docker ps --format '{{.Names}} => {{.Ports}}'
dodam-nginx     => 0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp   ← 유일한 외부 입구
dodam-mysql     => 3306/tcp, 33060/tcp        ← expose 만. 호스트에 안 붙는다
dodam-mongodb   => 27017/tcp
dodam-redis     => 6379/tcp
dodam-minio     => 9000/tcp
```

| 결정 | 이유 |
|------|------|
| **저장소 4종 노출 0** | 안에 든 것이 아동의 그림·대화·감정 기록이다. 외부 관문은 nginx 80/443 과 SSH 22 뿐 |
| **컨테이너 간 통신은 도커 내부 네트워크** | 앱은 `dodam_dodam-net` 안에서 서비스명(`mysql:3306` · `mongodb:27017` · `redis:6379` · `minio:9000`)으로만 접근한다 (§4) |
| **사람의 접속은 SSH 를 거친다** | 접근 경로를 SSH 계정으로 좁혀 인증·감사 지점을 단일화. 사람의 경로는 딱 두 가지 — §2(서버에서 `docker exec`) · §3(로컬 PC 에서 SSH 터널) |
| **비밀번호는 컨테이너 env 를 재사용** | 아래 명령들은 비밀번호를 **입력하지도, 호스트 셸에 남기지도 않는다.** 히스토리·`ps` 노출을 원천 차단 |

> ### 🚫 반복 금지 사례 — MySQL NodePort 30306 (S15P11B209-970)
> 2026-07-31, 외부 GUI 에서 바로 붙으려고 k3s 시절 **MySQL 을 NodePort 30306 으로 인터넷에
> 직접 열었다.** 08-06 에 회수했다(970). 노출면이 0 이 아니게 되는 순간 계정 비밀번호가
> 아동 데이터의 **유일한 방어선**이 된다. **compose 에서도 저장소에 `ports:` 를 추가하지 않는다.**
> 사람이 붙어야 하면 §2·§3 로 충분하다.

### 접속 정보(계정·비밀번호)의 원본

`infra/.env.compose`(git 비추적, 권한 `600`) 한 곳뿐이다. 컨테이너는 이 값을 env 로 물고 뜬다.
**어떤 값도 문서·이슈·메신저에 옮겨 적지 않는다.** 아래 표의 계정 열은 **env 변수 이름**이다.

| 대상 | 컨테이너 | DB/버킷 | 계정(값은 `.env.compose` 참조) |
|------|----------|---------|-------------------------------|
| MySQL | `dodam-mysql` | `$MYSQL_DATABASE`(=`b209`) | 앱: `$MYSQL_USER` / `$MYSQL_PASSWORD` · 관리: `root` / `$MYSQL_ROOT_PASSWORD` |
| MongoDB | `dodam-mongodb` | `$MONGO_INITDB_DATABASE`(=`dodam`) | 관리: `$MONGO_INITDB_ROOT_USERNAME` / `$MONGO_INITDB_ROOT_PASSWORD` (인증 DB `admin`) · 앱: `$MONGO_APP_USERNAME` / `$MONGO_APP_PASSWORD` (인증 DB `dodam`) |
| Redis | `dodam-redis` | DB 0 | 비밀번호 `$REDIS_PASSWORD` |
| MinIO | `dodam-minio` | 버킷 `dodam` | 관리: `$MINIO_ROOT_USER` / `$MINIO_ROOT_PASSWORD` · 앱: `$MINIO_BE_USER` / `$MINIO_BE_PASSWORD` |

> ⚠️ **MongoDB 만 env 이름이 다르다.** mongo 이미지가 `MONGO_INITDB_*` 라는 이름을 요구하기
> 때문에 컨테이너 안의 root 계정 변수는 **`MONGO_INITDB_ROOT_USERNAME` · `MONGO_INITDB_ROOT_PASSWORD`
> · `MONGO_INITDB_DATABASE`** 다(앱 계정은 `MONGO_APP_*` 그대로). `.env.compose` 의 Secret 키 이름
> (`MONGO_ROOT_USERNAME` 등)을 컨테이너 안에서 그대로 쓰면 **빈 값**이 되고, mongosh 는 인증 없이
> 기본 `test` DB 에 붙어 "접속된 것처럼" 보인다 — 실제로는 `listCollections` 단계에서야 실패한다(§2-4).

---

## 1. 접근 경로는 둘뿐

| 경로 | 누가 | 언제 | 절 |
|------|------|------|----|
| ① **컨테이너 직접** (`docker exec`) | 서버에 SSH 로 들어온 팀 계정(전원 `docker` 그룹) | 서버 안에서 CLI 로 빠르게 조회 | §2 |
| ② **SSH 터널** | 로컬 PC 에서 GUI(DBeaver·Compass 등)·CLI 로 붙을 때 | 내 PC 도구로 붙어야 할 때 | §3 |

`sudo` 도 `kubectl` 도 필요 없다 — 팀 계정은 전부 `docker` 그룹이다. (k3s 시절엔 `kubectl` 이
`kr` 만 됐지만, compose 에서는 `docker exec` 로 통일됐다.)

---

## 2. 서버에서 직접 접속 — `docker exec`

서버에 SSH 로 들어와서 컨테이너 안의 클라이언트를 그대로 쓴다. 비밀번호는 **컨테이너 env 를
재사용**하므로 명령줄에도 히스토리에도 남지 않는다.

### 2-1. MySQL

**앱 계정(`$MYSQL_USER`) — 평상시 조회는 이걸 쓴다. `--default-character-set=utf8mb4` 필수.**

```bash
docker exec -it dodam-mysql sh -c \
  'MYSQL_PWD="$MYSQL_PASSWORD" mysql --default-character-set=utf8mb4 -u"$MYSQL_USER" "$MYSQL_DATABASE"'
```

> ⚠️ **`--default-character-set=utf8mb4` 를 빠뜨리면 한글이 깨진다.** 아이 발화·리포트 본문이
> `?????` 로 보인다. 데이터가 아니라 **표시**의 문제이므로, 놀라서 데이터를 건드리지 말 것.

**root — 계정·권한·스키마 관리가 필요할 때만.**

```bash
docker exec -it dodam-mysql sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --default-character-set=utf8mb4 -uroot'
```

단발 쿼리는 `-e` 로:

```bash
docker exec dodam-mysql sh -c \
  'MYSQL_PWD="$MYSQL_PASSWORD" mysql --default-character-set=utf8mb4 -u"$MYSQL_USER" "$MYSQL_DATABASE" -e "SHOW TABLES;"'
```

> ⚠️ **계정과 비밀번호를 섞지 말 것.** `MYSQL_PWD="$MYSQL_PASSWORD"` 는 앱 계정(`$MYSQL_USER`)용,
> `MYSQL_PWD="$MYSQL_ROOT_PASSWORD"` 는 `-uroot` 용이다. 섞으면 `ERROR 1045 (using password: YES)` 가
> 나는데, "전달은 됐다"는 뜻이라 값이 틀린 줄 알고 엉뚱한 곳을 뒤지게 된다.

### 2-2. Redis

```bash
docker exec -it dodam-redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'
```

`--no-auth-warning` 은 "명령줄 비밀번호 경고"를 끄는 옵션이다. 값이 셸 히스토리가 아니라
컨테이너 env 에서 오므로 호스트에 남지 않는다.

```bash
# 키 개수·메모리 확인 (단발)
docker exec dodam-redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO keyspace'
```

⚠️ 운영 Redis 에서 `KEYS *` 는 쓰지 않는다(전 키 스캔 = 블로킹). 필요하면 `SCAN` 을 쓴다.

### 2-3. MinIO

minio 이미지 안에는 `mc` 가 들어 있다. localhost:9000 이 곧 이 컨테이너의 MinIO API 다.

```bash
# 버킷 목록
docker exec dodam-minio sh -c \
  'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls l'

# 프리픽스별 객체 확인 (images/ audio/ tts-cache/ reports/ evidences/)
docker exec dodam-minio sh -c \
  'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls --summarize l/dodam/images/'
```

⚠️ 객체를 **내려받지 않는다.** 파일 자체가 아동의 그림·음성 원본이다. 목록·용량 확인까지만.

> `mc alias set` 에 URL 대신 **인자를 분리**해 넘기는 것은 의도적이다. 비밀번호에 `@ : /` 가
> 들어가면 URL 형식(`http://user:pass@host`)이 조용히 다른 호스트를 가리킨다.

### 2-4. MongoDB

**root 로 (관리 작업용) — 인증 DB 는 `admin`:**

```bash
docker exec -it dodam-mongodb sh -c \
  'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
           --authenticationDatabase admin "$MONGO_INITDB_DATABASE"'
```

**앱 계정으로 (평상시 조회 — 최소권한) — 인증 DB 는 `dodam`:**

```bash
docker exec -it dodam-mongodb sh -c \
  'mongosh -u "$MONGO_APP_USERNAME" -p "$MONGO_APP_PASSWORD" \
           --authenticationDatabase "$MONGO_INITDB_DATABASE" "$MONGO_INITDB_DATABASE"'
```

⚠️ **`--auth` 라 자격증명이 반드시 필요하다.** 그리고 `--authenticationDatabase` 를 빠뜨리면
"인증 실패"가 아니라 **"사용자 없음"**으로 나와 원인을 헷갈린다. **root 는 `admin` DB, 앱 계정은
`dodam` DB** 에 있다 — 값이 다르다. (§0 의 env 이름 함정도 함께 볼 것.)

---

## 3. 로컬 PC 에서 SSH 터널로 붙기 (GUI·CLI)

저장소가 호스트에 포트를 열지 않으므로(§0), 컨테이너의 포트는 **도커 브리지 네트워크
(`dodam_dodam-net`, 예: `172.18.0.x`) 위에만** 있다. 로컬 PC 에서 붙으려면 SSH 로 들어가
그 **컨테이너 IP:포트**로 포워딩한다. (k3s 시절의 `127.0.0.1:3307` 상시 터널은 compose 에는 없다.)

```
내 PC (GUI/CLI) ──SSH:22──▶ 서버 ──▶ <컨테이너 IP>:3306 (dodam_dodam-net)
                                  └─ 여기부터는 서버 안이다. 밖에서 닿을 수 없다.
```

### 3-1. 컨테이너 IP 를 먼저 확인한다

컨테이너가 재생성되면 IP 가 바뀔 수 있다. 붙기 직전에 확인한다.

```bash
# 서버에서
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dodam-mysql
# 예: 172.18.0.5   ← 이 값을 아래 터널의 목적지로 쓴다
```

### 3-2. 터미널에서 (로컬 포워딩)

```bash
# 이 창은 켜 둔 채로 — 13306 은 내 PC 쪽 임의 포트(로컬 MySQL 과 안 겹치게)
ssh -N -L 13306:"$(ssh <내계정>@i15b209.p.ssafy.io \
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dodam-mysql)":3306 \
  <내계정>@i15b209.p.ssafy.io

# 다른 창에서
mysql -h 127.0.0.1 -P 13306 --default-character-set=utf8mb4 -u <MYSQL_USER 값> -p b209
```

다른 저장소도 목적지 포트만 바꾼다: MongoDB `27017` · Redis `6379` · MinIO API `9000`.

> 서버에서 CLI 만 필요하다면 터널을 안 쓰고 `docker exec`(§2)가 더 간단하다. 또는 같은
> 네트워크에 1회용 클라이언트를 띄워도 된다(서비스 별칭으로 해석됨):
> ```bash
> docker run --rm -it --network dodam_dodam-net mysql:8.4.10 \
>   mysql -h mysql --default-character-set=utf8mb4 -u <MYSQL_USER 값> -p b209
> ```

### 3-3. GUI 툴 (DBeaver·Workbench·IntelliJ·Compass)

GUI 내장 SSH 터널은 "서버에 들어간 뒤 **서버 기준 주소**로 붙는" 구조다. 그 주소로 **§3-1 에서
확인한 컨테이너 IP** 를 넣는다.

| 탭 | 항목 | 값 |
|----|------|-----|
| **SSH** | Host / Port | `i15b209.p.ssafy.io` / `22` |
| **SSH** | User / 인증 | 각자 계정 / 비밀번호 |
| **Main** | Host / Port | `<§3-1 컨테이너 IP>` / `3306` ← **서버 기준 주소**. 내 PC 의 것이 아니다 |
| **Main** | Database | `b209` |
| **Main** | User / Password | `$MYSQL_USER` 값 / `$MYSQL_PASSWORD` 값 |

MySQL 드라이버 속성 두 개를 함께 넣는다(넣는 곳은 툴마다 다르다):

```
sslMode            = REQUIRED
connectionTimeZone = Asia/Seoul
```

**GUI 함정 셋:**

1. **`Public Key Retrieval is not allowed` 가 뜨면 `allowPublicKeyRetrieval=true` 로 끄지 말 것.**
   그 에러는 "권한 부족"이 아니라 **TLS 가 꺼졌다**는 신호다. MySQL 8.4 의 기본 인증
   플러그인(`caching_sha2_password`)은 평문 연결이면 서버 공개키를 따로 받아와야 하는데 그
   요청이 기본 거부라 나는 것이다. `sslMode=REQUIRED` 를 제대로 넣으면 애초에 뜨지 않는다.
2. **시각을 변환하지 말 것.** DB 값은 이미 KST 다(§5). `connectionTimeZone=Asia/Seoul` 을 안 잡으면
   드라이버가 저장값을 UTC 로 착각해 화면에서 **9시간 밀어** 보여 준다.
3. **읽기 전용으로 걸어 둘 것.** 운영 DB 직접 DML/DDL 은 §7 금지 사항이다. DBeaver 는 연결 편집
   창에서 `Read-only connection` 체크. 실수로 `UPDATE` 를 커밋하는 사고를 **구조적으로** 막는다.

> ⚠️ **컨테이너 IP 를 GUI 에 고정 저장하면 재생성 후 붙지 않을 수 있다.** 붙기 전에 §3-1 로
> 다시 확인한다. IP 가 자주 바뀌어 번거로우면 §2 의 `docker exec` 를 권장한다.

---

## 4. 앱 → DB 는 어떻게 붙는가 (내부 네트워크)

앱 컨테이너는 사람과 다른 경로다. 전부 도커 내부 네트워크 **`dodam_dodam-net`** 위에서
**서비스명(별칭)** 으로 붙는다 — 호스트 포트를 거치지 않는다.

| 앱 | 대상 | 접근 주소(별칭) |
|----|------|----------------|
| backend | MySQL / Redis / MongoDB / MinIO | `mysql:3306` · `redis:6379` · `mongodb:27017` · `minio:9000` |
| ai | (파일은 BE 프록시 경유) | — |

- 앱 계층은 **blue-green 무중단 배포**라 컨테이너 이름이 `dodam-backend-blue`/`-green`,
  `dodam-ai-*`, `dodam-web-*` 로 색이 번갈아 뜬다. DB 4종·nginx 는 단일 컨테이너다.
- **backend ↔ ai 내부 호출은 공유 시크릿 `AI_INTERNAL_TOKEN`(헤더 `X-Internal-Token`)** 으로 인증한다.
- **MinIO 파일 접근은 presigned URL 이 아니라 BE 프록시 스트리밍**이다 — 매 요청마다
  JWT + 보호자-아동 관계·전문가 열람 범위를 검증하고 중계한다(`StreamingResponseBody`,
  `Cache-Control: private, no-store`). AI 의 이미지 접근도 BE 가 발급하는 **1회용 소비형 토큰
  URL**(Redis, TTL 60초, 내부망 전용)로만 이뤄진다. 상세: [저장소 아키텍처 §3·§4](../database/저장소-아키텍처.md).
  > presigned URL 이 탈락한 이유: "URL 소지 = 접근"이라 아동 그림 URL 이 로그·공유로 새면
  > 요청별 인가가 우회되고, MinIO 외부 노출까지 필요해져 80/443 원칙이 깨진다(가드레일 9절).

---

## 5. ⏰ MySQL 의 시각은 **KST** 로 저장된다

**`SELECT created_at` 의 값은 그대로 한국 시간이다. 변환하지 말 것 — 변환하면 9시간 틀린다.**

compose 의 `dodam-mysql` 은 다음 인자로 뜬다(실측):

```
--character-set-server=utf8mb4  --collation-server=utf8mb4_unicode_ci  --default-time-zone=+09:00
```

- **`--default-time-zone=+09:00`** 이 서버 시간대를 KST 로 **선언적으로 고정**한다. 그래서
  `docker exec` 로 붙은 `mysql` CLI 세션도 이미 `+09:00` 이다 → k3s 시절 CLI 가 UTC 라서
  수동 INSERT 가 9시간 어긋나던 함정(§부록)이 **compose 에서는 구조적으로 없다.**
- 이름(`Asia/Seoul`) 대신 오프셋인 이유: 이미지에 시간대 테이블이 없어 이름을 주면 **서버가
  기동하지 못한다.**
- 앱은 내부적으로 UTC 로 일관되고(JDBC 드라이버가 양방향 변환) DB 에는 KST 가 저장된다.
  그래서 API 응답·파드 로그에서 UTC 를 보는 것은 정상이다.

> ⚠️ **롤백(→k3s) 시 주의:** 라이브 k3s StatefulSet 의 args 에는 이 인자가 없어, mysql 파드가
> 새로 뜨면 서버 tz 가 UTC 로 풀린다. 롤백 절차에서 시간대를 복구해야 한다(부록 A 하단).

---

## 6. 백업·복원 (compose crontab 으로 이관됨)

k3s CronJob 3종(db/mongo/minio backup)과 TLS 갱신은 **호스트 crontab
`/etc/cron.d/dodam-compose`** 로 이관됐다(스크립트: `/opt/dodam/cron/dodam-*.sh`). 스케줄·파일명
규약·암호화 파라미터·보관기간(14일)을 k8s CronJob 과 동일하게 맞춰 기존 복원 절차가 그대로 먹는다.

- 절차·복원 드릴: [DB백업-복원.md](DB백업-복원.md) · [MinIO백업-복원.md](MinIO백업-복원.md)
- 백업 패스프레이즈는 `/etc/dodam/secrets/backup-passphrase`(root 600). 이걸 잃으면 기존 백업 전부 복호화 불가.
- ⚠️ **k8s CronJob 과 compose crontab 을 동시에 켜지 말 것** — 같은 STAMP·같은 파일명을 두고 경쟁해 한쪽이 다른 쪽 산출물을 덮어쓴다.

---

## 7. ⚠️ 가드레일 (타협 불가)

- **조회 = 민감정보 열람.** 필요한 범위만 본다. 아동 그림·대화·리포트 본문을 화면 밖(캡처·복사·메신저 공유)으로 내보내지 않는다.
- **저장소 4종을 외부에 열지 않는다.** compose 에 `ports:` 를 추가하거나 SSH 포워딩을
  `0.0.0.0` 로 여는 것 전부 금지. 사람 접속은 §2·§3 로 충분하다. (30306 NodePort 회수 사례 §0.)
- **비밀번호를 명령줄에 직접 쓰지 않는다.** §2 처럼 컨테이너 env 를 재사용한다. 히스토리에 남았으면 `history -d` 로 지운다.
- **운영 DB 에 직접 DML/DDL 을 치지 않는다.** 스키마 변경은 Flyway 마이그레이션으로만. 부득이한 수정은 백업을 먼저 뜨고(§6) 진행한다.
- **`.env.compose` · 백업 파일 · 덤프를 서버 밖으로 복사하지 않는다.** git 커밋 금지.
- **옛 named 볼륨(`dodam_mysql-data` 등, 2026-07-29 컷오버 직전 상태)을 되살려 조회하지 않는다.** 지금 데이터는 §8 의 bind 경로다.

---

## 8. 데이터는 지금 어디에 있는가 (bind 마운트, 이관 예정)

컷백은 데이터를 **옮기지 않았다.** k3s local-path PVC 의 호스트 디렉터리를 그대로 **bind 마운트**한다.

| 컨테이너 | 마운트 지점 | 호스트 경로(PVC 실체) |
|----------|------------|----------------------|
| `dodam-mysql` | `/var/lib/mysql` | `/var/lib/rancher/k3s/storage/pvc-…_dodam_data-mysql-0` |
| `dodam-mongodb` | `/data/db` | `…/pvc-…_dodam_data-mongodb-0` |
| `dodam-minio` | `/data` | `…/pvc-…_dodam_data-minio-0` |
| `dodam-redis` | `/data` | `…/pvc-…_dodam_data-redis-0` |

> ⚠️ **네임드 볼륨 이관은 런북(계획)만 준비돼 있고 아직 실행하지 않았다.** 실행 전까지 데이터의
> 진실은 위 bind 경로다. 이관 계획 문서(`docs/인프라/DB볼륨-네임드이관.md`)는 작성 예정 상태.
> 이관을 실행하기 전에는 볼륨 정의를 함부로 named 로 되돌리지 말 것 — 옛 stale 볼륨을 물면
> **8일 묵은 데이터로 조용히 정상 동작**한다(가드레일 사고 부류).

---

## 9. 트러블슈팅

| 증상 | 원인·조치 |
|------|-----------|
| `docker exec` 가 `No such container: dodam-mysql` | 컨테이너 이름 오타이거나 스택이 안 떠 있다. `docker ps` 로 실제 이름 확인 |
| 한글이 `?????` 로 보인다 | `--default-character-set=utf8mb4` 누락(§2-1). 데이터가 아니라 표시 문제 — 데이터를 건드리지 말 것 |
| `ERROR 1045 (using password: YES)` | `MYSQL_PWD` 와 계정을 섞었다. 앱=`$MYSQL_PASSWORD`+`$MYSQL_USER`, root=`$MYSQL_ROOT_PASSWORD`+`-uroot` (§2-1) |
| Mongo 가 `test` DB 에 붙고 `requires authentication` | Secret 키 이름(`$MONGO_ROOT_USERNAME`)을 컨테이너 안에서 썼다 → 빈 값. **`$MONGO_INITDB_ROOT_USERNAME`** 을 쓸 것 (§0·§2-4) |
| MongoDB 조회가 "사용자 없음" | `--authenticationDatabase` 누락·불일치. root=`admin`, 앱 계정=`dodam` (§2-4) |
| 로컬 SSH 터널이 `Connection refused` | 목적지 컨테이너 IP 가 바뀌었다(재생성). §3-1 로 IP 재확인 후 다시 터널 |
| GUI `Public Key Retrieval is not allowed` | **TLS 가 꺼진 상태** 신호다. `allowPublicKeyRetrieval=true` 로 끄지 말고 `sslMode=REQUIRED` 를 넣는다 (§3-3) |
| GUI `Unknown database 'b209'` / 빈 목록 | Main 탭 Host 를 내 PC 기준으로 적었다. GUI 내장 SSH 터널의 Host 는 **서버 기준 컨테이너 IP** 다 (§3-3) |
| 시각이 9시간 어긋나 보인다 | **DB 값은 KST 다**(§5). 변환하지 말 것. 앱 로그·API 는 UTC 이므로 그 둘을 비교할 때만 9시간을 감안 |
| `kubectl` 명령이 전부 실패 | 정상이다 — 컷백 중 k3s 는 정지 상태다. `docker exec`(§2)를 쓴다. k3s 로 롤백했다면 부록 A |

---

## 10. 빠른 참조

```bash
# MySQL 셸 (한글 필수 옵션 포함)
docker exec -it dodam-mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql --default-character-set=utf8mb4 -u"$MYSQL_USER" "$MYSQL_DATABASE"'

# Redis 셸
docker exec -it dodam-redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'

# MinIO 버킷 목록
docker exec dodam-minio sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls l'

# MongoDB 셸 (★ env 이름이 MONGO_INITDB_* 다 · 인증 DB admin — §2-4 참조)
docker exec -it dodam-mongodb sh -c 'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "$MONGO_INITDB_DATABASE"'

# 컨테이너 상태 한눈에
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
```

---

## 부록 A. k3s 롤백 시 접근법

> **팀 운영 기준은 여전히 k3s 다.** 컷백을 되돌리면(`docker compose down` → `systemctl enable
> --now k3s`) 저장소는 다시 k3s StatefulSet 으로 뜨고, 접근법이 아래 `kubectl` 기반으로 돌아간다.
> 이 절은 그 상태를 위한 보존본이다. (컷백 중에는 `kubectl` 이 동작하지 않는다.)

### A-0. 준비 — `kubectl` (Infra 전용, `kr`·`yj` 만)

```bash
ssh kr@i15b209.p.ssafy.io
export KUBECONFIG=$HOME/.kube/config   # 비로그인 셸·bash 에서는 빠진다. 스크립트는 항상 명시
kubectl -n dodam get pod
```

팀원 대부분은 `kubectl` 이 안 된다(`k3s.yaml` 은 root 600, 개인 kubeconfig 미발급). k3s 시절
팀원용 경로는 **서버 루프백 `127.0.0.1:3307` 상시 터널(`dodam-mysql-tunnel.service`)** 로 붙는
GUI SSH 터널이었다 — MySQL 한정. Redis·MinIO·MongoDB 는 `kubectl port-forward` 가 필요했다.

### A-1. 서버에서 직접 — `kubectl exec` (워크로드 `sts/…`)

```bash
# MySQL (앱 계정)
kubectl -n dodam exec -it sts/mysql -- sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"'
# MySQL (root)
kubectl -n dodam exec -it sts/mysql -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'
# Redis
kubectl -n dodam exec -it sts/redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'
# MinIO
kubectl -n dodam exec sts/minio -- sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls l'
# MongoDB (root · admin) — env 이름은 MONGO_INITDB_*
kubectl -n dodam exec -it sts/mongodb -- sh -c 'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "$MONGO_INITDB_DATABASE"'
```

- 파이프로 바이너리 스트림(gzip 등)을 받을 때는 **`-t`(TTY)를 붙이지 않는다** — CRLF 변환으로 깨진다. 대화형 셸에만 `-it`.
- `kubectl exec` 안에서 따옴표를 중첩하면 SQL 이 조용히 깨진다. 긴 SQL 은 `-i` + stdin 으로 넘긴다.

### A-2. 로컬에서 — `kubectl port-forward` + SSH

```bash
# 서버에서 (창 유지)
kubectl -n dodam port-forward sts/redis   6380:6379    # Redis
kubectl -n dodam port-forward sts/minio   9001:9001    # MinIO 웹 콘솔
kubectl -n dodam port-forward sts/mongodb 27018:27017  # MongoDB
# 로컬에서 (별도 창)
ssh -N -L 6380:127.0.0.1:6380 kr@i15b209.p.ssafy.io
```

- ⚠️ `port-forward` 는 기본 `127.0.0.1` 바인딩이다. `--address 0.0.0.0` 을 붙이지 말 것 — 저장소가 서버 외부에 열린다.
- MySQL 은 `dodam-mysql-tunnel.service`(서버 루프백 3307)가 상시 떠 있어 port-forward 없이 GUI 내장 SSH 터널로 `127.0.0.1:3307` 에 붙는다. ⚠️ 유닛의 `--address 127.0.0.1` 을 `0.0.0.0` 으로 바꾸지 말 것.

### A-3. 롤백 시 MySQL 서버 시간대 복구 (필수)

라이브 k3s StatefulSet args 에는 `--default-time-zone=+09:00` 이 **없다.** 롤백으로 mysql 파드가
새로 뜨면 서버 tz 가 UTC 로 풀려, CLI·백업 스크립트·수동 조회만 9시간 어긋난다(앱은 JDBC
`sessionVariables` 덕에 정상으로 보여 증상이 조용하다). 롤백 후:

```bash
kubectl -n dodam get sts mysql -o jsonpath='{.spec.template.spec.containers[0].args}'
#  → --default-time-zone=+09:00 이 없으면 args 에 --type json 으로 add (patch --type merge 는 배열을 통째 교체하니 금지)
#     또는 임시로: mysql -e "SET GLOBAL time_zone='+09:00'"  (재시작하면 다시 UTC)
```

### A-4. k3s 시절 외부 개방/회수 기록 (S15P11B209-970)

2026-07-31 MySQL 을 NodePort 30306 으로 인터넷에 직접 열었다가 08-06 회수했다. UFW 는
NodePort 를 막지 못하고(DNAT 로 INPUT 을 우회), 소스 IP 화이트리스트도 SNAT·유동 IP 때문에
실효가 없었다. 결론은 "화이트리스트를 잘 걸자"가 아니라 **"입구 자체를 없앤다"** 였다 —
이 원칙은 compose 컷백에도 그대로 이어진다(§0·§7).
