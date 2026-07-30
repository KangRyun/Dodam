# 도담 k8s 매니페스트 (S15P11B209-357)

> ## ⚠️ 이 매니페스트가 **운영을 돌리고 있다.**
>
> 2026-07-29 **360 컷오버 완료** — 운영 트래픽은 100% k3s 가 받는다(다운타임 3분 16초).
> 남아 있는 compose 워크로드는 `dodam-jenkins`·`dodam-registry`·`dodam-certbot` **셋뿐**이고
> 의도된 구성이다. 저장소(MySQL·Redis·MinIO·MongoDB)는 전부 k3s 로 넘어왔다.
>
> **연습장이 아니다.** 여기서 `kubectl apply -k overlays/prod` 를 돌리면 운영이 즉시 바뀐다.
> 아래 "손대기 전에 알아야 할 것"을 먼저 읽을 것.
>
> 진행 경과: 356(k3s 설치) → 357(매니페스트) → 358(스테이징 검증) → 359(Jenkins 전환) →
> **360(컷오버 ✅)** → 361(모니터링) · 733(백업 CronJob·경보) · 362(성능 실증, 355 대기)

---

## 손대기 전에 알아야 할 것

**① `apply -k overlays/prod` 는 이미지 태그를 되돌린다.**
매니페스트의 이미지는 `:prod` 태그인데, 지금 도는 것은 Jenkins 가 박은 **커밋 SHA 태그**다.
전체 apply 를 하면 `:prod` 로 덮어써져 "무엇이 배포됐는지" 추적성이 사라진다(내용은 같다).
특정 리소스만 고치려면 그 리소스만 골라 apply 하거나 `kubectl patch` 를 쓴다.

**② Secret 은 kustomize 밖에 있다.**
`base/kustomization.yaml` 에 Secret 이 없는 것은 실수가 아니라 설계다. 값이 빈 매니페스트를
apply 하는 순간 운영 비밀이 통째로 지워지기 때문이다. Secret 은 `infra/scripts/sync-secrets.sh`
로만 만들고 갱신한다.

**③ `jenkins-external.yaml` 은 kustomize 에서 일부러 뺐다.**
`commonLabels` 가 Service 의 selector 에도 주입되는데, 이 Service 는 selector 가 없어야만
수동 Endpoints 가 유지된다. 그 한 파일만 `kubectl apply -f` 로 직접 적용한다.

**④ 배포 계정에는 apply 권한이 없다.**
Jenkins 는 네임스페이스 한정 SA 로 `set image` 와 rollout 조회만 한다. **매니페스트 변경은
사람이 apply 해야 반영된다** — MR 이 머지됐다고 클러스터에 적용된 것이 아니다.
(2026-07-30, `f65fc9e`(AI 모드 http)가 develop 에 머지된 채 클러스터에 적용되지 않아
 하루 종일 mock 으로 돌던 사례가 있다.)

> ⚠️ **이 경고는 원래 여기 적혀 있었는데도 같은 날 또 당했다.**
> 365(스트로크 MongoDB) 가 `backend.yaml` 에 `MONGO_APP_*` env 를 정확히 넣었지만 아무도
> apply 하지 않았고, 새 파드가 빈 비밀번호로 뜨려다 설정 바인딩 NPE → CrashLoopBackOff →
> 배포 실패했다. 구 파드가 계속 서빙해서(maxUnavailable: 0) 장애가 없었던 탓에 더 늦게 알았다.
> **문서로는 막히지 않는다**는 게 이날의 결론이고, 그래서 아래 절차와 자동 감시(751)를 뒀다.

---

## 매니페스트를 고친 뒤 반영하기

머지는 반영이 아니다. 아래 절차를 따른다.

### 1. 무엇이 어긋나 있는지 먼저 본다

```bash
./infra/scripts/check-manifest-drift.sh          # 클러스터를 읽기만 한다
```

`0` 반영 완료 · `1` 미반영 있음 · `2` 점검 자체가 실패(권한·연결). **2 를 0 으로 읽지 말 것.**

