# MySQL `--default-time-zone` 반영 계획 (S15P11B209-904 잔여분)

> 관련 이슈: S15P11B209-904(시각 KST 통일) · 736(JDBC 세션 시간대) · 751(드리프트 감시 게이트)
> 관련 문서: `docs/인프라/드리프트경보-대응.md` · `docs/인프라/DB백업-복원.md` · `infra/k8s/README.md`
> 대상 파일: `infra/k8s/base/mysql.yaml:71`
> 작성 2026-08-05 · **아직 실행하지 않았다. 이 문서는 계획이다.**

---

## 1. 지금 어떤 상태인가

904 는 다섯 군데를 KST 로 맞췄다. 네 군데는 반영이 끝났고, **MySQL 한 줄만 남았다.**

| 대상 | 매니페스트 | 클러스터 | 상태 |
|------|-----------|---------|------|
| `configmap-app.yaml` `TZ: Asia/Seoul` | ✅ | ✅ `dodam-config.TZ=Asia/Seoul` | 반영됨 |
| backend | ✅ (envFrom) | ✅ 파드 안 `date` → `KST` | 반영됨 |
| ai | ✅ (envFrom) | ✅ | 반영됨 |
| web · gateway | ✅ (직접 env) | ✅ `TZ=Asia/Seoul` | 반영됨 |
| **mysql `--default-time-zone=+09:00`** | ✅ | ❌ **args 에 없음** | **미반영 — 이 문서의 대상** |

실측 (2026-08-05 13:54 KST):

```
kubectl get sts mysql -n dodam -o jsonpath='{.spec.template.spec.containers[0].args}'
  → ["--character-set-server=utf8mb4","--collation-server=utf8mb4_unicode_ci"]
     ...  --default-time-zone 이 없다

mysql-0 안에서:
  @@global.time_zone   = +09:00
  @@session.time_zone  = +09:00
  NOW()                = 2026-08-05 13:54:39   ← KST 로 맞다
  version              = 8.4.10
  Uptime               = 612,436초 (7.09일 — 컷오버 이후 한 번도 재시작 안 함)
```

### ★ 급하지 않지만 "안전"하지도 않다 — 지금 상태는 휘발성이다

기능상 급하지 않은 이유는 명확하다. `@@global.time_zone` 이 이미 `+09:00` 이라
`mysql` CLI·백업 스크립트·수동 조회가 전부 KST 로 읽힌다. 904 가 잡으려던 증상은 사라졌다.

**그런데 그 값은 런타임에 `SET GLOBAL time_zone='+09:00'` 로 넣은 것이다. 디스크에 없다.**

```
지금:  mysqld 기동 인자에 시간대 없음 + 메모리의 global time_zone = +09:00
   ↓ 어떤 이유로든 mysql-0 이 재시작하면 (노드 재부팅 · OOMKill · 축출 · 이미지 변경)
그때:  기동 인자에 시간대 없음 → global time_zone = SYSTEM(UTC) 로 복귀
   ↓
   ★ 아무 에러도 안 난다. 로그도 안 남는다. 경보도 안 뜬다.
     다음에 누가 mysql CLI 로 시각을 보고 "9시간 어긋나 보인다"에서 다시 시작한다.
```

904 커밋이 이 줄을 "다음 재시작 이후에도 값이 유지되게 하는 몫"이라고 적어둔 것이
바로 이 뜻이다. **매니페스트를 반영하는 순간부터는 재시작이 위험이 아니라 무해해진다.**
반영 전까지는 그 반대다 — 예정에 없던 재시작 한 번이 조용히 UTC 로 되돌린다.

### ⚠️ 그 "예정에 없던 재시작"이 가정이 아니다 — mysql-0 은 메모리 한계에 붙어 있다

```
kubectl top pods -n dodam
  mysql-0    14m CPU    868Mi        ← limits.memory = 1Gi  →  약 85%
```

`limits: {memory: 1Gi}` 에 대해 **868Mi(85%)** 를 쓰고 있다. 7일 무재시작으로 값이
안정된 상태라 당장 터질 조짐은 아니지만, 남은 여유는 156Mi 다.
발표 주간에 부하가 오르면 **OOMKill → 자동 재시작 → global time_zone 이 조용히 UTC 복귀**
라는 경로가 실제로 열려 있다. 관련: `docs/인프라/메모리-OOM-대응.md`.

