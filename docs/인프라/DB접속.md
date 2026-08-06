# DB·저장소 접속 가이드

> 대상: EC2 `i15b209.p.ssafy.io` 의 k3s 네임스페이스 `dodam` —
> `mysql-0`(MySQL 8.4.10) · `redis-0`(Redis 7.4.8) · `minio-0`(MinIO) · `mongodb-0`(MongoDB 8.0.4)
> 관련 문서: 백업·복원은 [DB백업-복원.md](DB백업-복원.md), 저장소 설계는 [../database/저장소-아키텍처.md](../database/저장소-아키텍처.md)
> ⚠️ **이 DB의 내용 = 아동의 그림·대화·감정 기록.** 조회 자체가 민감정보 열람이다. (CLAUDE.md 9절 가드레일)

> **2026-08-06 갱신 (S15P11B209-970):** 07-31 에 열었던 **MySQL 외부 개방(NodePort 30306)을 회수했다.**
> 이제 네 저장소 모두 외부 노출이 0 이고, 사람의 접속은 전부 SSH 를 거친다. GUI 절차는 §1-a.
> 30306 으로 저장해 둔 연결 설정은 더 이상 동작하지 않는다.

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

> **2026-08-06 (S15P11B209-970):** **네 저장소 모두 외부 노출이 0 이다.** 07-31~08-06 사이에만
> MySQL 이 예외였고(`mysql-ext`, NodePort 30306), 그 예외는 회수했다. 경위는 §1-a 하단.

MySQL·Redis·MinIO·MongoDB Service 는 전부 **headless ClusterIP**(`clusterIP: None`) 이고 NodePort 도
hostPort 도 없다. 이 넷에 대한 외부 직접 접속은 **설계상 불가능하며, 뚫지 않는다.**

```
$ kubectl -n dodam get svc mysql redis minio mongodb
mysql       ClusterIP   None      # 앱·파드용. 외부 입구 없음
redis       ClusterIP   None
minio       ClusterIP   None
mongodb     ClusterIP   None
```

| 결정 | 이유 |
|------|------|
| **네 저장소 모두 노출 0** | 안에 든 것이 아동의 그림·대화·감정 기록이다. 외부에 열린 포트는 gateway 의 80/443 과 SSH 의 22 뿐이다 |
| **파드 간 통신은 클러스터 DNS** | backend 는 `mysql:3306` · `redis:6379` · `minio:9000` · `mongodb:27017` 으로만 접근한다. Service 이름을 compose 서비스명과 똑같이 유지해서 앱 설정을 하나도 바꾸지 않았다 |
| **사람의 접속은 SSH 를 거친다** | 접근 경로를 SSH 계정 하나로 좁혀 인증·감사 지점을 단일화. 서버에 들어간 뒤 `kubectl exec`(§2), 또는 SSH 터널로 GUI 툴 연결(§1-a·§3) |
| **비밀번호는 파드 env 를 재사용** | 아래 명령들은 비밀번호를 **입력하지도, 호스트에 남기지도 않는다.** 셸 히스토리·`ps` 노출을 원천 차단(백업 스크립트와 동일 원칙) |

접속 정보(계정·비밀번호)의 원본은 서버의 `infra/.env`(git 비추적) → Secret `dodam-secrets`, 그리고
Jenkins 크리덴셜 `dodam-env` 뿐이다. **어떤 값도 문서·이슈·메신저에 옮겨 적지 않는다.**

| 대상 | 워크로드 / 파드 | DB/버킷 | 계정(값은 `.env` 참조) |
|------|-----------------|---------|------------------------|
| MySQL | `sts/mysql` · `mysql-0` | `b209` | 앱: `dodam`(`MYSQL_USER`) · 관리: `root`(`MYSQL_ROOT_PASSWORD`) |
| Redis | `sts/redis` · `redis-0` | DB 0 | 비밀번호 `REDIS_PASSWORD` |
| MinIO | `sts/minio` · `minio-0` | 버킷 `dodam` | 관리: `MINIO_ROOT_USER` · 앱: `dodam-be-rw` (ai-ro 는 673 회수) |
| MongoDB | `sts/mongodb` · `mongodb-0` | `dodam` | 관리: `MONGO_ROOT_USERNAME` · 앱: `MONGO_APP_USERNAME` |