`kubectl diff -k` 를 쓰지 않는 이유가 있다. 그건 내부적으로 `PATCH ...?dryRun=All` 을 보내는데
쿠버네티스는 dry-run 도 실제 쓰기와 동일하게 인가한다. 즉 **읽기 권한만으로는 돌지 않고**,
돌리려면 ClusterRole 에까지 patch 권한이 필요하다. 위 스크립트는 `kubectl get` 만 쓴다.

### 2. 필요한 것만 골라 반영한다

⚠️ **`kubectl apply -k overlays/prod` 를 통째로 돌리지 말 것** — 이미지 태그가 `:prod` 로
되돌아가 지금 배포된 빌드가 무엇이었는지 사라진다(위 ①).

| 바뀐 것 | 반영 방법 |
| --- | --- |
| ConfigMap 키 추가·수정 | `kubectl -n dodam patch cm <name> --type merge -p '{"data":{"K":"V"}}'` |
| Deployment 의 env | `kubectl -n dodam set env deployment/<name> --from=secret/dodam-secrets --keys=A,B` |
| 그 외 필드 | 해당 필드만 `kubectl -n dodam patch` |
| 새로 생긴 리소스 | `kubectl apply -f <그 파일 하나만>` |

⚠️ **`kubectl apply -f base/configmap-app.yaml` 도 금지.** prod overlay 가 덮어쓰는
`AI_*_MODE=http` 가 base 의 `mock` 으로 회귀한다 — 360 컷오버 직후 TTS 가 무음이던 원인이
정확히 이것이다.

### 3. ConfigMap 만 바꿨으면 롤아웃을 직접 건다

`envFrom` 으로 읽는 값은 파드 기동 시점에만 반영된다. ConfigMap 을 고쳐도 도는 파드는 모른다.

```bash
kubectl -n dodam rollout restart deployment/backend
```

### 4. 다시 확인한다

```bash
./infra/scripts/check-manifest-drift.sh          # 0 이 나와야 끝난 것
```

### 자동 감시

매시 20분에 `manifest-drift-check` CronJob 이 같은 점검을 돌린다. 드리프트가 있으면 Job 이
실패로 남고 → Prometheus `ManifestDriftDetected` → Alertmanager → Mattermost 로 알린다.
기본값은 `suspend: true` 이며 해제 절차는 `base/manifest-drift.yaml` 주석 참조.

---

## 이 설계의 한 줄

**Service 이름을 compose 서비스명과 똑같이 유지해서, 앱의 접속 값을 하나도 바꾸지 않는다.**

```
backend 의 DB_HOST=mysql          → Service/mysql   그대로 해석
        AI_BASE_URL=http://ai:8000 → Service/ai      그대로 해석
nginx 의 proxy_pass http://backend:8080 → Service/backend 그대로 해석
```

한 네임스페이스(`dodam`) 안에서는 짧은 이름이 그대로 DNS 로 풀리기 때문에 가능하다.
이게 깨지면 앱 코드·설정을 전부 손봐야 하고 전환 위험이 몇 배가 된다.

---

## 구조

```
infra/k8s/
├── base/                    ← 단독 apply 금지 (이미지 태그·노출 방식 비어 있음)
│   ├── namespace.yaml
│   ├── configmap-app.yaml   비밀 아닌 설정 전부
│   ├── pvc.yaml             letsencrypt · webroot · apk · backend-storage · ai-models
│   │                          (db-backup PVC 는 733 에서 제거 — 백업은 hostPath)
│   ├── mysql.yaml           StatefulSet + headless Service
│   ├── redis.yaml           StatefulSet + headless Service
│   ├── minio.yaml           StatefulSet + headless Service
│   ├── backend.yaml         Deployment ×2 + Service + PDB   ★ 무중단의 핵심
│   ├── ai.yaml              Deployment + Service
│   ├── gateway.yaml         nginx Deployment + conf ConfigMap + Service
│   ├── jenkins-external.yaml  셀렉터 없는 Service + 수동 Endpoints
│   ├── cronjobs.yaml        certbot 갱신 · MySQL·Mongo·MinIO 백업 (prod 에서 활성)
│   └── monitoring-*.yaml    Prometheus · Alertmanager · Grafana · exporters · 대시보드
└── overlays/
    ├── staging/   NodePort 30080/30443 · backend ×1   ← 358 검증용, 운영 포트 미점유
    └── prod/      hostPort 80/443     · backend ×2    ← 360 컷오버 시점에만
```

