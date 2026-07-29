# k3s 단일 노드 설치 runbook (S15P11B209-356)

> 대상: EC2 `i15b209.p.ssafy.io` (Ubuntu 24.04, 단일 노드). 담당: Infra(이강륜).
> 목적: compose→k8s 전환(357~362)의 **기반만** 깔기. 이 문서 범위에서 서비스는 **하나도 옮기지 않는다.**
> 후속: 357(kustomize 매니페스트) → 358(스테이징 검증) → 359(Jenkins kubectl 전환) → 360(컷오버)

⚠️ **이 문서의 명령은 서버 상태를 바꾼다. 제안이지 실행이 아니다 — 강륜님이 직접 실행한다.**
각 단계마다 "무엇을 확인하고 다음으로 넘어가는지"가 붙어 있다. 확인 없이 다음 단계로 가지 않는다.

---

## 라이브 무접촉 원칙

지금 이 EC2는 **운영 중**이다. 팀 시연·개발이 이 서버를 쓴다.

- k3s를 깔되 **워크로드는 올리지 않는다.** 80/443은 계속 기존 nginx가 가진다.
- 그래서 `--disable traefik` 이다. Traefik이 들어오면 인그레스 두 개가 같은 포트를 노린다.
- **성공 기준은 "k3s가 떴다"가 아니라 "k3s를 깔았는데 기존 서비스가 그대로다"** 이다.

---

## 사전 조건 — 2026-07-28 실측

| 항목 | 실측값 | 판단 |
|---|---|---|
| OS / 커널 | Ubuntu 24.04.4 LTS / 6.17.0-1017-aws | ✅ |
| cgroup | v2 (`cgroup2fs`) | ✅ k3s 요구 충족 |
| Docker | 29.6.2, overlayfs, cgroup driver `systemd` | ✅ 공존 가능 |
| 디스크 | 309G 중 232G 여유 | ✅ |
| 포트 5000 / 6443 / 10250 | 전부 비어 있음 | ✅ |
| **메모리** | 15,987MB 중 **available 4,421MB**, free 349MB | ⚠️ **빠듯하다** |
| **스왑** | 4,095MB 중 **2,058MB 이미 사용 중** | ⚠️ 이미 압박이 있다는 신호 |

### ⚠️ 메모리가 이 작업의 진짜 제약이다

실행 중 컨테이너 실측(2026-07-28 17:30):

```
dodam-jenkins   4,571MB  (빌드 중 — CPU 285%)
dodam-backend     760MB
dodam-mysql       490MB
dodam-minio       237MB
dodam-ai           77MB
그 외(nginx·redis·grafana·prometheus·cadvisor 등) 합계 약 170MB
+ Testcontainers MySQL 3~4개 (빌드 중에만, 개당 약 330MB)
```

- k3s 서버(API server + etcd(sqlite) + kubelet + CoreDNS + flannel)만으로 **약 600MB~1GB**가 더 든다.
- **358(스테이징 검증)에서는 앱을 compose와 k3s에 동시에 띄운다.** backend+mysql+minio 사본이
  추가로 약 1.5GB → 합계 **2.5GB 안팎이 더 필요**하다. available 4.4GB에서 감당은 되지만,
  **Jenkins 빌드가 동시에 돌면 확실히 스왑으로 밀리고 응답시간이 무너진다.**

### 🔴 2026-07-28 — 이 경고는 실제로 현실이 됐다

위 경고를 쓴 당일 저녁, **k3s 세팅 중 메모리가 고갈돼 EC2 가 응답 불능이 됐고 재부팅으로만
복구했다.** 진행 중이던 Android AAB 빌드(623)도 함께 날아갔다. 원인은 하나가 아니라 셋이었다:

1. 스왑이 4GB뿐이었고 그중 2GB를 이미 쓰고 있었다 — 버틸 여유가 없었다
2. **모든 컨테이너에 메모리 상한이 없었다** — 하나가 폭주하면 호스트 전체를 끌고 간다
3. **earlyoom 이 없었다** — 커널은 프로세스를 죽이는 대신 페이지 회수에 매달렸고,
   스왑이 EBS(네트워크 디스크) 위라 회수가 느려 시스템이 thrash 로 굳었다.
   "죽지도 살지도 않는" 상태 — SSH 조차 붙지 않아 재부팅 외 복구 수단이 없었다

대응은 `docs/인프라/메모리-OOM-대응.md` 에 정리했다. **아래 사전 점검을 통과하지 못하면
이 runbook 을 시작하지 않는다.**

**→ 설치·검증은 빌드가 돌지 않는 시간대에 한다.** 시작 전에 반드시:

```bash
# 가용 RAM · 스왑 잠식 · earlyoom · 무제한 컨테이너 · Jenkins 빌드 여부를 한 번에 판정한다.
# 통과하지 못하면 종료코드 1 로 막는다(이유 출력).
infra/scripts/preflight-memory.sh --need 6144
```

`--need 6144` 는 k3s 서버(약 1GB) + 358 스테이징 앱 사본(약 1.5GB) + 여유를 합친 값이다.
이 스크립트가 ⛔ 를 내면 **미룬다.** 눈으로 `free -h` 를 보고 "될 것 같다"로 판단하지 않는다 —
07-28 에 그렇게 판단해서 서버가 죽었다.

아직 방어가 적용되지 않았다면 먼저:

```bash
sudo bash infra/scripts/setup-swap.sh    # 스왑 16GB + 커널 튜닝 + earlyoom
```

> 참고: kubelet은 원래 스왑이 켜져 있으면 기동을 거부하지만 k3s는 이를 완화해 띄운다.
> 다만 **이 서버에서 확인한 적이 없다.** 3단계에서 노드가 `Ready`인지로 판정한다.
> `NotReady`면 스왑이 원인일 수 있다 — 추측하지 말고 `sudo journalctl -u k3s -n 100`을 본다.

---

## 위험 3가지와 대응

| # | 위험 | 왜 생기나 | 대응 |
|---|---|---|---|
| 1 | **iptables 간섭** | k3s(kube-proxy·flannel)가 자기 규칙을 넣는다. Docker도 `DOCKER`·`DOCKER-USER` 체인을 쓴다. 규칙 순서가 꼬이면 컨테이너 간 통신이나 외부 접속이 끊긴다 | 설치 **전에 규칙을 저장**해 두고 설치 후 비교. 서비스 e2e가 하나라도 깨지면 즉시 롤백 |
| 2 | **메모리 고갈** | 위 표 참조 | 빌드 없는 시간대 + 358에서 동시 기동 시 사전 재확인 |
| 3 | **80/443 탈취** | k3s의 ServiceLB(klipper)가 `LoadBalancer` 타입 Service를 만나면 **호스트 포트를 잡는다**. 실수로 하나 만들면 nginx와 충돌해 서비스가 죽는다 | `--disable servicelb`로 **기능 자체를 끈다**(아래 참조) |

### `--disable servicelb`를 권합니다

이슈 본문은 *"LB Service는 컷오버까지 미생성"* 으로 잡혀 있습니다. 그건 **약속**이고,
`--disable servicelb`는 **장치**입니다. 지키기로 한 것과 지켜지는 것은 다릅니다 —
잘못 붙인 매니페스트 하나로 운영 80/443이 넘어가는 걸 사람이 안 만드는 걸로 막지 않습니다.

컷오버(360) 때 다시 켜면 됩니다(`/etc/systemd/system/k3s.service`의 `--disable servicelb`
제거 → `daemon-reload` → `restart`). 또는 계속 끈 채로 nginx가 NodePort로 프록시하는 구성도
가능하며, **그 편이 전환 폭이 작습니다.** 어느 쪽으로 갈지는 357에서 결정합니다.

---

## 절차

### 0단계 — 기준선 저장 (반드시 먼저)

무엇을 되돌려야 하는지 모르면 롤백도 못 합니다.