---

## 1-a. 🔐 GUI 툴에서 MySQL 붙기 — SSH 터널 (2026-08-06, S15P11B209-970)

DBeaver·IntelliJ·Workbench 같은 GUI 는 **내장 SSH 터널**로 붙는다. DB 트래픽이 SSH(22) 안으로
흐르므로 새 포트를 열 필요가 없고, 서버 밖에서 MySQL 포트가 보이지 않는다.

```
내 PC (GUI) ──SSH:22──▶ 서버 ──▶ 127.0.0.1:3307 ──port-forward──▶ mysql-0:3306
                              └─ 여기부터는 서버 안이다. 밖에서 닿을 수 없다.
```

### 설정값

| 탭 | 항목 | 값 |
|----|------|-----|
| **SSH** | Host / Port | `i15b209.p.ssafy.io` / `22` |
| **SSH** | User / 인증 | 각자 계정(`woo`·`domingo`·`jhp`·`bg`·`kr`·`yj`) / 비밀번호 (`PasswordAuthentication yes`) |
| **Main** | Host / Port | `127.0.0.1` / **`3307`** ← **서버 기준 주소다.** 내 PC 의 3307 이 아니다 |
| **Main** | Database | `b209` |
| **Main** | User / Password | `dodam` / `.env` 의 `MYSQL_PASSWORD` |

**드라이버 속성 두 개**를 함께 넣는다. 넣는 곳은 툴마다 다르다.

```
sslMode            = REQUIRED
connectionTimeZone = Asia/Seoul
```

| 툴 | 넣는 곳 |
|----|---------|
| DBeaver | 새 연결 → MySQL → **Driver properties** 탭 (SSH 는 **SSH** 탭) |
| MySQL Workbench | Connection Method: **Standard TCP/IP over SSH** |
| IntelliJ Database | URL `jdbc:mysql://127.0.0.1:3307/b209` → **SSH/SSL** 탭에서 SSH 켜기 |

### 왜 서버 루프백 3307 에 무언가 떠 있는가

`kubectl port-forward` 를 systemd 가 상시 유지한다 — `infra/k3s/dodam-mysql-tunnel.service`.
GUI 내장 SSH 터널은 "서버에 들어간 뒤 **서버 기준 주소**로 붙는" 구조라, 서버 루프백에 듣고
있는 것이 없으면 성립하지 않는다. 07-31~08-06 에는 NodePort 30306 이 그 역할을 했고,
그것을 회수하면서 같은 편의를 **노출 없이** 되돌려 준 것이 이 유닛이다.

```bash
# 살아 있는지
systemctl status dodam-mysql-tunnel
ss -tlnp | grep 3307        # 반드시 127.0.0.1:3307. 0.0.0.0 이면 사고다
```

⚠️ **유닛의 `--address 127.0.0.1` 을 `0.0.0.0` 으로 바꾸지 말 것.** 그 한 글자가 970 에서 닫은
구멍을 그대로 다시 연다. 게다가 매니페스트에 안 남아서 `kubectl get svc` 로는 보이지도 않는다.

### GUI 함정 셋

