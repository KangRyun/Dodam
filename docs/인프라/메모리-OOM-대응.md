# 호스트 메모리 고갈(OOM) 대응 — 2026-07-28 사고와 방어 체계

> 관련 이슈: S15P11B209-356(k3s 설치) · 358(스테이징 검증) · 623(Android AAB)
> 관련 문서: `docs/인프라/k3s-설치-runbook.md` · `infra/scripts/setup-swap.sh` · `infra/scripts/preflight-memory.sh`

---

## 1. 무슨 일이 있었나

**2026-07-28 저녁, k3s 세팅 중 EC2(i15b209)가 메모리 고갈로 응답 불능이 됐다.**
SSH도 붙지 않아 재부팅으로만 복구했고(21:05 부팅), 진행 중이던 Android AAB 빌드(623)가
gradle 캐시 4.2GB를 남긴 채 중단됐다.

### 왜 "느려짐"이 아니라 "멈춤"이 됐나

리눅스는 메모리가 마르면 곧바로 프로세스를 죽이지 않는다. 먼저 페이지를 회수하려 든다.

```
메모리 여유 감소
  → kswapd 가 회수 시작 (기본 설정은 여유가 거의 없을 때까지 기다린다)
  → 회수 속도 < 소비 속도  →  스왑으로 밀어냄
  → ★ 이 서버의 스왑은 EBS(네트워크 디스크) 위다 — 밀어내는 것 자체가 느리다
  → 회수하려고 IO 대기 → 그 사이 메모리는 더 마름 → 더 회수 시도  = thrash
  → 모든 프로세스가 IO 대기에 갇힘. sshd 도 스케줄되지 못함
  → "죽지도 살지도 않는" 상태. OOM 킬러조차 제때 돌지 못한다
  → 복구 수단 = 재부팅뿐
```

**즉 이 사고는 "메모리가 부족해서"가 아니라 "부족해질 때 죽는 대신 굳도록 설정돼 있어서"
일어났다.** 스왑을 늘리는 것만으로는 재발한다 — 굳기까지 걸리는 시간이 길어질 뿐이다.

### 사고 당시 구성 (원인 3가지)

| # | 상태 | 문제 |
|---|---|---|
| 1 | 스왑 4GB 중 2GB 이미 사용 | 버틸 여유가 없었다 |
| 2 | **컨테이너 메모리 상한이 minio(1g) 하나뿐** | 하나가 폭주하면 호스트 전체를 끌고 간다 |
| 3 | **earlyoom 없음** | 커널이 굳기 전에 개입할 주체가 없었다 |

부수적으로: `/etc/fstab`에 스왑 항목이 **두 줄 중복**돼 있었다(기능상 무해하나 오진 유발).

---

## 2. 방어 체계 — 4겹

한 겹이 뚫려도 다음이 받도록 겹쳐 둔다. **가장 중요한 것은 3번(earlyoom)이다.**

| 겹 | 무엇 | 막는 것 | 적용 방법 |
|---|---|---|---|
| 1 | **컨테이너 상한** | 하나가 호스트 전체를 삼키는 것 | `mem_limit` (compose) · `docker update` (즉시) |
| 2 | **커널 튜닝** | thrash 진입 자체를 늦춤 | `setup-swap.sh` → `/etc/sysctl.d/99-dodam-memory.conf` |
| 3 | **earlyoom** ★ | **호스트가 굳는 것** — 대신 프로세스 하나가 죽는다 | `setup-swap.sh` |
| 4 | **사전 점검 관문** | 위험한 상태에서 무거운 작업을 *시작*하는 것 | `preflight-memory.sh` |

여기에 관측(Prometheus 경보 규칙)과 k3s 전용 가드(kubelet 예약 + systemd drop-in)를 더한다.

### 현재 적용 상태 (2026-07-28 기준)

| 항목 | 상태 |
|---|---|
| 컨테이너 상한 — compose 파일 반영 | ✅ 완료 (backend·mysql·ai·redis·nginx·certbot·jenkins) |
| 컨테이너 상한 — 실행중 컨테이너 즉시 적용 | ✅ 완료 (재시작 없이 `docker update`) |
| Prometheus 메모리 경보 규칙 | ✅ 완료 (6개 규칙 로드 확인) |
| k3s kubelet 예약 플래그 · systemd drop-in | ✅ 문서·파일 준비 완료 (k3s 미설치라 미적용) |
| 사전 점검 스크립트 | ✅ 완료 |
| **스왑 16GB · 커널 튜닝 · earlyoom** | ⚠️ **미적용 — root 필요** (아래 3절) |