**스크립트로 한 번에** (S15P11B209-358 — 아래 수동 절차를 자동화한 것):

```bash
infra/scripts/k3s-baseline.sh capture before
```

서비스 e2e 4종 · 컨테이너 목록/상태 · 리슨 포트 · 메모리를 파일로 굳혀 둡니다.
`iptables` 스냅샷만 sudo가 필요해, 없으면 그 항목만 건너뛰고 나머지는 그대로 캡처합니다
(같이 받으려면 `sudo iptables-save > ~/.local/state/dodam/k3s-baseline/before/iptables.rules`).

설치 후에는 `capture after` → `compare`로 **기계가 대조**합니다(4단계 참조).
눈으로 비교하면 "컨테이너 하나가 조용히 재시작됐다" 같은 걸 놓칩니다.

<details><summary>수동으로 하려면 (스크립트가 하는 일)</summary>

```bash
cd ~/S15P11B209

# 서비스 정상 응답 — 이 3줄이 설치 후에도 똑같이 나와야 한다
curl -s -o /dev/null -w 'landing  %{http_code}\n' https://i15b209.p.ssafy.io/
curl -s -o /dev/null -w 'ai       %{http_code}\n' https://i15b209.p.ssafy.io/ai/health
curl -s -o /dev/null -w 'api-401  %{http_code}\n' https://i15b209.p.ssafy.io/api/v1/users/me

# 컨테이너 상태와 방화벽 규칙 스냅샷
docker ps --format '{{.Names}}\t{{.Status}}' | sort > /tmp/before-k3s-containers.txt
sudo iptables-save > /tmp/before-k3s-iptables.rules
sudo ip6tables-save > /tmp/before-k3s-ip6tables.rules
wc -l /tmp/before-k3s-*.rules
```

**기대:** `landing 200` · `ai 200` · `api-401 401`. — 2026-07-28 실측으로 확인한 값입니다.
401이 정상입니다 — 토큰 없이 보호 경로를 부른 것이니 인가가 살아 있다는 뜻입니다.

</details>

> 2026-07-29 실측 기준선: `landing 200 · ai 200 · api 401 · legal 200` · 컨테이너 12개 · 가용 8.5GB

---

### 1단계 — 로컬 레지스트리 기동

```bash
docker compose -f infra/jenkins/docker-compose.yml up -d registry
curl -fsS http://127.0.0.1:5000/v2/ && echo "  ← 레지스트리 정상"
```

**기대:** `{}` 출력. 외부에서는 닫혀 있어야 정상입니다:

```bash
curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://i15b209.p.ssafy.io:5000/v2/   # 000/타임아웃이 정상
```

**왜 레지스트리가 필요한가** — 지금 파이프라인은 이미지를 만들어 **호스트 Docker 데몬 안에만**
둡니다(`dodam-backend:local` → `:<SHA>`, push 없음). 그런데 k3s는 Docker가 아니라
**containerd**를 씁니다. 둘은 이미지 저장소가 완전히 별개라서 k3s는 Docker의 이미지를
**볼 수 없습니다.** 그래서 둘이 함께 보는 레지스트리를 중간에 둡니다.

```
Jenkins ─ docker build ─→ docker push 127.0.0.1:5000/... ─→ k3s(containerd) ─ pull
```

---

### 2단계 — k3s 설치

**버전을 먼저 고릅니다.** `latest`로 깔면 다음에 재설치할 때 다른 게 깔립니다.
설치 시점에 실제 존재하는 안정 버전을 확인하세요:

```bash
curl -s https://api.github.com/repos/k3s-io/k3s/releases | grep -oE '"tag_name": "[^"]+"' | head -10
```

고른 버전을 넣고 설치합니다:

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="<위에서 고른 태그>" sh -s - \
    --disable traefik \
    --disable servicelb \
    --kubelet-arg=system-reserved=memory=8Gi \
    --kubelet-arg=kube-reserved=memory=1Gi \
    --kubelet-arg=eviction-hard=memory.available<1Gi \
    --kubelet-arg=eviction-minimum-reclaim=memory.available=500Mi