1. **`Public Key Retrieval is not allowed` 가 뜨면 `allowPublicKeyRetrieval=true` 로 끄지 말 것.**
   그 에러는 "권한이 모자라다"가 아니라 **TLS 가 꺼졌다**는 신호다. MySQL 8.4 의 기본 인증
   플러그인(`caching_sha2_password`)은 평문 연결이면 서버 공개키를 따로 받아와야 하는데,
   그 요청이 기본 거부라서 나는 것이다. `sslMode=REQUIRED` 를 제대로 넣으면 애초에 뜨지 않는다.
   SSH 터널 안이라 도청 위험은 없지만, **끄는 습관이 남으면 다음에 터널 밖에서도 끈다.**
   백엔드 설정에 `allowPublicKeyRetrieval=true` 가 있는 것은 파드 간 통신이라 그런 것이다.
2. **시각을 변환하지 말 것.** DB 값은 이미 KST 다(§1-b). `connectionTimeZone` 을 안 잡으면
   드라이버가 저장값을 UTC 로 착각해 화면에서 **9시간 밀어** 보여 준다.
3. **읽기 전용으로 걸어 둘 것.** 운영 DB 직접 DML/DDL 은 §4 금지 사항이다. DBeaver 는 연결 편집
   창에서 `Connection type: Production` + `Read-only connection` 체크(메뉴 위치는 버전마다 다르다).
   실수로 `UPDATE` 를 커밋하는 사고를 **구조적으로** 막는 편이 조심하는 것보다 낫다.

### 터미널이 편하면 (GUI 내장 터널을 안 쓰는 경우)

서버에 상시 터널이 있으므로 로컬 포트포워딩 한 줄이면 된다. `port-forward` 를 따로 띄울
필요가 없다 — 그게 3307 이 존재하는 이유다.

```bash
# 이 창은 켜 둔 채로 (13306 은 내 PC 쪽 임의 포트 — 로컬 MySQL 과 안 겹치게)
ssh -N -L 13306:127.0.0.1:3307 <내계정>@i15b209.p.ssafy.io

# 다른 창에서
mysql -h 127.0.0.1 -P 13306 -u dodam -p b209
```

---

### 📌 07-31 의 외부 개방과 그 회수 (기록)

2026-07-31, 외부 도구에서 바로 붙기 위해 `mysql-ext`(NodePort 30306)로 **운영 MySQL 을 인터넷에
직접 열었다.** 2026-08-06 재점검에서 회수했다(970). 같은 요구가 다시 올 때 판단을 되풀이하지
않도록 근거를 남긴다.

**노출은 가정이 아니라 사실이었다** (2026-08-06 실측). k8s Service 가 살아 있었고, UFW 에도
규칙이 그대로 있었다.

```
$ sudo ufw status | grep 30306
30306/tcp        ALLOW   Anywhere        # mysql 외부개방 2026-07-31
30306/tcp (v6)   ALLOW   Anywhere (v6)   # mysql 외부개방 2026-07-31
```

즉 우리 쪽 관문은 둘 다 열려 있었고, **마지막에 남은 것은 SSAFY 보안그룹 하나뿐**이었다.
우리가 통제하지 못하는 것이 유일한 방어선인 상태로 6일을 보냈다.

**🔴 그리고 UFW 는 애초에 NodePort 를 막지 못한다.** 이 문서는 예전에 관문을
`① k8s Service → ② UFW → ③ 보안그룹` 셋으로 적어 두었는데, **②는 관문이 아니었다.**
위 규칙을 지우는 것으로 닫혔다고 판단하면 안 된다는 뜻이다 — 실제로 닫은 것은 ①이다.

```
패킷 도착 (dst = 노드IP:30306)
  → nat PREROUTING → KUBE-NODEPORTS → DNAT (dst 를 파드 IP:3306 으로 변경)
  → 목적지가 파드 IP라 로컬이 아님 → INPUT 이 아니라 FORWARD 로 감
  → kube-proxy 가 FORWARD 맨 앞에 -I 로 넣은 KUBE-FORWARD 가 먼저 ACCEPT
  → ufw-before-forward 는 평가되지 않음
```

UFW 규칙은 filter 테이블 **INPUT** 체인에 있다. DNAT 때문에 이 트래픽은 INPUT 에 도달하지
않는다. Docker 의 `-p` 퍼블리시가 UFW 를 우회하는 것과 같은 구조다.