즉 "재시작이 일어날 수도 있다"가 아니라 **"일어날 만한 이유가 이미 있다"** 이다.
이것이 이 작업을 발표 전에 끝내야 하는 실질적 근거다.

그래서 결론은: **08/10 발표 전 조용한 시점에 반드시 한 번은 하고 넘어간다.**
발표 당일까지 미루지 않는다. 미룰수록 "발표 중 노드 이벤트로 조용히 UTC 복귀" 확률만 남는다.

---

## 2. 왜 자동으로 안 되는가 (배경)

Jenkins 배포 단계는 `kubectl set image` 만 한다 — **이미지 태그만** 바꾼다.
배포용 서비스 계정에 생성·수정 권한이 없는 것은 권한 최소화 설계다(`infra/k8s/README.md` ④).
그래서 args·env·리소스 같은 **설정 변경은 사람이 손으로 반영**해야 하고,
그 "손으로 해야 함"을 잊지 않게 하는 장치가 `manifest-drift-check` 게이트다.

### 🚫 `kubectl apply -k infra/k8s/overlays/prod` 를 통째로 돌리지 말 것

두 가지가 동시에 망가진다.

1. **이미지 태그가 `:prod` 로 되돌아간다** — Jenkins 가 `set image` 로 박아둔 빌드 다이제스트가
   사라지고, 방금 배포한 코드가 롤백된다(`Jenkinsfile` 297행).
2. **MySQL 도 같이 재시작된다** — 아래 절차보다 훨씬 넓은 범위가 동시에 흔들려,
   문제가 나도 어느 변경 탓인지 분리할 수 없다.

이 작업은 **StatefulSet 하나의 args 필드 하나**만 건드린다.

---

## 3. 예상 중단 시간

**결론: 정상 진행 시 20~40초. 최악 90초. 자동 복구된다.**

근거를 하나씩 쌓아둔다 — "대충 1분"이 아니라 어디서 몇 초가 나오는지가 판단 재료다.

| 구간 | 예상 | 근거 |
|------|------|------|
| InnoDB 종료 | 1~3초 | `b209` DB 가 **13.9 MB**(data+index, 82 테이블). `innodb_fast_shutdown=1`, buffer pool 128 MB. 플러시할 더티 페이지가 거의 없다. `terminationGracePeriodSeconds: 60` 은 상한일 뿐 다 쓰지 않는다 |
| 파드 삭제→재생성 | 2~5초 | 단일 노드, `mysql:8.4.10` 이미지가 이미 노드에 있음(`imagePullPolicy` 기본 = IfNotPresent → **풀 없음**) |
| mysqld 기동 | 5~10초 | 기존 datadir 재기동. 최초 init(계정·DB 생성)이 아니라 크래시 복구 수준도 아님 |
| `startupProbe` 통과 | +0~5초 | `periodSeconds: 5` — 준비돼도 최대 5초 늦게 감지 |
| **JVM DNS 캐시** | **+0~30초** | ⚠️ 이게 가장 놓치기 쉬운 구간이다. 새 파드는 **새 IP** 를 받는데, JVM 기본 `networkaddress.cache.ttl` 은 30초다. backend 가 최대 30초간 사라진 옛 IP 로 계속 붙으려 한다 |

### 그동안 사용자에게 무엇이 보이는가

**파드는 죽지 않는다. 재배포도 없다.** 확인해 둔 근거:

- backend readinessProbe = `/actuator/health/readiness`. `application.yml:34-36` 은
  `management.endpoint.health.probes.enabled: true` 만 켰고 **readiness 그룹에 `db` 를 넣지 않았다.**
  Spring Boot 기본 readiness 그룹은 `readinessState` 뿐 — DB 가 죽어도 **Ready 를 유지한다.**
- 따라서 Endpoints 에서 빠지지 않고, gateway(nginx)가 502 를 내지 않는다.
- 대신 **DB 를 건드리는 요청이 500 으로 실패**한다. HikariCP 설정이 따로 없어
  `connectionTimeout` 기본 30초 — 최악의 요청은 30초 매달렸다가 실패한다.
  동시 요청이 많으면 Tomcat 워커가 잠깐 물릴 수 있다(자동 해소).
- `PodDisruptionBudget backend(minAvailable=1)` 는 이 작업과 무관하다 — backend 를 안 건드린다.