---

## 설계 결정 5가지

### ① Secret 은 kustomize 가 관리하지 않는다

`base/kustomization.yaml` 에 Secret 이 없는 것은 실수가 아니다.

kustomize 가 Secret 을 들고 있으면 **값이 빈 매니페스트를 한 번 apply 하는 순간 운영 비밀이
통째로 지워진다.** k8s 는 이전 값을 보관하지 않아 되돌릴 방법도 없다.

그래서 Secret 은 값이 있는 `.env` 를 들고 있을 때만 스크립트로 만든다:

```bash
infra/scripts/sync-secrets.sh infra/.env --dry-run   # 검사만
infra/scripts/sync-secrets.sh infra/.env             # 실제 적용
```

이 스크립트가 compose 의 `${VAR:?}` fail-fast 를 대신한다 — 필수 키 18종이 **존재하고
비어 있지 않은지** 검사하고, `JWT_SECRET` 이 (공백 제외) 32바이트 이상인지도 본다.
또 **모든 키**에 대해 선두/꼬리 공백 오염을 검출해 실패시킨다(S15P11B209-730).
(값은 절대 출력하지 않는다 — 키 이름과 길이만)

### ② 외부 노출 방식을 base 가 정하지 않는다

`base` 의 gateway Service 는 ClusterIP 다. 80/443 을 언제 잡을지는 overlay 가 정한다.

| overlay | 노출 | 쓰는 때 |
|---|---|---|
| staging | NodePort 30080/30443 | 358 — compose 가 서비스하는 동안 옆에서 검증 |
| prod | hostPort 80/443 | 360 — 컷오버 시점에만 |

356 의 "라이브 무접촉" 원칙을 **디렉토리 구조로 강제**한 것이다.
staging 을 아무리 apply 해도 운영 포트를 건드릴 수 없다.

> LoadBalancer 를 쓰지 않은 이유: 356 권고대로 `--disable servicelb` 로 ServiceLB 를 껐기 때문.
> 노드가 하나뿐이라 hostPort 가 가장 단순하고 경로도 짧다.

### ③ 무중단은 backend 에서만 보장한다

```yaml
strategy:
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0     # ← 옛 파드를 먼저 지우지 않는다
```

`readinessProbe` 가 통과한 새 파드가 생긴 **뒤에** 옛 파드를 내린다.
지금 compose 의 `up -d`(죽이고 새로 띄움)와 근본적으로 다른 지점이고,
S15P11B209-362 가 수치로 증명할 대상이다.

**게이트웨이는 무중단이 아니다.** hostPort 는 노드당 한 파드만 잡을 수 있어
`maxSurge: 0`(먼저 내리고 올리기)으로 갈 수밖에 없다 — 수 초 끊긴다.
게이트웨이의 무중단은 노드가 둘 이상이어야 얻는다(3차 과제).

### ④ 프로브 경로는 전부 실측으로 확인했다

| 대상 | 경로 | 실측 응답 |
|---|---|---|
| backend | `:9404/actuator/health/liveness` | `{"status":"UP"}` |
| backend | `:9404/actuator/health/readiness` | `{"status":"UP"}` |
| ai | `:8000/health` | `{"status":"ok"}` |
| minio | `:9000/minio/health/live` | `200` |
| gateway | `:80/` | `301` |

