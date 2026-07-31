# DB·저장소 접속 가이드

> 대상: EC2 `i15b209.p.ssafy.io` 의 k3s 네임스페이스 `dodam` —
> `mysql-0`(MySQL 8.4.10) · `redis-0`(Redis 7.4.8) · `minio-0`(MinIO) · `mongodb-0`(MongoDB 8.0.4)
> 관련 문서: 백업·복원은 [DB백업-복원.md](DB백업-복원.md), 저장소 설계는 [../database/저장소-아키텍처.md](../database/저장소-아키텍처.md)
> ⚠️ **이 DB의 내용 = 아동의 그림·대화·감정 기록.** 조회 자체가 민감정보 열람이다. (CLAUDE.md 9절 가드레일)

> **2026-07-30 갱신 (S15P11B209-739):** 360 컷오버로 운영이 k3s 로 옮겨갔다. 이 문서는 그 기준이다.
> ⚠️ **정지된 compose 컨테이너(`dodam-mysql` 등)를 다시 켜지 말 것.** 2026-07-29 23:55 에 멈춘
> 그 컨테이너들은 **컷오버 이전 데이터**를 갖고 있다. 켜면 조회는 되는데 내용이 과거다 —
> 백업 스크립트가 정확히 그 함정에 빠질 뻔했다(S15P11B209-732).

---

## 0. 준비 — `kubectl` 이 되는지부터

```bash
ssh kr@i15b209.p.ssafy.io
kubectl -n dodam get pod          # 이게 되면 아래 명령이 전부 된다
```

안 되고 `Unable to read /etc/rancher/k3s/k3s.yaml` 가 나오면 kubeconfig 를 가리켜 준다.

```bash
export KUBECONFIG=$HOME/.kube/config
```

`kr` 계정의 `~/.zshrc` 에는 이미 들어 있다. **비로그인 셸이나 bash 로 들어오면 빠진다** —
스크립트·cron 에서 쓸 때는 항상 명시할 것.

> `sudo k3s kubectl` 은 쓰지 않는다. `sudo` 가 비밀번호를 물어 비대화형에서 멈춘다.
> `kr` 의 kubeconfig 로 이미 관리자 권한이 나온다.

---

## 1. 전제 — 무엇이 열려 있고 무엇이 닫혀 있는가

> **2026-07-31 변경:** **MySQL 만 외부에 개방했다**(사용자 지시). 나머지 저장소는 종전대로 노출 0 이다.
> 매니페스트는 `infra/k8s/overlays/prod/mysql-nodeport.yaml`, 경위·되돌리는 법은 그 파일 머리주석에 있다.

Redis·MinIO·MongoDB Service 는 여전히 **headless ClusterIP**(`clusterIP: None`) 이고 NodePort 도
hostPort 도 없다. 이 셋에 대한 외부 직접 접속은 **설계상 불가능하며, 뚫지 않는다.**
MySQL 은 headless `mysql`(파드 DNS·앱 접속용) 은 그대로 두고 **`mysql-ext`(NodePort 30306) 이라는
입구를 하나 더** 낸 형태다.

```
$ kubectl -n dodam get svc mysql mysql-ext redis minio mongodb
mysql       ClusterIP   None                    # 앱·파드용 (변경 없음)
mysql-ext   NodePort    <cluster-ip>  3306:30306/TCP   # ← 외부 개방
redis       ClusterIP   None
minio       ClusterIP   None
mongodb     ClusterIP   None
```

