# DB·저장소 접속 가이드

> 대상: EC2 `i15b209.p.ssafy.io` 의 `dodam-mysql`(MySQL 8.4.10) · `dodam-redis`(Redis 7.4.8) · `dodam-minio`(MinIO)
> 관련 문서: 백업·복원은 [DB백업-복원.md](DB백업-복원.md), 저장소 설계는 [../database/저장소-아키텍처.md](../database/저장소-아키텍처.md)
> ⚠️ **이 DB의 내용 = 아동의 그림·대화·감정 기록.** 조회 자체가 민감정보 열람이다. (CLAUDE.md 9절 가드레일)

---

## 1. 전제 — 왜 "그냥 접속"이 안 되는가

`docker-compose.yml` 에서 **MySQL·Redis·MinIO 는 호스트 포트를 열지 않는다**(`ports:` 미선언).
외부에서 `mysql -h i15b209.p.ssafy.io -P 3306` 같은 직접 접속은 **설계상 불가능하며, 뚫으면 안 된다.**

| 결정 | 이유 |
|------|------|
| **DB·Redis·MinIO 포트 미개방** | 아동 민감정보 저장소의 외부 노출면 = 0. 외부에 열린 포트는 nginx 의 80/443 뿐이고 EC2 UFW 도 그 둘만 허용한다 |
| **컨테이너 간 통신은 내부 DNS** | backend 는 `mysql:3306` · `redis:6379` · `minio:9000` 으로만 접근한다(같은 `dodam-net` 브리지). 그래서 앱은 호스트 포트가 없어도 동작한다 |
| **사람의 접속은 SSH 를 거친다** | 접근 경로를 SSH 계정 하나로 좁혀 인증·감사 지점을 단일화. 서버에 들어간 뒤 `docker exec`, 또는 SSH 터널로 GUI 툴 연결 |
| **비밀번호는 컨테이너 env 를 재사용** | 아래 명령들은 비밀번호를 **입력하지도, 호스트에 남기지도 않는다.** 셸 히스토리·`ps` 노출을 원천 차단(백업 스크립트와 동일 원칙) |

접속 정보(계정·비밀번호)의 원본은 서버의 `infra/.env`(git 비추적)와 Jenkins 크리덴셜 `dodam-env` 두 곳뿐이다.
**어떤 값도 문서·이슈·메신저에 옮겨 적지 않는다.**

| 대상 | 컨테이너 | DB/버킷 | 계정(값은 `.env` 참조) |
|------|----------|---------|------------------------|
| MySQL | `dodam-mysql` | `b209` | 앱: `dodam`(`MYSQL_USER`) · 관리: `root`(`MYSQL_ROOT_PASSWORD`) |
| Redis | `dodam-redis` | DB 0 | 비밀번호 `REDIS_PASSWORD` |
| MinIO | `dodam-minio` | 버킷 `dodam` | 관리: `MINIO_ROOT_USER` · 앱: `dodam-be-rw` / `dodam-ai-ro` |

---

## 2. 서버에서 직접 접속 (가장 흔한 경로)

먼저 SSH 로 서버에 들어간다. `docker` 명령은 `kr` 계정에서 sudo 없이 실행된다.

```bash
ssh kr@i15b209.p.ssafy.io
```

### 2-1. MySQL

**앱 계정(`dodam`)으로 — 평상시 조회는 이걸 쓴다.**

```bash
docker exec -it dodam-mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"'
```

**root 로 — 계정·권한·스키마 관리가 필요할 때만.**

```bash
docker exec -it dodam-mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'
```

동작 원리: `docker exec` 로 컨테이너 안에서 셸을 열고, **컨테이너가 이미 갖고 있는 환경변수**를 그대로 쓴다.
`MYSQL_PWD` 는 mysql 클라이언트가 읽는 비밀번호 변수라 `-p` 입력도, 명령줄 인자 노출도 없다.

단발 쿼리는 `-e` 로:

```bash
docker exec dodam-mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" -e "SHOW TABLES;"'
```

### 2-2. Redis

```bash
docker exec -it dodam-redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'
```

`--no-auth-warning` 은 "명령줄 비밀번호 경고"를 끄는 옵션이다. 여기서는 값이 셸 히스토리가 아니라
컨테이너 내부 env 에서 오므로 호스트에 남지 않는다.

```bash
# 키 개수·메모리 확인 (단발)
docker exec dodam-redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO keyspace'
```

⚠️ 운영 Redis 에서 `KEYS *` 는 쓰지 않는다(전 키 스캔 = 블로킹). 필요하면 `SCAN` 을 쓴다.

### 2-3. MinIO

```bash
# 버킷 목록
docker exec dodam-minio sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls l'

# 프리픽스별 객체 확인 (images/ audio/ tts-cache/ reports/ evidences/)
docker exec dodam-minio sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls --summarize l/dodam/images/'
```

⚠️ 객체를 **내려받지 않는다.** 파일 자체가 아동의 그림·음성 원본이다. 목록·용량 확인까지만.

