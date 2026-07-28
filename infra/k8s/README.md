# 도담 k8s 매니페스트 (S15P11B209-357)

> compose 스택을 k3s 로 옮기기 위한 리소스 정의. **아직 아무것도 배포하지 않았다.**
> 선행 356(k3s 설치) · 후속 358(스테이징 검증) → 359(Jenkins 전환) → 360(컷오버) → 362(성능 실증)

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
│   ├── pvc.yaml             letsencrypt · webroot · apk · backend-storage · ai-models · db-backup
│   ├── mysql.yaml           StatefulSet + headless Service
│   ├── redis.yaml           StatefulSet + headless Service
│   ├── minio.yaml           StatefulSet + headless Service
│   ├── backend.yaml         Deployment ×2 + Service + PDB   ★ 무중단의 핵심
│   ├── ai.yaml              Deployment + Service
│   ├── gateway.yaml         nginx Deployment + conf ConfigMap + Service
│   ├── jenkins-external.yaml  셀렉터 없는 Service + 수동 Endpoints
│   └── cronjobs.yaml        certbot 갱신 · DB 백업(기본 suspend)
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

이 스크립트가 compose 의 `${VAR:?}` fail-fast 를 대신한다 — 필수 키 13종이 **존재하고
비어 있지 않은지** 검사하고, `JWT_SECRET` 이 32바이트 이상인지도 본다.
(값은 절대 출력하지 않는다 — 키 이름만)

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

> ⚠️ `base/jenkins-external.yaml` 의 IP `10.0.0.1` 은 **자리표시자**다. 노드 InternalIP 로 교체해야 하고,
> Jenkins 는 지금 `127.0.0.1:9090` 으로만 바인딩돼 있어 파드에서 닿지 않는다.
> 이 두 가지가 해결되기 전까지 `/jenkins/` 는 502 다 — 359 와 함께 결정한다.
> `/grafana/` 는 361 소관이라 그때까지 역시 502 다. **둘 다 게이트웨이 전체를 막지는 않는다**
> (변수+resolver 패턴 덕분 — 고정 `proxy_pass` 였다면 nginx 가 통째로 못 떴을 것).

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

2026-07-28 실측(available 4.4GB · swap 2GB 사용 중) 기준으로 잡았다.

| 워크로드 | 실측 | requests | limits | 비고 |
|---|---|---|---|---|
| backend | 760MB | 768Mi ×N | 1536Mi | 최대 소비자 |
| mysql | 490MB | 512Mi | 1Gi | OOMKill 이 가장 위험 |
| minio | 237MB | 256Mi | 1Gi | 캐시로 여유 메모리를 흡수하는 성격 |
| ai | 77MB | 128Mi | 512Mi | |
| redis | 4.4MB | 64Mi | 256Mi | AOF 재작성 여유 |
| gateway | 5.5MB | 32Mi | 128Mi | |

- **staging(backend ×1) 합계 requests ≈ 1.7GB**
- **prod(backend ×2) 합계 requests ≈ 2.5GB**

⚠️ 358 구간에서는 compose 스택(약 1.6GB)과 **동시에** 떠 있다. 여기에 k3s 자체 600MB~1GB 를
더하면 4GB 안팎이 된다. **Jenkins 빌드(단독 4.5GB)가 겹치면 확실히 스왑으로 밀린다.**
그래서 staging overlay 는 backend 를 1벌로 낮춘다.

---

## 아직 하지 않은 것 / 컷오버 위험

### 🔴 데이터 이관이 최대 난제다

이 매니페스트의 PVC 는 **전부 비어 있는 채로** 생성된다. compose 볼륨의 내용은 자동으로
넘어오지 않는다.

| 데이터 | 어디에 | 이관 안 하면 |
|---|---|---|
| MySQL | `dodam_mysql-data` | 빈 DB — 회원·활동 전부 없음 |
| MinIO **(아동 그림·음성)** | `dodam_minio-data` (객체 71개) | 파일 전부 유실처럼 보임 |
| letsencrypt 인증서 | `dodam_letsencrypt` | **TLS 가 깨진다 — 서비스 접속 불가** |

358(스테이징)에서 빈 상태로 뜨는 것은 **정상이자 의도**다 — 운영 데이터와 섞지 않는다.
문제는 360이고, 이관 절차 확정이 컷오버의 선행 조건이다.

### 그 밖에

- **db-backup CronJob 은 `suspend: true`** — Secret `dodam-backup`(BACKUP_PASSPHRASE)과
  복원 드릴 1회가 끝나기 전에는 켜지 않는다. 호스트 cron 과 동시에 켜지 말 것.
- **kube-dns IP `10.43.0.10`** 은 k3s 기본값이다. 설치 후 실측 확인:
  `kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}'`
  (nginx `resolver` 는 IP 리터럴만 받아 환경변수·호스트명을 쓸 수 없다)
- **nginx conf 가 두 벌**이다 — `infra/nginx/conf.d/default.conf`(compose)와
  `base/gateway.yaml`의 ConfigMap. 360 까지는 둘을 함께 고쳐야 한다. 갈라지면 컷오버에서 사고가 난다.
- **모니터링(Prometheus·Grafana)은 없다** — S15P11B209-361 소관.
- **local-path 는 노드 로컬 디스크**다. 노드가 늘면 파드가 다른 노드로 가는 순간 데이터에
  접근하지 못한다.

---

## 검증한 것

- `kustomize build overlays/staging` · `overlays/prod` **양쪽 성공** (각 26 리소스)
- 렌더링 결과 실물 확인: staging = NodePort 30080/30443 · backend replicas 1 · `:staging` 태그 /
  prod = hostPort 80/443 · backend replicas 2 · `:prod` 태그
- prod gateway 포트 병합이 `containerPort` + `hostPort` 로 올바르게 합쳐짐(중복 없음)
- 프로브 경로 5종 전부 운영 컨테이너에서 실제 응답 확인
- `sync-secrets.sh` bash 구문 통과

**클러스터에는 적용하지 않았다** — k3s 가 아직 설치되지 않았고(356 미실행),
`kubectl apply` 는 서버 상태를 바꾸는 작업이다.