```

**플래그 근거**

| 플래그 | 이유 |
|---|---|
| `--disable traefik` | 기존 nginx가 계속 게이트웨이. 인그레스 컨트롤러 둘이 같은 포트를 노리면 안 된다. Traefik 전환은 3차 과제 |
| `--disable servicelb` | 실수로 만든 `LoadBalancer` Service가 운영 80/443을 잡는 사고를 **구조적으로** 차단 |
| `system-reserved=memory=8Gi` | ★07-28 사고 대응. **kubelet 은 자기 밖의 사용량을 모른다** — docker compose 운영 스택과 Jenkins 가 쓰는 메모리가 kubelet 에겐 보이지 않아, 가만히 두면 "아직 15GB 남았다"고 판단하고 파드를 계속 받는다. 이 서버는 k3s 전용이 아니므로 **compose 스택 몫을 미리 떼어 놓는다** |
| `kube-reserved=memory=1Gi` | k3s 자신(API server·etcd·kubelet·CoreDNS·flannel)의 몫 |
| `eviction-hard=memory.available<1Gi` | 호스트 가용이 1GB 밑으로 가면 kubelet 이 파드를 먼저 축출한다. 커널 OOM 킬러(=호스트가 굳는 경로)까지 가기 전에 k8s 가 스스로 정리하게 하는 마지막 관문 |
| `eviction-minimum-reclaim` | 축출을 찔끔찔끔 반복하지 않고 한 번에 500MB 확보 — 축출 → 다시 임계 → 축출 루프 방지 |

**allocatable 계산** (설치 후 실측으로 확인할 것):

```
allocatable ≈ 15.6GB(capacity) − 8GB(system-reserved) − 1GB(kube-reserved) − 1GB(eviction-hard)
            ≈ 5.6GB   ← k3s 가 파드에 나눠줄 수 있는 총량
```

```bash
# 실측 확인 — 위 계산과 맞는지 본다. 안 맞으면 플래그가 안 먹은 것이다.
kubectl get node -o jsonpath='{.items[0].status.allocatable.memory}{"\n"}'
sudo systemctl show k3s -p ExecStart --value | tr ' ' '\n' | grep kubelet-arg
```

`system-reserved` 값은 **compose 스택이 실제로 쓰는 상한의 합**에서 나온다.
`infra/docker-compose.yml` 의 `mem_limit` 을 바꿨다면 이 값도 함께 재계산할 것
(근거와 예산표: `docs/인프라/메모리-OOM-대응.md`).

**설치 직후 — 메모리 가드 drop-in 배치 (건너뛰지 말 것)**

```bash
sudo mkdir -p /etc/systemd/system/k3s.service.d
sudo cp infra/k3s/k3s.service.d/10-dodam-memory.conf /etc/systemd/system/k3s.service.d/
sudo systemctl daemon-reload && sudo systemctl restart k3s

# 먹었는지 확인 — 값이 안 보이면 적용 안 된 것이다
systemctl show k3s -p MemoryHigh -p MemoryMax -p OOMScoreAdjust
```

이 drop-in 은 k3s 에 부드러운 상한(4G)·하드 상한(6G)을 걸고, **메모리가 마를 때 운영 스택보다
k3s 가 먼저 죽도록**(`OOMScoreAdjust=200`) 우선순위를 조정한다. 근거는 파일 안 주석에 있다.

**`--write-kubeconfig-mode 644`는 쓰지 마세요.** 편하지만 호스트의 모든 사용자가
클러스터를 완전히 제어하게 됩니다. 이 서버에는 **호스트 docker 소켓을 마운트한 Jenkins**가
떠 있어 노출면이 작지 않습니다. 대신 본인 계정으로 복사해서 씁니다:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config
chmod 600 ~/.kube/config
```

---

### 3단계 — 레지스트리 설정 배치 + 기동 확인

```bash
sudo install -D -m 644 -o root -g root \
  infra/k3s/registries.yaml /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s          # 이 재시작이 있어야 반영된다

kubectl get nodes
kubectl get pods -A
```