**이것이 왜 중요한가** — 이번엔 UFW 에 `ALLOW Anywhere` 가 있었으니 결과적으로 차이가 없었다.
문제는 반대 방향이다. 앞으로 누군가 "UFW 로 소스 IP 를 제한했으니 안전하다"고 판단하면
**그 믿음이 틀린다.** NodePort 로 들어오는 트래픽은 그 규칙을 지나쳐 간다.
그래서 §1-a 의 결론이 "화이트리스트를 잘 걸자"가 아니라 "입구 자체를 없애자"인 것이다.

**소스 IP 화이트리스트로 좁히는 것도 불가능했다.**

| 계층 | 가능? | 이유 |
|------|-------|------|
| UFW `allow from <IP>` | ❌ | 위 구조로 우회 |
| iptables `raw` PREROUTING | ✅ | `nat` 보다 먼저 평가된다. 단 재부팅·k3s 재시작 영속화가 필요 |
| NetworkPolicy | △ | `externalTrafficPolicy: Cluster` 라 소스 IP 가 노드 IP 로 SNAT 된다. `Local` 로 바꿔야 원본이 보인다 |
| MySQL 계정 `host` 제한 | ❌ | 같은 SNAT 이유로 DB 에는 전부 노드 IP 로 보인다 |
| NodePort 자체 | ❌ | 특정 IP 바인딩 불가. `loadBalancerSourceRanges` 도 NodePort 엔 적용되지 않는다 |

팀원 접속 IP 가 대부분 유동 IP 라, 화이트리스트를 유지하는 손이 SSH 터널 설정보다 컸다.
**SSH 계정 보유자만 접근**이 가장 강한 화이트리스트이고 노출면이 0 이 된다 — 그래서 회수했다.

> 다시 열자는 요구가 오면: 이 표를 먼저 보고, "어느 계층에서 누구를 막을 것인가"에 답이
> 나온 뒤에 연다. NodePort 를 그냥 되살리는 것은 **인터넷 전체에 로그인 프롬프트를 여는 것**과
> 같고, 그때 계정 비밀번호가 아동 데이터의 유일한 방어선이 된다.
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

### 2-5. 백엔드를 로컬에서 띄울 때 필요한 환경변수 (S15P11B209-752)

`MONGO_APP_PASSWORD` 는 **기본값이 없다.** 없이 실행하면 앱이 뜨지 않는다.

```
Could not resolve placeholder 'MONGO_APP_PASSWORD' in value "${MONGO_APP_PASSWORD}"
```

이건 버그가 아니라 의도다. 예전에는 빈 기본값(`${MONGO_APP_PASSWORD:}`)이 있었는데, 그러면
Boot 가 빈 문자열을 `char[]` 로 바인딩하다 **NullPointerException** 을 던졌다. 죽는 건 같은데
메시지가 무엇이 없는지 알려주지 않아서, 2026-07-30 배포 실패(365) 때 원인을 찾는 데 시간을 썼다.
지금은 **없는 변수 이름이 그대로 찍힌다.**

로컬 실행:

```bash
cd backend
MONGO_APP_PASSWORD='<로컬 mongo 앱 계정 비밀번호>' ./gradlew bootRun
```

운영·스테이징은 `dodam-secrets` 에서 주입되므로 손댈 것이 없다.

> **다른 시크릿은 왜 안 바꿨나** — `REDIS_PASSWORD`·`DB_PASSWORD`·`JWT_SECRET` 등에도 빈
> 기본값이 남아 있지만 일괄 변경 대상이 아니다. 그것들은 `String` 으로 바인딩돼 빈 값이 들어가도
> NPE 가 나지 않고, 실패하더라도 인증 오류처럼 **읽을 수 있는 메시지**로 죽는다.
> 바꿔야 하는 건 "빈 값으로 조용히 뜨거나, 원인을 가린 채 죽는" 것들뿐이다.