> **정리:** "서비스가 내려간다"가 아니라 "30초쯤 DB 쓰는 화면이 에러 난다"이다.
> 그래도 **아이가 그리는 중이면 스트로크 배치가 실패**한다(앱이 재시도 큐로 버티지만
> 굳이 겹칠 이유가 없다). 아래 4-①의 "사용 중 아님" 확인을 건너뛰지 말 것.

---

## 4. 절차

### ① 창(window) 고르기 — 실행 전 확인

```bash
# (a) 지금 그리는 아이가 있는가 — 최근 10분 스트로크 배치 유입 확인
kubectl exec -n dodam mongodb-0 -c mongodb -- bash -c \
  'mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
   --authenticationDatabase admin "$MONGO_INITDB_DATABASE" \
   --eval "print(db.strokes.countDocuments({createdAt:{\$gt:new Date(Date.now()-600000)}}))"'
#   → 0 이어야 진행. 0 이 아니면 활동 중이다. 기다린다.

# (b) 백업 CronJob 이 지금 돌고 있지 않은가 (db-backup 04:00 KST · mongo-backup 04:30 KST)
kubectl get jobs -n dodam | grep -E 'backup' | grep -v Complete
#   → 아무것도 안 나와야 진행
```

**권장 시각: 평일 오전(예: 10~11시 KST).** 새벽을 고르지 않는 이유는 두 가지다 —
백업 잡(04:00/04:30)과 겹치고, **문제가 생겼을 때 사람이 깨어 있어야** 하기 때문이다.
1분짜리 작업에 대기 인원이 없는 시간대를 고를 이유가 없다.

### ② 백업 상태 확인 + 직전 스냅샷 확보

정기 백업은 매일 **04:00 KST**(`db-backup`)에 `/var/backups/dodam` 로 나간다.
최근분 실측: `b209-2026-08-05-0400.sql.gz.enc` (1,373,344 bytes, 결과 `OK`).

```bash
# (a) 최근 백업이 실제로 있고 크기가 정상인가  ※ hostPath 라 sudo 필요
sudo ls -la --time-style=full-iso /var/backups/dodam | tail -10
#   → 오늘 날짜 b209-YYYY-MM-DD-0400.sql.gz.enc 가 있고 bytes 가 0 이 아닐 것

# (b) 최근 백업 잡이 성공으로 끝났는가
kubectl -n dodam logs job/$(kubectl -n dodam get jobs -o name | grep db-backup | tail -1 | sed 's|job.batch/||') | tail -3
#   → '[db-backup] OK file=... bytes=...' 이면 정상. WARN/ERROR 면 여기서 멈춘다.

# (c) ★ 작업 직전 스냅샷을 새로 뜬다 — 정기 백업은 최대 24시간 낡았다
kubectl -n dodam create job --from=cronjob/db-backup db-backup-pre904-$(date +%Y%m%d%H%M)
kubectl -n dodam wait --for=condition=complete job/db-backup-pre904-<위에서찍힌이름> --timeout=300s
kubectl -n dodam logs job/db-backup-pre904-<이름> | tail -3     # OK 확인
```

> ⚠️ (c) 의 `OK` 를 눈으로 확인하기 전에는 ③으로 넘어가지 않는다.
> 이 작업 자체는 데이터를 건드리지 않지만, **재시작은 언제나 "안 뜨는" 가능성을 포함**한다.
> 복원 절차는 `docs/인프라/DB백업-복원.md` 에 있다.

### ③ 사전 검증 — 이 옵션으로 mysqld 가 뜨는가 (운영 밖에서)

기동 인자가 틀리면 **mysqld 가 아예 안 뜨고 CrashLoopBackOff** 가 된다. 그게 이 작업의
유일한 진짜 위험이다. 운영 파드를 건드리기 전에 일회용 파드에서 확인한다.

```bash
kubectl run mysql-cfgcheck --rm -it --restart=Never \
  --image=mysql:8.4.10 --namespace=default -- \
  mysqld --validate-config \
         --character-set-server=utf8mb4 \
         --collation-server=utf8mb4_unicode_ci \
         --default-time-zone=+09:00
#   → 출력 없이 종료코드 0 이면 통과.
```

이름(`Asia/Seoul`)이 아니라 **오프셋(`+09:00`)** 인 이유: 이름을 쓰려면 mysql 시간대
테이블(`mysql_tzinfo_to_sql`)이 적재돼 있어야 하는데 이 이미지엔 없다. 없는 이름을 주면
**서버가 기동하지 못한다.** 한국은 서머타임이 없어 고정 오프셋으로 충분하다.
(이 근거는 `infra/k8s/base/mysql.yaml:60-65` 주석과 동일하다.)