**기대:** 노드가 `Ready`, `kube-system`의 coredns·metrics-server·local-path-provisioner가 `Running`.
`traefik`·`svclb-*`는 **없어야** 정상입니다(위에서 껐으므로).

`NotReady`면 멈추고 원인부터 봅니다 — 스왑일 수도, 다른 것일 수도 있습니다:

```bash
sudo journalctl -u k3s -n 100 --no-pager
kubectl describe node "$(hostname)" | sed -n '/Conditions/,/Addresses/p'
```

---

### 4단계 — ★ 기존 서비스 e2e 재확인 (통과 못 하면 롤백)

**이 단계가 356의 진짜 완료 조건입니다.** k3s가 뜬 것은 성공이 아닙니다.

**스크립트로 판정** (S15P11B209-358):

```bash
infra/scripts/k3s-baseline.sh capture after
infra/scripts/k3s-baseline.sh compare      # 종료코드 0 = 통과, 1 = 롤백
```

판정 기준(하나라도 어긋나면 실패):
- **서비스 e2e 4종이 0단계와 완전히 동일** ← 이게 틀리면 나머지는 볼 것도 없이 롤백
- 컨테이너 목록·상태 동일 (사라짐·죽음·재시작 전부 검출)
- 사라진 포트 없음 (새로 열린 6443·10250은 정상)
- `DOCKER` 체인 유지 (iptables 스냅샷을 sudo로 받아둔 경우)

<details><summary>수동으로 확인하려면</summary>

```bash
# 0단계와 똑같은 3줄 — 값이 같아야 한다
curl -s -o /dev/null -w 'landing  %{http_code}\n' https://i15b209.p.ssafy.io/
curl -s -o /dev/null -w 'ai       %{http_code}\n' https://i15b209.p.ssafy.io/ai/health
curl -s -o /dev/null -w 'api-401  %{http_code}\n' https://i15b209.p.ssafy.io/api/v1/users/me

# 컨테이너가 하나도 죽지 않았는지 — 출력이 비어야 정상
docker ps --format '{{.Names}}\t{{.Status}}' | sort > /tmp/after-k3s-containers.txt
diff /tmp/before-k3s-containers.txt /tmp/after-k3s-containers.txt

# 컨테이너 → 외부 DNS·HTTPS (flannel이 아웃바운드를 깨지 않았는지)
docker exec dodam-backend sh -c 'getent hosts api.github.com >/dev/null && echo "DNS ok"'

# 컨테이너 → 컨테이너 (앱 내부망이 살아있는지)
# ⚠️ actuator 는 8080 이 아니라 **관리 포트 9404** 에 있다(application.yml `management.server.port`).
#    nginx 가 8080 만 프록시하도록 일부러 분리해 둔 것이라, 8080/actuator/health 는 404 다.
docker exec dodam-nginx sh -c 'wget -q -O- http://backend:9404/actuator/health | head -c 120; echo'

# iptables 변화량 — 늘어난 것 자체는 정상이다. DOCKER 체인이 사라졌는지를 본다
sudo iptables-save > /tmp/after-k3s-iptables.rules
echo "규칙 수: $(wc -l < /tmp/before-k3s-iptables.rules) → $(wc -l < /tmp/after-k3s-iptables.rules)"
diff /tmp/before-k3s-iptables.rules /tmp/after-k3s-iptables.rules | grep '^<' | head -20
```

**판정**

- 3개 curl 값이 0단계와 동일 + `diff`(컨테이너) 무출력 + 내부 통신 정상 → **통과**
- `diff | grep '^<'` 에 `DOCKER` 계열 규칙이 **사라진 것**으로 찍히면 → **위험 신호, 즉시 롤백**
  (규칙이 **추가**된 것은 정상입니다. 없어진 게 문제입니다)
- 하나라도 어긋나면 다음 단계로 가지 말고 **롤백**합니다

</details>

---

### 5단계 — 레지스트리 왕복 확인 (선택이지만 권장)