| 결정 | 이유 |
|------|------|
| **MySQL 외부 개방** (2026-07-31) | 외부 도구에서 직접 붙기 위해 사용자가 결정. **대가**: 인터넷 전체가 로그인 시도 가능 — 계정·비밀번호가 유일한 방어선이 된다. 아래 §1-a 의 위험을 알고 쓴다 |
| **Redis·MinIO·Mongo 노출 0 유지** | 개방 요청 범위가 MySQL 뿐이다. 노출면은 필요한 만큼만 넓힌다 |
| **파드 간 통신은 클러스터 DNS** | backend 는 `mysql:3306` · `redis:6379` · `minio:9000` · `mongodb:27017` 으로만 접근한다. Service 이름을 compose 서비스명과 똑같이 유지해서 앱 설정을 하나도 바꾸지 않았다 |
| **사람의 접속은 SSH 를 거친다** (MySQL 제외) | 접근 경로를 SSH 계정 하나로 좁혀 인증·감사 지점을 단일화. 서버에 들어간 뒤 `kubectl exec`, 또는 `kubectl port-forward` + SSH 터널로 GUI 툴 연결. **MySQL 은 2026-07-31 부터 이 원칙에서 빠졌다** — SSH 없이 바로 붙는다 |
| **비밀번호는 파드 env 를 재사용** | 아래 명령들은 비밀번호를 **입력하지도, 호스트에 남기지도 않는다.** 셸 히스토리·`ps` 노출을 원천 차단(백업 스크립트와 동일 원칙) |

접속 정보(계정·비밀번호)의 원본은 서버의 `infra/.env`(git 비추적) → Secret `dodam-secrets`, 그리고
Jenkins 크리덴셜 `dodam-env` 뿐이다. **어떤 값도 문서·이슈·메신저에 옮겨 적지 않는다.**

| 대상 | 워크로드 / 파드 | DB/버킷 | 계정(값은 `.env` 참조) |
|------|-----------------|---------|------------------------|
| MySQL | `sts/mysql` · `mysql-0` | `b209` | 앱: `dodam`(`MYSQL_USER`) · 관리: `root`(`MYSQL_ROOT_PASSWORD`) |
| Redis | `sts/redis` · `redis-0` | DB 0 | 비밀번호 `REDIS_PASSWORD` |
| MinIO | `sts/minio` · `minio-0` | 버킷 `dodam` | 관리: `MINIO_ROOT_USER` · 앱: `dodam-be-rw` / `dodam-ai-ro` |
| MongoDB | `sts/mongodb` · `mongodb-0` | `dodam` | 관리: `MONGO_ROOT_USERNAME` · 앱: `MONGO_APP_USERNAME` |

---

## 1-a. 🌐 MySQL 외부 직접 접속 (2026-07-31 개방)

SSH 터널 없이 GUI 툴·CLI 에서 바로 붙는다.

| 항목 | 값 |
|------|-----|
| Host | `i15b209.p.ssafy.io` |
| Port | **30306** (컨테이너 3306 → NodePort 30306) |
| Database | `b209` |
| User / Password | `dodam` / `.env` 의 `MYSQL_PASSWORD` |

### ⚠️ TLS 는 선택이 아니다 (2026-07-31 실측)

```
tls_version               TLSv1.2,TLSv1.3     ← 서버는 TLS 를 할 수 있고
require_secure_transport  OFF                 ← 평문 접속도 그대로 받는다
```

**클라이언트가 TLS 를 켜지 않으면 평문으로 붙는다.** 클러스터 안에서만 오갈 때는 문제가
아니었지만, 이제 비밀번호와 아동 데이터가 인터넷을 건넌다. 그래서 아래 모든 설정에
`sslMode=REQUIRED` 가 들어간다 — **빼먹으면 조용히 평문이 된다.**

```bash
mysql -h i15b209.p.ssafy.io -P 30306 -u dodam -p b209 --ssl-mode=REQUIRED
```

> 서버에서 `require_secure_transport=ON` 으로 막는 편이 근본적이다. **다만 지금 켜면 백엔드가 죽는다** —
> `application-local.yml:15` 의 JDBC URL 이 `useSSL=false` 로 명시돼 있다. 순서는
> ① 백엔드를 `sslMode=REQUIRED` 로 고쳐 배포 → ② 서버 스위치 ON. 포트를 오래 열어 둘 거면 해 둔다.

### GUI 툴 설정 (DBeaver · Workbench · IntelliJ)

접속 정보는 위 표와 같고, **드라이버 속성 두 개**를 반드시 넣는다.

```
sslMode            = REQUIRED
connectionTimeZone = Asia/Seoul
```