### ④ 반영 — args 필드 하나만 교체

```bash
kubectl -n dodam patch statefulset mysql --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/args","value":[
    "--character-set-server=utf8mb4",
    "--collation-server=utf8mb4_unicode_ci",
    "--default-time-zone=+09:00"
  ]}
]'
```

- `--type=json` 의 `replace` 로 **배열 전체를 명시**한다. `add` 로 원소를 붙이면
  재실행 시 중복이 쌓이고, strategic merge 는 리스트 병합 규칙이 모호하다.
- 이 patch 는 StatefulSet 템플릿을 바꾸므로 **mysql-0 이 자동으로 교체된다.**
  `updateStrategy: RollingUpdate`, `replicas: 1` → 파드 삭제 후 재생성. 여기서 ③의 중단이 시작된다.
- 매니페스트에 없는 필드는 하나도 건드리지 않는다 → 새 드리프트를 만들지 않는다.

### ⑤ 관찰 (patch 직후 바로)

```bash
kubectl -n dodam get pod mysql-0 -w
#   Terminating → Pending → ContainerCreating → Running(0/1) → Running(1/1)
#   1/1 까지 40초를 넘기면 ⑦(롤백 판단)로 간다.
```

### ⑥ 검증

```bash
# (a) 매니페스트대로 떴는가
kubectl -n dodam get pod mysql-0 -o jsonpath='{.spec.containers[0].args}{"\n"}'
#   → [...,"--default-time-zone=+09:00"]

# (b) ★ 기동값으로 KST 인가 (SET GLOBAL 없이)
kubectl exec -n dodam mysql-0 -c mysql -- bash -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@global.time_zone, NOW();"'
#   → +09:00  /  현재 KST 시각
#   ※ 이번엔 아무도 SET GLOBAL 을 하지 않았다. 이 값이 곧 "재시작해도 유지된다"의 증거다.

# (c) 앱이 복구됐는가
kubectl -n dodam get pods -l app=backend        # 2/2 Running, RESTARTS 증가 없어야 정상
kubectl -n dodam logs -l app=backend --tail=50 | grep -i "hikari\|communications link\|SQLException"
#   → 재시작 직후 몇 줄 나오다 멈추면 정상(재연결됨). 계속 쌓이면 ⑦.

curl -s -o /dev/null -w '%{http_code}\n' https://i15b209.p.ssafy.io/api/v1/health || true

# (d) 드리프트가 해소됐는가 — 다음 정시(:20)를 기다리지 말고 수동 실행
kubectl -n dodam create job --from=cronjob/manifest-drift-check drift-verify-$(date +%H%M)
kubectl -n dodam logs job/drift-verify-<이름>
#   → '✅ 클러스터가 매니페스트와 일치한다' (합계: 누락 0 · 불일치 0)
#   이 잡은 CronJob 이 소유하므로, 성공하면 ManifestDriftDetected 경보가 스스로 해제된다.
```

### ⑦ 롤백

**판단 기준: ⑤에서 60초 안에 `1/1` 이 안 되거나, `CrashLoopBackOff` 가 뜨면 즉시.**
원인을 파고들지 말고 먼저 되돌린다. 재시작 자체는 데이터를 안 건드리므로 되돌리면 원상태다.

```bash
# 1) 로그로 원인만 한 줄 확보하고 (사후 분석용)
kubectl -n dodam logs mysql-0 --tail=50
kubectl -n dodam logs mysql-0 --previous --tail=50

# 2) args 를 되돌린다 — 또 한 번 재시작이 발생한다(같은 20~40초)
kubectl -n dodam patch statefulset mysql --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/args","value":[
    "--character-set-server=utf8mb4",
    "--collation-server=utf8mb4_unicode_ci"
  ]}
]'

# 3) 뜬 뒤 런타임으로 KST 를 다시 넣어 원상 복귀 (지금과 같은 휘발성 상태로 돌아간다)
kubectl exec -n dodam mysql-0 -c mysql -- bash -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL time_zone='"'"'+09:00'"'"';"'
kubectl exec -n dodam mysql-0 -c mysql -- bash -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@global.time_zone;"'   # +09:00
```

> **3) 을 빼먹지 말 것.** 롤백만 하고 끝내면 global time_zone 이 UTC 로 남아
> **904 이전보다 나쁜 상태**(문서에는 고쳤다고 적혀 있는데 실제는 UTC)가 된다.