357로 넘어가기 전에 "Jenkins가 밀어넣은 이미지를 k3s가 실제로 당겨오는가"를 한 번 봅니다.
여기서 안 보면 357에서 매니페스트 문제인지 레지스트리 문제인지 구분하지 못합니다.

```bash
docker pull hello-world
docker tag hello-world 127.0.0.1:5000/hello-world:probe
docker push 127.0.0.1:5000/hello-world:probe

kubectl run k3s-registry-probe --restart=Never \
  --image=127.0.0.1:5000/hello-world:probe
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/k3s-registry-probe --timeout=60s \
  && echo "✅ containerd가 로컬 레지스트리에서 pull 성공"
kubectl logs k3s-registry-probe
kubectl delete pod k3s-registry-probe
```

`ImagePullBackOff`가 나면 `registries.yaml` 배치 또는 3단계의 `systemctl restart k3s`가
빠진 것입니다. `kubectl describe pod k3s-registry-probe`의 Events를 봅니다.

---

## 롤백

4단계를 통과하지 못했다면 **주저 없이 되돌립니다.** 되돌리는 비용보다 서비스가 이상한 채로
남는 비용이 훨씬 큽니다.

```bash
sudo /usr/local/bin/k3s-uninstall.sh     # k3s가 넣은 iptables 규칙도 함께 정리된다

# 서비스 재확인
curl -s -o /dev/null -w 'landing %{http_code}\n' https://i15b209.p.ssafy.io/
docker ps --format '{{.Names}}\t{{.Status}}' | sort | diff /tmp/before-k3s-containers.txt -
```

그래도 컨테이너 네트워크가 이상하면 Docker가 자기 규칙을 다시 깔게 합니다:

```bash
sudo systemctl restart docker
```

> ⚠️ **`docker restart`는 모든 컨테이너를 재시작합니다 = 짧은 서비스 중단.**
> 마지막 수단이며, 팀에 알리고 실행합니다. 재시작 후 백엔드가 healthy가 될 때까지
> nginx가 `Created`에 머무를 수 있습니다(정상 — `depends_on: service_healthy`).

레지스트리만 내리려면:

```bash
docker compose -f infra/jenkins/docker-compose.yml stop registry
```

---

### 6단계 — 축소 스테이징 실배포 (2026-07-29 실측)

`infra/k8s/overlays/staging-min` 을 실제로 올려 **매니페스트가 도는가**를 확인했습니다.
운영 80/443 을 건드리지 않도록 NodePort 30080/30443 을 씁니다.

```bash
infra/scripts/preflight-memory.sh --need 3072      # 통과 못 하면 여기서 멈춘다
infra/scripts/sync-secrets.sh infra/.env --dry-run # 필수 키 게이트
infra/scripts/sync-secrets.sh infra/.env
kubectl apply -k infra/k8s/overlays/staging-min
kubectl -n dodam get pods
```

**결과: 컷오버였다면 운영이 기동조차 못 했을 결함 3건을 잡았습니다.**

| 증상 | 원인 | 조치 |
|---|---|---|
| backend CrashLoopBackOff (OCI `read-only file system`) | FCM 시크릿이 `/run/secrets` 를 읽기전용으로 덮는데 kubelet 이 그 안에 SA 토큰 디렉터리를 만들려 함. compose 엔 SA 토큰이 없어 안 드러남 | `automountServiceAccountToken: false` (backend 는 k8s API 미사용 — 최소권한에도 부합) |
| backend `Failed to configure a DataSource` | **`application-prod.yml` 이 존재하지 않는다.** DataSource·JPA·Flyway 는 `application-local.yml` 에만 있고 운영도 `local` 로 돈다(`infra/.env`) | ConfigMap `SPRING_PROFILES_ACTIVE` → `local`. 📌 prod 프로파일 신설은 BE 별도 과제 |
| gateway CrashLoopBackOff (`cannot load certificate`) | `letsencrypt` PVC 가 빈 새 볼륨 | 아래 인증서 이관 |