| 툴 | 넣는 곳 |
|----|---------|
| DBeaver | 새 연결 → MySQL → **Driver properties** 탭 |
| MySQL Workbench | Standard TCP/IP → **SSL** 탭에서 `Use SSL: Require` |
| IntelliJ Database | URL `jdbc:mysql://i15b209.p.ssafy.io:30306/b209` → **Advanced** 탭 |

#### GUI 함정 셋

1. **`Public Key Retrieval is not allowed` 가 뜨면 `allowPublicKeyRetrieval=true` 로 끄지 말 것.**
   그 에러는 "권한이 모자라다"가 아니라 **TLS 가 꺼졌다**는 신호다. MySQL 8.4 의 기본 인증
   플러그인(`caching_sha2_password`)은 평문 연결일 때 서버 공개키를 따로 받아와야 하는데,
   그 요청이 기본 거부라서 나는 것이다. `sslMode=REQUIRED` 를 제대로 넣으면 애초에 뜨지 않는다.
   백엔드 설정에 `allowPublicKeyRetrieval=true` 가 있는 것은 **파드 간 통신이라 그런 것이고,
   인터넷 경유 설정에 그대로 베끼면 평문 접속이 된다.**
2. **시각을 변환하지 말 것.** DB 값은 이미 KST 다(§1-b). `connectionTimeZone` 을 안 잡으면
   드라이버가 저장값을 UTC 로 착각해 화면에서 **9시간 밀어** 보여 준다.
3. **읽기 전용으로 걸어 둘 것.** 운영 DB 직접 DML/DDL 은 §4 금지 사항이다. DBeaver 는 연결 편집
   창에서 `Connection type: Production` + `Read-only connection` 체크(메뉴 위치는 버전마다 다르다).
   실수로 `UPDATE` 를 커밋하는 사고를 **구조적으로** 막는 편이 조심하는 것보다 낫다.

### GUI 내장 SSH 터널 — 보안그룹이 막혀 있어도 되는 경로

30306 이 밖에서 안 열리면 GUI 의 **SSH 탭**을 쓴다. 22 번만 타므로 보안그룹과 무관하고,
SSH 가 암호화하므로 TLS 설정도 필요 없다.

| 탭 | 항목 | 값 |
|----|------|-----|
| SSH | Host / Port | `i15b209.p.ssafy.io` / `22` |
| SSH | User / 인증 | `kr` / 비밀번호 (`PasswordAuthentication yes`) |
| Main | Host / Port | `127.0.0.1` / `30306` ← **서버 기준 주소다** |

> `mysql-ext` 가 생긴 뒤로 이 경로에 **`kubectl port-forward` 가 필요 없어졌다.** 서버 루프백에서
> 30306 이 바로 잡히기 때문이다. §3 의 port-forward 절차는 Redis·MinIO·Mongo 에만 해당한다.

### 관문이 셋이다 — 안 닿으면 순서대로 짚는다

`timeout` 이 나면 어디서 막혔는지부터 가른다. **세 관문 중 하나만 닫혀도 증상은 똑같다.**

| # | 관문 | 확인 | 여는 법 |
|---|------|------|---------|
| ① | k8s Service | `kubectl -n dodam get svc mysql-ext` | `kubectl apply -k infra/k8s/overlays/prod` |
| ② | EC2 UFW | `sudo ufw status \| grep 30306` | `sudo ufw allow 30306/tcp comment 'mysql 외부개방'` |
| ③ | SSAFY 보안그룹 | 외부 PC 에서 `nc -vz i15b209.p.ssafy.io 30306` | **우리 권한 밖.** 막혀 있으면 SSAFY 에 요청해야 한다 |

①②가 모두 열렸는데도 밖에서 timeout 이면 원인은 ③ 하나뿐이다. 그때는 서버 안에서
`mysql -h 127.0.0.1 -P 30306` 이 되는지로 ①을 실증해 두면 오진을 피한다
(서버에서 **자기 공인 IP** 로 붙는 시험은 INPUT 체인을 타지 않아 ②③의 증거가 되지 않는다).

### ⚠️ 열어 둔 대가 — 알고 쓴다

