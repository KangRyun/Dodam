# 도담 모니터링 스택 (Prometheus + Grafana) — S15P11B209-352

backend(`:9404 /actuator/prometheus`)·ai(`:8000 /metrics`)·EC2 호스트(node-exporter)·
컨테이너(cAdvisor) 메트릭을 수집(Prometheus)·시각화(Grafana)하는 스택.

> ⚠️ **임시 구성** — k3s 컷오버(2차 MVP Day 6) 때 재배치(Helm/매니페스트) 예정.
> 그때까지의 실용 최소 구성이므로 이 스택에 기능을 과하게 붙이지 말 것.

## 사전 준비 (1회)

`infra/.env` 에 Grafana 관리자 비밀번호 키를 추가한다 (**값은 커밋 금지** — `.env`는 gitignore 등록됨):

```
GRAFANA_ADMIN_PASSWORD=<강한 비밀번호>
```

미설정 시 compose가 fail-fast로 기동을 거부한다(기본 비번 admin/admin 방지 — 의도된 동작).

또한 본 스택(`dodam`)이 먼저 떠 있어야 한다 — backend·ai 스크레이프가
기존 내부망 `dodam_dodam-net`(external)을 통하기 때문.

## 기동 / 중지 (repo 루트에서)

```bash
# 기동
docker compose -f infra/monitoring/docker-compose.yml --env-file infra/.env up -d

# 상태 확인
docker compose -f infra/monitoring/docker-compose.yml ps

# 중지 (볼륨 유지 — 메트릭·대시보드 보존)
docker compose -f infra/monitoring/docker-compose.yml down

# 설정 변경 반영 (prometheus.yml / provisioning 수정 후)
docker compose -f infra/monitoring/docker-compose.yml --env-file infra/.env up -d --force-recreate prometheus grafana
```

## 접속 — SSH 터널 전용

Grafana(3000)·Prometheus(9091)는 **호스트 127.0.0.1에만 바인딩**되어 있다
(가드레일: 외부 노출면은 80/443 유지). 로컬 PC에서 터널을 뚫어 접속한다:

```bash
ssh -L 3000:127.0.0.1:3000 -L 9091:127.0.0.1:9091 <user>@i15b209.p.ssafy.io
```

- Grafana: http://localhost:3000 (admin / `GRAFANA_ADMIN_PASSWORD` 값)
- Prometheus: http://localhost:9091 (Status → Targets 에서 5개 job UP 확인)

호스트 포트가 9090이 아니라 **9091**인 이유: 서버 9090이 이미 점유돼 있음(2026-07-23 실측).

## 대시보드 import (UI에서, 최초 1회)

Prometheus 데이터소스는 provisioning으로 자동 등록돼 있다. 대시보드만 import하면 된다:

1. Grafana 좌측 메뉴 → Dashboards → New → **Import**
2. ID 입력 → Load → 데이터소스 `Prometheus` 선택 → Import
   - **4701** — JVM (Micrometer) : backend 힙·GC·스레드
   - **1860** — Node Exporter Full : EC2 CPU·메모리·디스크·스왑
3. import 결과는 `grafana-data` 볼륨에 저장돼 컨테이너 재생성에도 유지된다.

(선택) JSON 파일을 `infra/monitoring/grafana/dashboards/` 에 두면 1분 내 자동 로드된다.

## 구성 요약

| 서비스 | 이미지(고정) | 호스트 바인딩 | 역할 |
|---|---|---|---|
| prometheus | prom/prometheus:v3.5.0 | 127.0.0.1:9091 | 수집·TSDB(15d 보관, mem 700m) |
| grafana | grafana/grafana:11.6.0 | 127.0.0.1:3000 | 대시보드(mem 256m, 익명 차단) |
| node-exporter | prom/node-exporter:v1.9.1 | 없음 | 호스트 메트릭 |
| cadvisor | gcr.io/cadvisor/cadvisor:v0.51.0 | 없음 | 컨테이너별 메트릭(전부 ro 마운트) |

네트워크: 자체 `monitoring-net` + 기존 `dodam_dodam-net`(external, prometheus만 참여 — 최소권한).