**actuator 는 8080 이 아니라 9404 다**(`management.server.port`). nginx 가 8080 만
프록시하도록 일부러 분리한 구조라 `8080/actuator/health` 는 404 다 — 여기에 프로브를
걸면 파드가 영원히 Ready 가 되지 않는다.

gateway 프로브가 `/`(301)인 것도 같은 이유다. **k8s httpGet 프로브는 2xx·3xx 만 성공으로
보고 404 는 실패로 센다.** `/.well-known/acme-challenge/`(404)로 걸면 절대 Ready 가 안 된다.

`startupProbe` 를 셋 다 넣은 이유: 부팅 중에 `livenessProbe` 가 먼저 실패해 파드를
죽이는 크래시 루프를 막는다. compose 의 `start_period` 에 해당한다.

### ⑤ 클러스터 밖 Jenkins 는 수동 Endpoints 로 연결한다

**셀렉터가 없는 Service** 를 만들면 k8s 가 Endpoints 를 자동으로 채우지 않는다.
그 자리에 노드 주소를 손으로 적어 넣으면, 클러스터 안에서는 평범한 Service 처럼 보이지만
트래픽은 호스트로 나간다.

> ✅ **둘 다 해결됐다**(359·361). `/jenkins/` 와 `/grafana/` 모두 게이트웨이를 통해 응답한다
> (각자 로그인 필요). Prometheus 는 **공개 라우트가 없다** — `/prometheus/` 는 랜딩 페이지
> catch-all 이 200 을 줄 뿐이다. UI 가 필요하면 `kubectl port-forward` 를 쓴다.
>
> ⚠️ `base/jenkins-external.yaml` 을 kustomize 에서 뺀 이유는 위 "손대기 전에" ③ 참조.
> 변수+resolver 패턴은 그대로 유지한다 — 고정 `proxy_pass` 면 업스트림 부재 시 nginx 가
> 통째로 못 뜬다.

---

## 사용법

```bash
# 0. 렌더링 결과부터 눈으로 본다 (클러스터 미변경)
kubectl kustomize infra/k8s/overlays/staging | less

# 1. 비밀 주입 (kustomize 밖 — ① 참조)
infra/scripts/sync-secrets.sh infra/.env

# 2. 적용
kubectl apply -k infra/k8s/overlays/staging

# 3. 확인
kubectl -n dodam get pods,svc,pvc
kubectl -n dodam rollout status deployment/backend
curl -I http://127.0.0.1:30080/          # 301 이면 게이트웨이 정상

# conf(ConfigMap)만 바꿨을 때는 롤아웃을 직접 걸어야 한다
kubectl -n dodam rollout restart deployment/gateway
```

---

## 메모리 예산

2026-07-28 실측 기준으로 잡고, 이후 실제 부하로 드러난 값은 갱신했다.

| 워크로드 | 실측 | requests | limits | 비고 |
|---|---|---|---|---|
| backend | 760MB | 768Mi ×N | 1536Mi | 최대 소비자 |
| mysql | 490MB | 512Mi | 1Gi | OOMKill 이 가장 위험 |
| minio | 237MB | 256Mi | 1Gi | 캐시로 여유 메모리를 흡수하는 성격 |
| ai | 405MB | 256Mi | 1Gi | 512Mi 에서 OOMKilled — 실 AI 모드 전환 후 상향(738) |
| redis | 4.4MB | 64Mi | 256Mi | AOF 재작성 여유 |
| gateway | 5.5MB | 32Mi | 128Mi | |

- **staging(backend ×1) 합계 requests ≈ 1.7GB**
- **prod(backend ×2) 합계 requests ≈ 2.5GB**

⚠️ 358 구간에서는 compose 스택(약 1.6GB)과 **동시에** 떠 있다. 여기에 k3s 자체 600MB~1GB 를
더하면 4GB 안팎이 된다. **Jenkins 빌드(단독 4.5GB)가 겹치면 확실히 스왑으로 밀린다.**
그래서 staging overlay 는 backend 를 1벌로 낮춘다.

---

## 끝난 것 / 남은 위험