- **인터넷 전체가 로그인 프롬프트에 닿는다.** 이제 `MYSQL_PASSWORD`·`MYSQL_ROOT_PASSWORD` 가
  아동 데이터의 **유일한** 방어선이다. 비밀번호 유출 = 데이터 유출이 직결된다.
- **`root` 도 원격에서 붙는다.** mysql 공식 이미지는 `root@'%'` 를 만든다(`MYSQL_ROOT_HOST` 기본값 `%`).
  좁히려면 `RENAME USER 'root'@'%' TO 'root'@'localhost';` 를 검토한다 — 단 **백업·복원 스크립트가
  파드 안에서 root 를 쓰므로**(`kubectl exec` 경로) 그 영향부터 확인할 것.
- **무차별 대입은 조용하다.** 실패 로그를 보려면 파드에서
  `SELECT user, host FROM performance_schema.accounts;` · `SHOW GLOBAL STATUS LIKE 'Aborted_connects';`
  를 주기적으로 본다. 급증하면 닫는 것을 먼저 고려한다.
- **닫는 건 30초면 된다** — `mysql-nodeport.yaml` 머리주석의 되돌리기 절차. 쓸 일이 끝나면 닫는다.

---

## 1-b. ⏰ MySQL 의 시각은 **KST** 로 저장된다 (2026-07-30, S15P11B209-736)

조회하기 전에 이것부터 알아야 한다. **`SELECT created_at` 의 값은 그대로 한국 시간이다.**
변환하지 말 것 — 변환하면 9시간 틀린다.

| 계층 | 시간대 | |
|---|---|---|
| **MySQL 저장값** | **KST** | 사람이 보는 값. 그대로 읽는다 |
| MySQL 서버(`@@time_zone`) | UTC(`SYSTEM`) | 서버 기본값은 그대로 두었다 |
| 백엔드 앱 내부 | UTC | 드라이버가 읽을 때 KST→UTC 로 변환한다 |
| 파드 로그 · Prometheus | UTC | 관측 축을 UTC 로 유지 |

**앱은 내부적으로 UTC 로 일관되고 DB 에는 KST 가 저장된다.** 드라이버가 양방향으로 변환하기
때문에 모순이 아니다. 그래서 API 응답이나 로그에서 UTC 를 보는 것은 정상이다.

### 어떻게 그렇게 되는가

```
jdbc:mysql://...?serverTimezone=Asia/Seoul&sessionVariables=time_zone='+09:00'
                 ↑ 값 변환 기준            ↑ 세션 시간대 자체
```

두 설정의 역할이 다르다. 이걸 몰라서 2026-07-30 까지 규약이 둘로 갈려 있었다.

| 설정 | 무엇을 지배하나 |
|---|---|
| `serverTimezone` | **드라이버가 값을 변환**할 때의 기준 → **앱이 쓰는 컬럼**만 KST 가 됐다 |
| `sessionVariables=time_zone` | **MySQL 세션 시간대** → `DEFAULT CURRENT_TIMESTAMP` 가 평가되는 기준 |

`DEFAULT CURRENT_TIMESTAMP` 는 드라이버를 거치지 않고 서버가 채운다. 그래서 `serverTimezone`
이 닿지 않아 서버 기본값(UTC)이 들어갔고, **같은 행 안에서 `started_at` 은 KST, `created_at` 은
UTC** 인 상태가 됐다. V26 마이그레이션이 과거분 50개 컬럼을 +9h 보정했다.

### ⚠️ 새 datetime 컬럼을 만들 때

`DEFAULT CURRENT_TIMESTAMP` 를 쓰든 엔티티가 값을 넣든 **이제 둘 다 KST** 다. 다만 위 JDBC
설정에 의존하는 구조이므로, 그 설정을 손대면 **모든 신규 행의 기준이 조용히 바뀐다.**
`application-local.yml` 의 datasource URL 을 수정할 때는 이 문서를 함께 볼 것.

### 사람이 직접 INSERT 할 때 주의

`mysql` CLI 로 붙으면 세션 시간대가 서버 기본값(**UTC**)이다. 그 상태로
`DEFAULT CURRENT_TIMESTAMP` 에 의존해 INSERT 하면 **UTC 가 들어가 규약이 깨진다.**
운영 DB 에 직접 INSERT 하지 않는 것이 원칙이지만(§4), 부득이하면 먼저:

```sql
SET SESSION time_zone = '+09:00';
```

---

## 2. 서버에서 직접 접속 (가장 흔한 경로)

### ⚠️ `-t`(TTY)를 언제 붙이고 언제 빼는가

| 상황 | 플래그 | 이유 |
|------|--------|------|
| 대화형 셸 (mysql·redis-cli 프롬프트) | `-it` | 사람이 타이핑한다. TTY 가 필요하다 |
| 단발 쿼리·**파이프로 데이터를 받는** 경우 | **붙이지 않는다** | TTY 를 붙이면 개행이 CRLF 로 바뀌어 **gzip·바이너리 스트림이 깨진다**(S15P11B209-732 에서 실제로 겪었다) |
| 컨테이너로 **데이터를 밀어 넣는** 경우 | `-i` 만 | stdin 은 필요하고 TTY 는 해롭다 |

### 2-1. MySQL

**앱 계정(`dodam`)으로 — 평상시 조회는 이걸 쓴다.**

```bash
kubectl -n dodam exec -it sts/mysql -- \
  sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"'
```

**root 로 — 계정·권한·스키마 관리가 필요할 때만.**

```bash
kubectl -n dodam exec -it sts/mysql -- \
  sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'
```

동작 원리: `kubectl exec` 로 파드 안에서 셸을 열고, **파드가 이미 갖고 있는 환경변수**를 그대로 쓴다.
`MYSQL_PWD` 는 mysql 클라이언트가 읽는 비밀번호 변수라 `-p` 입력도, 명령줄 인자 노출도 없다.

단발 쿼리는 `-e` 로 (TTY 없이):

```bash
kubectl -n dodam exec sts/mysql -- \
  sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" -e "SHOW TABLES;"'
```

긴 SQL 은 **stdin 으로** 넘긴다. `kubectl exec` 안에서 따옴표를 중첩하면 조용히 빈 결과가 나온다
(733 복원 드릴에서 "테이블 0개"로 오판한 적이 있다).

```bash
echo "SELECT COUNT(*) FROM drawing_sessions;" | kubectl -n dodam exec -i sts/mysql -- \
  sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql -u"$MYSQL_USER" -N -B "$MYSQL_DATABASE"'
```

> ⚠️ **계정과 비밀번호를 섞지 말 것.** `MYSQL_PWD="$MYSQL_PASSWORD"` 는 앱 계정(`$MYSQL_USER`)용,
> `MYSQL_PWD="$MYSQL_ROOT_PASSWORD"` 는 `-uroot` 용이다. 섞으면 `ERROR 1045 (using password: YES)` 가
> 나는데, 비밀번호가 "전달은 됐다"는 뜻이라 값이 틀린 줄 알고 엉뚱한 곳을 뒤지게 된다.

> ⚠️ **`sts/mysql` 은 워크로드 이름이다.** 파드명(`mysql-0`)을 직접 써도 되지만, 파드가 재생성되면
> 이름이 그대로여도(StatefulSet 이라) 습관적으로 워크로드를 쓰는 편이 안전하다.

### 2-2. Redis

```bash
kubectl -n dodam exec -it sts/redis -- \
  sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'
```

`--no-auth-warning` 은 "명령줄 비밀번호 경고"를 끄는 옵션이다. 여기서는 값이 셸 히스토리가 아니라
파드 내부 env 에서 오므로 호스트에 남지 않는다.

```bash
# 키 개수·메모리 확인 (단발)
kubectl -n dodam exec sts/redis -- \
  sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO keyspace'
```

⚠️ 운영 Redis 에서 `KEYS *` 는 쓰지 않는다(전 키 스캔 = 블로킹). 필요하면 `SCAN` 을 쓴다.

### 2-3. MinIO

```bash
# 버킷 목록
kubectl -n dodam exec sts/minio -- \
  sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls l'

# 프리픽스별 객체 확인 (images/ audio/ tts-cache/ reports/ evidences/)
kubectl -n dodam exec sts/minio -- \
  sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls --summarize l/dodam/images/'
```