---

## 3. 로컬 GUI 툴에서 접속 (port-forward + SSH 터널)

Redis·MinIO·MongoDB 처럼 **외부 입구가 없는 저장소**를 GUI·CLI 로 볼 때 쓴다.

> **MySQL 은 이 절이 필요 없다**(2026-08-06, S15P11B209-970). 서버 루프백 3307 에 상시 터널이
> 이미 떠 있어서 **§1-a** 로 끝난다.
> ⚠️ 그리고 여기서 `sts/mysql 3307:3306` 을 다시 띄우려 하면 `address already in use` 로 실패한다 —
> 그 포트는 `dodam-mysql-tunnel` 유닛이 잡고 있다. 다른 포트를 쓰거나, 그냥 §1-a 를 쓸 것.

compose 시절에는 `docker inspect` 로 컨테이너 IP 를 뽑아 그 IP 로 터널을 뚫었다.
**k3s 에서는 그럴 필요가 없다** — `kubectl port-forward` 가 파드를 서버의 루프백에 붙여 준다.
파드 IP 가 바뀌어도 명령이 그대로다.

```bash
# 서버에서: 파드 → 서버 루프백 (이 창은 켜 둔 채로)
ssh kr@i15b209.p.ssafy.io
kubectl -n dodam port-forward sts/redis 6380:6379
```

```bash
# 로컬에서: 서버 루프백 → 내 PC (별도 창)
ssh -N -L 6380:127.0.0.1:6380 kr@i15b209.p.ssafy.io
```

한 줄로 합칠 수도 있다:

```bash
ssh -N -L 6380:127.0.0.1:6380 kr@i15b209.p.ssafy.io \
  -o "RemoteCommand kubectl -n dodam port-forward sts/redis 6380:6379" -t
```

접속 (위 터널 기준 — 주소는 **내 PC** 의 127.0.0.1 이다):

```bash
redis-cli -h 127.0.0.1 -p 6380 -a "<REDIS_PASSWORD>" --no-auth-warning
```

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
- **네 저장소 어느 것도 외부에 열지 않는다.** MySQL·Redis·MinIO·MongoDB 를 `NodePort`/`LoadBalancer`
  로 바꾸거나 `hostPort` 를 추가하거나 `port-forward --address 0.0.0.0` 을 쓰는 것 전부 금지.
  불가피하면 루프백 바인딩만, 그리고 작업 후 즉시 되돌린다.
  MySQL 은 2026-07-31~08-06 사이 예외였으나 **회수했다**(S15P11B209-970). 그 기간을
  "전례가 있다"는 근거로 인용하지 않는다 — 왜 되돌렸는지가 §1-a 하단에 있다.
  ⚠️ 특히 `dodam-mysql-tunnel.service` 의 `--address 127.0.0.1` 은 **바꾸면 안 되는 값**이다.
  거기서 새는 노출은 `kubectl get svc` 에 안 보여서 더 오래 살아남는다.
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
| 외부에서 `i15b209.p.ssafy.io:30306` 이 timeout | **정상이다.** 2026-08-06 에 닫았다(970). GUI 는 §1-a 의 SSH 터널로 붙는다 |
| GUI SSH 터널이 `Connection refused` (3307) | 서버의 상시 터널이 죽었다. `systemctl status dodam-mysql-tunnel` → `sudo systemctl restart dodam-mysql-tunnel`. 유닛 자체가 없으면 `infra/k3s/dodam-mysql-tunnel.service` 배치부터 (§1-a) |
| GUI 가 `Unknown database 'b209'` 또는 빈 목록 | Main 탭 Host 를 **내 PC 기준**으로 적었다. GUI 내장 SSH 터널의 Host 는 **서버 기준** `127.0.0.1:3307` 이다 (§1-a) |
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