### ✅ 데이터 이관 (360, 2026-07-29)

컷오버의 최대 난제였고, 끝났다. MySQL 덤프→복원 · MinIO mirror · letsencrypt 복사를
모두 마친 뒤 overlay 를 올렸다. 다운타임 3분 16초.

> ⚠️ **정지된 compose 컨테이너를 다시 켜지 말 것.** `dodam-mysql`·`dodam-minio` 는
> 2026-07-29 23:55 에 멈췄고 **컷오버 이전 데이터**를 갖고 있다. 켜면 조회도 되고 백업도
> 성공하는데 **내용만 과거**다. 백업 스크립트가 정확히 그 함정에 빠질 뻔했다(S15P11B209-732).

### ✅ 백업 (733, 2026-07-30)

`db-backup`·`mongo-backup`·`minio-backup` 세 CronJob 이 **활성 상태로 돌고 있다.**
호스트 cron 은 제거됐다. 산출물은 hostPath `/var/backups/dodam`(PVC 아님 — 기존 백업과
같은 곳에 모아 복원 절차를 한 벌로 유지한다).

| CronJob | 시각(KST) | timeZone |
|---|---|---|
| `db-backup` | 04:00 | `Asia/Seoul` |
| `mongo-backup` | 04:30 | `Asia/Seoul` |
| `minio-backup` | 00:30·06:30·12:30·18:30 | `Asia/Seoul` |

> ⚠️ **`timeZone` 을 빼면 UTC 로 해석된다.** 파드도 기본이 UTC 다. `0 4 * * *` 가
> 13:00 KST 에 뜬다. 스케줄 해석(`spec.timeZone`)과 컨테이너 `date`(`TZ` env)는 **별개**라
> 둘 다 필요하다.

실패는 Alertmanager 를 거쳐 Mattermost 로 통보된다(`BackupJobFailed`·`BackupMissing`·`BackupSuspended`).
361 에서 경보 룰만 옮기고 Alertmanager 를 두지 않아 **그때까지 메모리 경보 3종이 아무데도
통보되지 않고 있었다** — 733 에서 함께 세웠다.

### 남은 위험

- **kube-dns IP `10.43.0.10`** 은 k3s 기본값이다. 실측 확인:
  `kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}'`
  (nginx `resolver` 는 IP 리터럴만 받아 환경변수·호스트명을 쓸 수 없다)
- **nginx conf 가 두 벌**이다 — `infra/nginx/conf.d/default.conf`(compose)와
  `base/gateway.yaml`의 ConfigMap. 운영은 후자를 쓴다. 갈라지면 다음 사고가 여기서 난다.
- **`certbot` 이 Docker·k3s 양쪽에 있다** — 갱신 경로가 이중화돼 있다. 정리 필요.
- **local-path 는 노드 로컬 디스크**다. 노드가 늘면 파드가 다른 노드로 가는 순간 데이터에
  접근하지 못한다. 백업 hostPath 도 같은 제약을 갖는다.
- **`mysql-0` 이 상한의 66%**(677Mi/1024Mi). 컷오버 때 2g→1Gi 로 줄인 값이라 지켜볼 것.
- **MinIO 복원 드릴 미수행** — MySQL 만 했다(S15P11B209-737).

---

## 검증한 것

- 렌더링: `overlays/staging`·`overlays/prod` 양쪽 빌드 성공
- 프로브 경로 5종 전부 실제 응답 확인 (**actuator 는 9404** · 404 를 프로브에 걸지 말 것)
- 무중단 롤링: backend `maxUnavailable: 0` 으로 컷오버 후 여러 차례 실증
- 복원 드릴 1회 성공 (733) — CronJob 산출물을 임시 파드에 복원해 **69/69 테이블 대조**
- 경보 발송 경로 실증 — `alertmanager_notifications_total{integration="slack"}` 증가 확인

**지금은 이 매니페스트가 운영을 돌리고 있다.** 문서 맨 위 경고를 다시 읽을 것.