⚠️ 객체를 **내려받지 않는다.** 파일 자체가 아동의 그림·음성 원본이다. 목록·용량 확인까지만.

> `mc alias set` 에 URL 대신 **인자를 분리**해 넘기는 것은 의도적이다. 비밀번호에 `@ : /` 가
> 들어가면 URL 형식(`http://user:pass@host`)이 조용히 다른 호스트를 가리킨다.

> MinIO 이미지에는 **`mc` 와 `stat` 밖에 없다.** `tar`·`gzip`·`openssl`·`find` 가 없어서
> `kubectl cp`(tar 의존)도 쓸 수 없다. 백업이 2단 컨테이너 구조인 이유다(733).

### 2-4. MongoDB

### ⚠️ Mongo 만 env 이름이 다르다 — Secret 키 이름을 그대로 쓰면 안 된다

MySQL·Redis·MinIO 는 Secret 키 이름이 파드 env 이름과 같지만, **MongoDB 는 다르다.**
mongo 이미지가 `MONGO_INITDB_*` 라는 이름을 요구하기 때문에 매니페스트에서 이렇게 매핑돼 있다:

| Secret 키 (`dodam-secrets`) | 파드 env 이름 |
|---|---|
| `MONGO_ROOT_USERNAME` | **`MONGO_INITDB_ROOT_USERNAME`** |
| `MONGO_ROOT_PASSWORD` | **`MONGO_INITDB_ROOT_PASSWORD`** |
| `MONGO_DATABASE` | **`MONGO_INITDB_DATABASE`** |
| `MONGO_APP_USERNAME` · `MONGO_APP_PASSWORD` | 이름 그대로 |

Secret 키 이름(`$MONGO_ROOT_USERNAME`)을 파드 안에서 쓰면 **빈 값**이 되고, mongosh 는 인증을
시도하지 않은 채 기본 `test` DB 에 붙는다. `ping` 은 인증 없이도 성공하므로 **접속에 성공한 것처럼
보인다** — 실제로는 `listCollections` 단계에서야 `requires authentication` 이 난다.

**root 로 (관리 작업용):**

```bash
kubectl -n dodam exec -it sts/mongodb -- \
  sh -c 'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
         --authenticationDatabase admin "$MONGO_INITDB_DATABASE"'
```

**앱 계정으로 (평상시 조회 — 최소권한):**

```bash
kubectl -n dodam exec -it sts/mongodb -- \
  sh -c 'mongosh -u "$MONGO_APP_USERNAME" -p "$MONGO_APP_PASSWORD" \
         --authenticationDatabase "$MONGO_INITDB_DATABASE" "$MONGO_INITDB_DATABASE"'
```

⚠️ `--authenticationDatabase` 를 빠뜨리면 "인증 실패"가 아니라 **"사용자 없음"**으로 나와
원인을 헷갈린다. **root 는 `admin` DB, 앱 계정은 `dodam` DB** 에 있다 — 값이 다르다.

> 2026-07-30 기준 컬렉션(`strokes`·`conversation_events`)은 **비어 있다.** 앱의 Mongo 전환이
> 아직 진행 중이다(S15P11B209-365). 백업이 `documents=0` WARN 을 내는 것도 그래서다.

---

## 3. 로컬 GUI 툴에서 접속 (port-forward + SSH 터널)

DBeaver·MySQL Workbench·IntelliJ Database 등에서 붙고 싶을 때.

> **MySQL 은 이 절이 필요 없다**(2026-07-31). `mysql-ext`(NodePort 30306) 가 생겨서 직접 접속이든
> GUI 내장 SSH 터널이든 **§1-a** 로 끝난다. 아래 `port-forward` 절차는 **Redis·MinIO·MongoDB** 용이다.

compose 시절에는 `docker inspect` 로 컨테이너 IP 를 뽑아 그 IP 로 터널을 뚫었다.
**k3s 에서는 그럴 필요가 없다** — `kubectl port-forward` 가 파드를 서버의 루프백에 붙여 준다.
파드 IP 가 바뀌어도 명령이 그대로다.