---

## 3. ⚠️ 남은 한 가지 — root 권한이 필요한 작업

스왑 확대·커널 파라미터·earlyoom 설치는 **root 권한이 필요하다.** 아래 한 줄이면 끝난다:

```bash
sudo bash infra/scripts/setup-swap.sh
```

하는 일 (멱등 — 여러 번 돌려도 안전하고, 운영 스택이 떠 있는 상태로 돌려도 된다):

1. `/etc/fstab` 스왑 항목 중복 제거 (백업 후)
2. 스왑 **4GB → 16GB**
3. `/etc/sysctl.d/99-dodam-memory.conf` 생성·적용
   - `vm.watermark_scale_factor=200` ← **이번 사고에 가장 직접적인 값.** kswapd가
     여유 2% 지점부터 회수를 시작한다(기본 0.1% — "거의 다 쓸 때까지" 기다린다)
   - `vm.min_free_kbytes=262144` (66MB→256MB) — 예비가 얇으면 원자적 할당 실패가 겹쳐 굳는다
   - `vm.swappiness=20` (10→20) — 차가운 페이지를 미리 내보내 급락 구간을 완만하게
4. **earlyoom 설치·설정·기동** ★
   - 가용 RAM 10% 미만 → SIGTERM, 5% 미만 → SIGKILL
   - `--avoid`: `systemd sshd dockerd containerd mysqld nginx redis-server`
     (sshd를 지키는 이유 = 이번 사고에서 잃은 것이 원격 복구 수단이었다)
   - `--prefer`: `gradle kotlin* dart flutter* k3s* node python3` — 다시 돌리면 그만인 것들
5. **검증** — "설정했다"가 아니라 "동작한다"를 본다 (스왑 실측 · sysctl 실측 · 서비스 active)

> 이 스크립트를 돌리지 않으면 **1·4겹만 적용된 상태**다. 컨테이너 폭주는 막지만,
> 상한 밖(호스트 프로세스·k3s 설치 스크립트·Testcontainers)에서 메모리가 마르면
> 07-28과 같은 경로로 다시 굳는다.

---

## 4. 메모리 예산

RAM **15.6GB** / 스왑 4GB(→16GB 예정) · EBS gp3.

| 대상 | 상한 | 실사용(07-28) | 비고 |
|---|---:|---:|---|
| dodam-backend | 3g *(현재 5g)* | 730MB | JVM — `MaxRAMPercentage=60` 과 짝 |
| dodam-mysql | 2g | 490MB | buffer_pool 기본 128MB |
| dodam-ai | 2g | 83MB | ONNX 추론 피크 기준 |
| dodam-minio | 1g | 300MB | 기존 설정 |
| dodam-redis | 1g | 13MB | maxmemory 미설정 → 상한만 |
| dodam-nginx | 512m | 13MB | |
| dodam-certbot | 256m | 23MB | |
| **운영 소계** | **~9.8g** | **1.65g** | |
| 모니터링 4종 | 1.25g | 275MB | prometheus 700m·grafana/cadvisor 256m·node-exporter 64m |
| **dodam-jenkins** | **6g** | **4,571MB** | ★최대 소비자. `-Xmx2g` 로 컨트롤러 힙도 제한 |
| Testcontainers | (상한 밖) | 330MB × 3~4 | 호스트 도커에 직접 뜬다 |
| 호스트 OS | — | ~1g | |

**상한 총합(17g) > RAM(15.6g)은 의도된 것이다.** 상한은 *예약*이 아니라 *천장*이다.
모두가 동시에 천장을 치는 일은 없고, 그런 순간을 위해 스왑과 earlyoom이 있다.

### backend 만 compose 값(3g)과 실제(5g)가 다른 이유

**JVM은 cgroup 상한을 기동 시점에 한 번만 읽는다.** 지금 도는 backend JVM은 "호스트 RAM
15.6GB"를 기준으로 최대 힙(약 3.9GB)을 이미 정한 뒤 떠 있다. 여기에 3g를 걸면 GC가 힙을
늘리는 순간 컨테이너가 통째로 OOM-kill 된다.