---

## 3. 로컬 GUI 툴에서 접속 (SSH 터널)

DBeaver·MySQL Workbench·IntelliJ Database 등에서 붙고 싶을 때. 호스트에 3306 이 열려 있지 않으므로
**터널의 목적지는 호스트가 아니라 컨테이너 IP** 다. (호스트는 도커 브리지로 컨테이너에 직접 도달한다 — 실측 확인됨)

```bash
# 1) 현재 컨테이너 IP 조회 (컨테이너를 재생성하면 바뀐다 — 매번 확인할 것)
MYSQL_IP=$(ssh kr@i15b209.p.ssafy.io \
  "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dodam-mysql")
echo "$MYSQL_IP"          # 예: 172.18.0.4

# 2) 터널 열기 (로컬 3307 → 컨테이너 3306). 이 창은 켜 둔 채로 사용
ssh -N -L 3307:"$MYSQL_IP":3306 kr@i15b209.p.ssafy.io
```

GUI 툴 접속 설정:

| 항목 | 값 |
|------|-----|
| Host / Port | `127.0.0.1` / `3307` |
| Database | `b209` |
| User | `dodam` (`MYSQL_USER`) |
| Password | `.env` 의 `MYSQL_PASSWORD` |

같은 방식으로 다른 저장소도 열 수 있다(포트만 바꿔서):

```bash
ssh -N -L 6380:<dodam-redis IP>:6379  kr@i15b209.p.ssafy.io   # Redis
ssh -N -L 9001:<dodam-minio IP>:9001  kr@i15b209.p.ssafy.io   # MinIO 웹 콘솔 → http://127.0.0.1:9001
```

호스트 포트로 이미 열려 있어 **IP 조회가 필요 없는** 것들(127.0.0.1 바인딩이라 터널만 뚫으면 된다):

```bash
ssh -N -L 3000:127.0.0.1:3000 kr@i15b209.p.ssafy.io   # Grafana
ssh -N -L 9091:127.0.0.1:9091 kr@i15b209.p.ssafy.io   # Prometheus
```

> Jenkins 는 nginx 를 통해 공개돼 있어 터널이 필요 없다 — <https://i15b209.p.ssafy.io/jenkins/>

---

## 4. ⚠️ 가드레일 (타협 불가)

- **조회 = 민감정보 열람.** 필요한 범위만 본다. 아동 그림·대화·리포트 본문을 화면 밖(캡처·복사·메신저 공유)으로 내보내지 않는다.
- **`ports:` 를 열어 임시 접속하지 않는다.** compose 에 `3306:3306` 같은 줄을 추가하는 것은 금지.
  불가피하면 `127.0.0.1:3306:3306`(로컬 바인딩)만, 그리고 작업 후 즉시 되돌린다.
- **비밀번호를 명령줄에 직접 쓰지 않는다.** 위 명령들처럼 컨테이너 env 를 재사용한다.
  히스토리에 남은 경우 `history -d` 로 지운다.
- **운영 DB 에 직접 DML/DDL 을 치지 않는다.** 스키마 변경은 Flyway 마이그레이션으로만.
  부득이한 수정은 [DB백업-복원.md](DB백업-복원.md) 절차로 **백업을 먼저 뜨고** 진행한다.
- **`.env` · 백업 파일 · 덤프를 서버 밖으로 복사하지 않는다.** git 커밋은 물론 금지.

---

## 5. 트러블슈팅

| 증상 | 원인·조치 |
|------|-----------|
| `ERROR 1045 (28000): Access denied ... (using password: NO)` | `MYSQL_PWD` 가 비어 전달됨. 호스트에서 `.env` 를 읽어 넘기려다 경로가 틀린 경우가 대부분 — 2절의 **컨테이너 env 재사용** 방식을 쓸 것 |
| 터널이 `Connection refused` | 컨테이너 IP 가 바뀌었다(재배포 시 변경). 3절 1)번으로 IP 를 다시 조회 |
| `docker: permission denied` | `kr` 계정이 docker 그룹에 없음. 재로그인하거나 관리자에게 문의 |
| 컨테이너가 `Created`/`Exited` 상태 | 배포가 중간에 실패한 상태. `docker ps -a` 로 확인 후 [배포검증-롤백.md](배포검증-롤백.md) 절차 |
| MongoDB 에 붙고 싶다 | **아직 배포되지 않았다.** 스트로크·대화 로그의 MongoDB 이관은 설계만 확정된 상태 — [../database/저장소-아키텍처.md](../database/저장소-아키텍처.md) 참조 |

---

## 6. 빠른 참조

```bash
# MySQL 셸
docker exec -it dodam-mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"'

# Redis 셸
docker exec -it dodam-redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'

# MinIO 버킷 목록
docker exec dodam-minio sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls l'

# 컨테이너 상태 한눈에
docker ps --format 'table {{.Names}}\t{{.Status}}'
```