**데이터가 깨진 경우에만** `docs/인프라/DB백업-복원.md` 의 복원 절차 + ②(c) 스냅샷을 쓴다.
이 작업 범위에서는 일어날 이유가 없다(스키마·데이터 무변경).

---

## 5. 그때까지 드리프트 경보를 어떻게 다룰 것인가

### 현황 (실측)

```
alert   : ManifestDriftDetected (severity=warning, category=drift)
state   : firing
activeAt: 2026-08-04T22:20:43Z = 2026-08-05 07:20 KST  ← 지금까지 6시간 넘게 firing
```

Alertmanager 라우팅(`alertmanager-config`)상 이 경보는 `severity=critical` 도
`category=backup` 도 아니라 **기본 경로**를 탄다 → `repeat_interval: 12h`.

**즉 하루 2건.** 08/10 발표까지 그대로 두면 대략 **10건**이 Mattermost 에 쌓인다.

### 판단: 견딜 만하지만, 그대로 두면 안 된다

10건 자체는 못 견딜 양이 아니다. 문제는 **"이 채널의 🔴 는 봐도 되는 것"이라는 학습**이 생기는 것이다.
그 학습이 생기고 나면, 발표 주간에 진짜 드리프트(예: 배포 후 ConfigMap 미반영)가 떠도
같은 모양이라 넘어간다. 이 게이트는 2026-07-30 에 정확히 그 사고(365 미반영)를 놓쳐서 생겼다.

### 선택지 4개와 판단

| # | 방법 | 판정 | 이유 |
|---|------|------|------|
| A | 그냥 둔다 | ⚠️ 차선 | 탐지력은 100% 유지. 대신 위의 "🔴 는 무시해도 된다" 학습이 5일간 쌓인다 |
| B | CronJob 을 `suspend` 한다 | **🚫 금지** | 탐지기를 통째로 끈다. 게다가 `ManifestDriftCheckNotRunning` 룰이 `suspend=0` 조건이라 **그것도 같이 침묵**한다 → 발표 주간을 **완전 무감시**로 보내게 된다. 최악의 선택 |
| C | 매니페스트에서 그 줄을 임시로 뺀다 | **🚫 금지** | 경보는 꺼지지만 git 이 거짓말을 하게 된다. 904 는 "고쳤다"고 커밋돼 있는데 코드에는 없는 상태 — 나중에 아무도 못 찾는다 |
| D | **Alertmanager silence(만료 시각 지정)** | **✅ 채택** | 이 경보만 정확히 끄고, 다른 드리프트는 그대로 뜬다. **만료가 있어 잊을 수 없다** |
| E | STS `partition: 1` 로 재시작 없이 spec 만 반영 | **🚫 금지** | 아래 참조 |

### 🚫 E 안(`partition` 트릭)을 쓰지 않는 이유 — 검토했고 기각했다

"`updateStrategy.rollingUpdate.partition: 1` 을 먼저 넣으면 replicas=1(ordinal 0)이라
파드가 갱신되지 않는다 → args 만 patch 해서 **재시작 없이 드리프트를 해소**할 수 있다"
는 방법이 실제로 성립한다. 하지만 결과가 나쁘다.

- 드리프트 스크립트는 **StatefulSet spec** 을 본다. spec 만 고치면 화면은 초록이 된다.
  그런데 돌고 있는 파드는 여전히 옛 리비전이다 → **경보가 "반영됐다"고 거짓말한다.**
- 더 나쁜 건 그 상태에서 파드가 죽으면, partition 아래 ordinal 은 `currentRevision`(옛것)으로
  재생성된다. **경보는 초록인데 MySQL 은 UTC 로 부활**한다. 게이트가 있는 이유를 정면으로 배신한다.
- `partition` 필드 자체도 매니페스트에 없으므로 **새 드리프트**가 될 소지가 있다.

한 계층(경보 색)만 보고 판단하지 않는다는 원칙이 이 안을 기각한다.

### D 안 실행 방법 (경보를 잠재우는 쪽)