#### ★ 인증서 이관 — 360 컷오버의 필수 단계 (sudo 불필요)

`live/*.pem` 은 `../../archive/` 를 가리키는 **상대 심링크**입니다.
**`live/` 만 복사하면 깨진 링크만 남습니다** — `/etc/letsencrypt` 트리를 통째로 옮겨야 합니다.

```bash
# PVC 를 마운트한 임시 파드를 띄운다(gateway 는 죽어 있어 exec 불가)
kubectl -n dodam run cert-mover --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"automountServiceAccountToken":false,"containers":[{"name":"shell","image":"busybox:1.36","command":["sh","-c","sleep 600"],"volumeMounts":[{"name":"letsencrypt","mountPath":"/etc/letsencrypt"}]}],"volumes":[{"name":"letsencrypt","persistentVolumeClaim":{"claimName":"letsencrypt"}}]}}'
kubectl -n dodam wait --for=condition=Ready pod/cert-mover --timeout=90s

# docker exec 는 컨테이너 안에서 root라 호스트 sudo 없이 인증서를 읽는다
docker exec dodam-nginx tar cf - -C /etc letsencrypt \
  | kubectl -n dodam exec -i cert-mover -- tar xf - -C /etc

# ★ 검증은 "파일이 있다"가 아니라 "심링크 역참조가 읽힌다"로 한다
kubectl -n dodam exec cert-mover -- sh -c \
  'wc -c < /etc/letsencrypt/live/i15b209.p.ssafy.io/fullchain.pem'   # 4825 정도면 정상
kubectl -n dodam delete pod cert-mover

kubectl -n dodam rollout restart deployment/gateway
```

> ⚠️ TLS 개인키를 다루는 작업입니다. 값을 출력하지 말고 서버 밖으로 내보내지 마세요(가드레일 9절).

**검증 (2026-07-29 실측):**

```
k8s   :30080 → 301 · :30443 landing 200 · api 401
운영  landing 200 · api 401 · ai 200 · legal 200      ← 무영향
backend actuator UP(9404) · jdbc:mysql://mysql:3306   ← Service 이름 접속 확인(357 목표)
```

> 스왑이 1507→2336MB 로 늘었습니다. 두 스택 동시 가동의 실제 비용이고 360 에서 compose 를
> 내리면 회수됩니다.

---

## 유지 관리 — 레지스트리 디스크

커밋 SHA마다 태그가 쌓입니다. 방치하면 디스크를 채웁니다.

```bash
docker exec dodam-registry du -sh /var/lib/registry          # 사용량
docker exec dodam-registry registry garbage-collect \
  /etc/docker/registry/config.yml                            # 미참조 레이어 회수
```

> 태그 삭제 API는 `REGISTRY_STORAGE_DELETE_ENABLED=true`로 켜 두었지만,
> **삭제 후 garbage-collect를 돌려야 실제 디스크가 회수됩니다.** 태그만 지우고
> 용량이 줄었다고 판단하지 마세요.

---

## 아직 하지 않은 것

이 runbook은 **설치까지**입니다. 아래는 후속 이슈 소관입니다.

- 앱 매니페스트(Deployment/Service/ConfigMap/Secret) — **357** ✅ 작성 완료
- 스테이징 검증(compose와 병행 기동) — **358** ✅ 축소 스테이징 완료(6단계).
  남은 것: ai·mongodb 를 실제로 띄우는 전체 스테이징, backend replicas 2 롤링
- Jenkins `docker compose up` → `kubectl apply` 전환 — **359**
- 80/443 전환(ServiceLB 재활성 또는 nginx→NodePort) — **360**
- Prometheus/Grafana 재배치 — **361**

## 참조

- 레지스트리 설정: `infra/k3s/registries.yaml` · `infra/jenkins/docker-compose.yml`
- 현행 파이프라인: `Jenkinsfile` · `docs/인프라/CICD.md`
- 배포 검증·롤백 절차: `docs/인프라/배포검증-롤백.md`