```bash
# 서버에서: 파드 → 서버 루프백 (이 창은 켜 둔 채로)
ssh kr@i15b209.p.ssafy.io
kubectl -n dodam port-forward sts/mysql 3307:3306
```

```bash
# 로컬에서: 서버 루프백 → 내 PC (별도 창)
ssh -N -L 3307:127.0.0.1:3307 kr@i15b209.p.ssafy.io
```

한 줄로 합칠 수도 있다:

```bash
ssh -N -L 3307:127.0.0.1:3307 kr@i15b209.p.ssafy.io \
  -o "RemoteCommand kubectl -n dodam port-forward sts/mysql 3307:3306" -t
```

GUI 툴 접속 설정 (위 터널 기준):

| 항목 | 값 |
|------|-----|
| Host / Port | `127.0.0.1` / `3307` ← **내 PC 기준** |
| Database | `b209` |
| User | `dodam` (`MYSQL_USER`) |
| Password | `.env` 의 `MYSQL_PASSWORD` |

> MySQL 예시는 **구조를 보여 주려고 남겨 둔다.** 실제로 MySQL 에 붙을 때는 §1-a 가 더 짧다
> (창을 켜 둘 필요도, 파드 재생성 때 터널이 끊길 일도 없다). 이 절의 값어치는
> **Redis·MinIO·Mongo 처럼 외부 입구가 없는 저장소**에 있다.

같은 방식으로 다른 저장소도 (포트만 바꿔서):

```bash
kubectl -n dodam port-forward sts/redis   6380:6379    # Redis
kubectl -n dodam port-forward sts/minio   9001:9001    # MinIO 웹 콘솔
kubectl -n dodam port-forward sts/mongodb 27018:27017  # MongoDB
kubectl -n dodam port-forward deploy/prometheus 9091:9090  # Prometheus UI
```

> ⚠️ `port-forward` 는 기본이 **127.0.0.1 바인딩**이다. `--address 0.0.0.0` 을 붙이지 말 것 —
> 그 순간 저장소가 서버 외부에 열린다.

**터널이 필요 없는 것들** — nginx 를 통해 이미 공개돼 있다:

| 대상 | 주소 | 인증 |
|------|------|------|
| Grafana | <https://i15b209.p.ssafy.io/grafana/> | Grafana 로그인 필요(미인증 API 는 401) |
| Jenkins | <https://i15b209.p.ssafy.io/jenkins/> | Jenkins 로그인 필요 |

> Prometheus 는 **공개 라우트가 없다.** `/prometheus/` 로 접근하면 nginx 의 랜딩 페이지가
> 200 으로 응답하는데, Prometheus 가 아니라 catch-all 이다. UI 가 필요하면 위 port-forward 를 쓴다.

---

## 4. ⚠️ 가드레일 (타협 불가)

- **조회 = 민감정보 열람.** 필요한 범위만 본다. 아동 그림·대화·리포트 본문을 화면 밖(캡처·복사·메신저 공유)으로 내보내지 않는다.
- **MySQL 외의 저장소는 외부에 열지 않는다.** Redis·MinIO·MongoDB 를 `NodePort`/`LoadBalancer` 로
  바꾸거나 `hostPort` 를 추가하거나 `port-forward --address 0.0.0.0` 을 쓰는 것 전부 금지.
  불가피하면 루프백 바인딩만, 그리고 작업 후 즉시 되돌린다.
  MySQL 은 2026-07-31 사용자 결정으로 이 원칙에서 빠졌다(§1-a) — **예외이지 새 기본값이 아니다.**
  다른 저장소를 열자는 근거로 인용하지 않는다.
- **비밀번호를 명령줄에 직접 쓰지 않는다.** 위 명령들처럼 파드 env 를 재사용한다.
  히스토리에 남은 경우 `history -d` 로 지운다.
- **운영 DB 에 직접 DML/DDL 을 치지 않는다.** 스키마 변경은 Flyway 마이그레이션으로만.
  부득이한 수정은 [DB백업-복원.md](DB백업-복원.md) 절차로 **백업을 먼저 뜨고** 진행한다.