→ 지금은 **폭주만 막고(5g)**, 정식 3g + `MaxRAMPercentage=60`은 **다음 재생성(배포) 때**
자동 적용된다. 서비스를 끊지 않기 위한 의도적 선택이다.

이것이 "메모리 상한을 걸었더니 오히려 더 자주 죽는" 흔한 함정이다 — **JVM 컨테이너에
상한을 걸 때는 힙 비율을 반드시 같이 준다.**

---

## 5. k3s 전용 가드 (356·358 착수 전 필독)

**kubelet은 자기 밖의 사용량을 모른다.** compose 운영 스택과 Jenkins가 쓰는 메모리는
kubelet의 회계에 잡히지 않아, 가만히 두면 "아직 15GB 남았다"고 판단하고 파드를 계속 받는다.
이 서버는 k3s 전용이 아니므로 **compose 몫을 미리 떼어 놔야 한다.**

- 설치 플래그(`system-reserved=8Gi` 등)와 근거 → `docs/인프라/k3s-설치-runbook.md` 2단계
- systemd drop-in → `infra/k3s/k3s.service.d/10-dodam-memory.conf`
  (MemoryHigh 4G / MemoryMax 6G / **OOMScoreAdjust=200** — 메모리가 마르면 운영 스택보다
  k3s가 먼저 죽는다. k3s는 다시 띄우면 되지만 mysqld는 아동 데이터를 쥔 채 죽는다)

착수 전 관문:

```bash
infra/scripts/preflight-memory.sh --need 6144
```

---

## 6. 일상 운영 체크리스트

**무거운 작업(k3s·AAB 빌드·k6 부하테스트) 전:**

```bash
infra/scripts/preflight-memory.sh --need 4096   # 종료코드 1이면 시작하지 않는다
```

**주기적으로 (또는 이상할 때):**

```bash
free -h
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'
# 상한 없는 컨테이너가 새로 생겼는지
docker ps -q | xargs -r docker inspect -f '{{.Name}} {{.HostConfig.Memory}}' | grep ' 0$'
```

Prometheus 경보(SSH 터널 → `http://localhost:9091/alerts`) — `HostMemoryAvailableLow`,
`HostSwapUsageHigh`, `ContainerWithoutMemoryLimit` 등 6개.
⚠️ **Alertmanager가 없어 알림은 나가지 않는다.** 화면을 봐야 보인다.

---

## 7. 다시 굳었을 때

1. **SSH가 되면** — 가장 큰 소비자부터 끊는다. Jenkins가 대개 답이다:
   ```bash
   docker stop dodam-jenkins
   ```
2. **SSH가 안 붙으면** — AWS 콘솔에서 인스턴스 재부팅. 그 전에 콘솔 스크린샷으로
   커널 메시지를 남겨 두면 사후 분석이 된다.
3. **복구 후 반드시 확인** (재부팅은 원인을 지운다):
   ```bash
   journalctl -k -b -1 --no-pager | grep -iE 'oom|killed process'   # 직전 부팅 커널 로그
   docker ps -a --filter status=exited --format '{{.Names}}\t{{.Status}}'
   docker inspect -f '{{.Name}} OOMKilled={{.State.OOMKilled}}' $(docker ps -aq)
   ```
4. 진행 중이던 작업의 잔재를 확인한다 (07-28에는 gradle 캐시 4.2GB와
   `dodam-android-*` 볼륨이 남아 "어디까지 됐는지"를 알려줬다).

---

## 8. 아직 안 한 것

- **Alertmanager + Mattermost 연동** — 규칙은 있으나 알림이 나가지 않는다. k3s 컷오버 이후 과제.
- **zram(압축 스왑)** — EBS 스왑보다 훨씬 빠르다. RAM을 쓰는 대신 IO를 없애는 교환.
  16GB 스왑 + earlyoom으로 충분한지 관찰한 뒤 판단한다(지금 도입은 과투자).
- **Jenkins를 별도 인스턴스로 분리** — 최대 소비자를 운영 서버에서 떼면 이 문제의 상당 부분이
  구조적으로 사라진다. 비용 결정이 필요해 팀 논의 대상.
- **earlyoom 발동 이력의 지표화** — 지금은 syslog에만 남는다.