```bash
AM=$(kubectl -n dodam get pods -l app=alertmanager -o name | head -1 | sed 's|pod/||')

# 만료 시각을 반드시 넣는다. 08/10 발표 전에 스스로 풀리도록 08/09 24:00 KST 로 둔다.
kubectl -n dodam exec $AM -- amtool silence add \
  --alertmanager.url=http://localhost:9093 \
  'alertname=ManifestDriftDetected' \
  --duration=<남은시간, 예: 100h> \
  --author="이강륜" \
  --comment="S15P11B209-904 잔여: mysql --default-time-zone. 계획서 docs/인프라/904-MySQL-기본시간대-반영계획.md. 반영 후 즉시 expire."

# 확인
kubectl -n dodam exec $AM -- amtool silence query --alertmanager.url=http://localhost:9093
```

**규칙 3가지:**

1. **`--duration` 을 반드시 준다.** 무기한 silence 는 B 안(끄기)과 같아진다.
   만료를 **08/09 안**으로 두는 것이 핵심이다 — 발표 당일(08/10)에는 게이트가
   다시 눈을 뜨고 있어야 한다.
2. **matcher 를 `alertname` 하나로 좁힌다.** `category="drift"` 로 묶으면
   `ManifestDriftCheckNotRunning`(= 점검이 아예 안 돎)까지 같이 삼킨다.
   그건 성격이 다른 사고다.
3. **④ 반영이 끝나면 곧바로 silence 를 만료시킨다.** 만료를 기다리지 않는다.

```bash
kubectl -n dodam exec $AM -- amtool silence expire <silence-id> --alertmanager.url=http://localhost:9093
```

### 어느 쪽이든, 이건 남긴다

silence 를 걸든 안 걸든 **팀 채널에 한 줄은 남긴다** — "지금 뜨는 드리프트 경보는
904 의 mysql 시간대 한 줄이고, X일 X시에 반영 예정이다."
경보를 끄는 것보다 **경보의 의미를 팀이 공유하는 것**이 알람 피로의 실제 해법이다.

---

## 6. 이 작업에서 절대 하지 말 것 (요약)

- 🚫 `kubectl apply -k infra/k8s/overlays/prod` — 이미지 태그 `:prod` 회귀 + 광범위 재시작
- 🚫 `kubectl apply -f infra/k8s/base/mysql.yaml` — base 에는 overlay 가 덮는 값이 없다
- 🚫 `rollout restart statefulset/mysql` — args 를 안 바꾸고 중단만 만든다(무의미)
- 🚫 드리프트 CronJob `suspend`
- 🚫 만료 없는 Alertmanager silence
- 🚫 `partition` 으로 spec 만 반영(§5 E)
- 🚫 ②(c) 스냅샷 `OK` 확인 없이 ④ 진행
- 🚫 발표 당일(08/10) 실행

---

## 7. 남은 시간대 공백 (이 작업 범위 밖, 후속 제안)

904 는 **애플리케이션 워크로드**를 KST 로 맞췄다. **데이터 계층 컨테이너는 아직 UTC** 다.

```
kubectl get sts <name> -o jsonpath='{...containers[0].env[?(@.name=="TZ")]}'
  mongodb → (없음)     redis → (없음)     minio → (없음)     mysql → (없음)
```

실측 — mongod 로그는 UTC 로 찍힌다:

```json
{"t":{"$date":"2026-08-05T04:55:29.001+00:00"}, ...}
```

백업 CronJob 3종과 alertmanager 는 이미 `TZ: Asia/Seoul` 이라 로그가 `+0900` 이다.
**같은 사건을 mongo-backup 로그는 KST, mongod 로그는 UTC 로 적는다** — 장애 조사에서
두 로그를 나란히 놓고 볼 때 정확히 904 가 잡으려던 종류의 오독이 다시 생긴다.

- **영향 범위**: 로그 타임스탬프뿐. MongoDB 는 내부적으로 UTC 로 저장하므로 **데이터에는 영향이 없다**
  (MySQL 의 `--default-time-zone` 과 성격이 다르다 — 그건 `NOW()`·`DEFAULT CURRENT_TIMESTAMP` 값에 영향을 준다).
- **비용**: mongodb·redis·minio STS 에 `TZ: Asia/Seoul` env 한 줄씩. 다만 **셋 다 재시작**을 부른다.
- **제안**: 별도 백로그로 분리하고, **발표 이후**에 이번 MySQL 작업과 같은 절차로 처리한다.
  급하지 않다(데이터 무영향). 지금 묶어서 하면 한 번에 흔드는 범위만 커진다.

부수 관찰 하나 — `dodam-config.SPRING_PROFILES_ACTIVE = local` 이다.
운영에서 `local` 프로파일을 쓰는 것은 별개 사안이지만, 이번 조사 중 눈에 띄어 적어둔다.