- **`.env` · 백업 파일 · 덤프를 서버 밖으로 복사하지 않는다.** git 커밋은 물론 금지.
- **정지된 compose 컨테이너를 되살려 조회하지 않는다.** 내용이 컷오버 이전이다(문서 상단 경고 참조).

---

## 5. 트러블슈팅

| 증상 | 원인·조치 |
|------|-----------|
| `Unable to read /etc/rancher/k3s/k3s.yaml` | kubeconfig 미지정. `export KUBECONFIG=$HOME/.kube/config` (0절) |
| `ERROR 1045 (28000): Access denied ... (using password: NO)` | `MYSQL_PWD` 가 비어 전달됨. 호스트에서 `.env` 를 읽어 넘기려다 경로가 틀린 경우가 대부분 — 2절의 **파드 env 재사용** 방식을 쓸 것 |
| 쿼리 결과가 **조용히 비어서** 나온다 | `kubectl exec` 안에서 따옴표가 중첩돼 SQL 이 깨졌다. **stdin 으로 넘길 것**(2-1 마지막 예시) |
| 파이프로 받은 덤프가 gzip 오류 | `-t` 를 붙였다. 바이너리 스트림에는 TTY 를 붙이지 않는다(2절 표) |
| `port-forward` 가 끊긴다 | 파드가 재생성되면 끊긴다. 파드 상태 확인 후 다시 실행: `kubectl -n dodam get pod` |
| 터널이 `Connection refused` | 서버 쪽 `port-forward` 가 안 떠 있다. 프로세스가 살아 있어도 포트가 열렸다는 뜻은 아니다 — 서버에서 `curl 127.0.0.1:<port>` 로 먼저 확인 |
| 파드가 `CrashLoopBackOff`/`Pending` | `kubectl -n dodam describe pod <이름>` 의 Events 부터 본다. 이후 [배포검증-롤백.md](배포검증-롤백.md) 절차 |
| Mongo 가 `test` DB 에 붙고 `requires authentication` | Secret 키 이름(`$MONGO_ROOT_USERNAME`)을 파드 안에서 썼다 → 빈 값. **`$MONGO_INITDB_ROOT_USERNAME`** 을 쓸 것 (2-4). `ping` 은 인증 없이도 성공하므로 접속된 것처럼 보인다 |
| MongoDB 조회가 "사용자 없음" | `--authenticationDatabase` 누락·불일치. root=`admin`, 앱 계정=`dodam` (2-4) |
| GUI 에서 `Public Key Retrieval is not allowed` | **TLS 가 꺼진 상태**라는 신호다. `allowPublicKeyRetrieval=true` 로 끄지 말고 `sslMode=REQUIRED` 를 넣는다 (§1-a GUI 함정 1) |
| 외부 30306 이 timeout | 관문 3개를 순서대로: `kubectl get svc mysql-ext` → `sudo ufw status` → 보안그룹(우리 권한 밖). 서버 안에서 `127.0.0.1:30306` 이 되면 ①은 정상이다 (§1-a) |
| 시각이 9시간 어긋나 보인다 | **DB 값은 KST 다**(1-b). 변환하지 말 것. 앱 로그·API 는 UTC 이므로 그 둘을 비교할 때만 9시간을 감안한다 |
| 새로 넣은 행만 UTC 로 들어갔다 | `mysql` CLI 세션이 UTC 라서다. `SET SESSION time_zone='+09:00'` 후 재시도 (1-b 마지막) |

---

## 6. 빠른 참조

```bash
export KUBECONFIG=$HOME/.kube/config

# MySQL 셸
kubectl -n dodam exec -it sts/mysql -- sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"'

# Redis 셸
kubectl -n dodam exec -it sts/redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'

# MinIO 버킷 목록
kubectl -n dodam exec sts/minio -- sh -c 'mc alias set l http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc ls l'

# MongoDB 셸  (★ env 이름이 MONGO_INITDB_* 다 — 2-4 참조)
kubectl -n dodam exec -it sts/mongodb -- sh -c 'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "$MONGO_INITDB_DATABASE"'

# 워크로드 상태 한눈에
kubectl -n dodam get pod -o wide
```
