# k6 부하 테스트 (S15P11B209-354 · 635 · 636)

> 목적: **k3s 전환 전/후 성능을 같은 자로 재기 위한 측정 도구.**
> 베이스라인 측정은 355, 전환 후 재측정·무중단 실증은 362가 이 스크립트를 그대로 쓴다.
> 담당: Infra(이강륜)

---

## 🚨 먼저 읽을 것

| 규칙 | 이유 |
|---|---|
| **실아동 데이터 금지** | `sql/seed.sql` 이 만든 `k6-load-*` 합성 계정만 쓴다 (가드레일 9절) |
| **서버 안에서 실행 금지** | 부하 발생기가 측정 대상과 CPU를 나눠 쓰면 숫자가 오염된다. 팀원 노트북 등 **외부 머신**에서 https 도메인을 때린다 (355 지시사항) |
| **팀 합의 시간대에만** | 운영 도메인을 때린다. 사전 공지 없이 돌리면 남의 개발·시연을 망친다 |
| **LLM 경로는 스모크 1회** | 대화는 외부 Gemini API 호출 = 과금. `04-conversation-smoke.js` 의 `iterations: 1` 을 늘리지 말 것 |
| **토큰·`JWT_SECRET` 커밋 금지** | `.gitignore` 로 막아 뒀지만 최종 책임은 사람이다 |
| **끝나면 반드시 정리** | `sql/cleanup.sql` + MinIO 잔여 확인 |
| **`kubectl exec` 에 `-t` 금지** | SQL 을 stdin 으로 밀어 넣는다. `-t`(TTY)를 붙이면 개행이 변환돼 조용히 깨진다. `-i` 만 쓴다 |

---

## ⚠️ 전제가 바뀌었다 (2026-07-30)

이 도구는 원래 **compose 스택의 베이스라인을 재고, k3s 전환 후와 비교**하려고 만들었다(355 → 362).
그런데 **360 컷오버가 2026-07-29 에 끝나 compose 스택은 더 이상 존재하지 않는다.**
따라서 "전환 전" 숫자는 이제 잡을 수 없다. 지금 355 를 돌려서 얻는 것은 **k3s 베이스라인**이고,
그 값은 여전히 쓸모가 있다 — 362(무중단 실증)의 기준선이자 용량 판단의 출발점이다.
**다만 "전환 효과 증명"이라는 원래 목적은 달성 불가**이며, 그렇게 쓰지 말 것.

실행 명령은 전부 k3s 기준으로 고쳐 뒀다(예전 `docker exec dodam-mysql ...` 은 **멈춘 컨테이너**를
가리키고 있었고 DB 이름도 `dodam` 이 아니라 `b209` 다 — 그대로 돌렸으면 실패했다).

**2026-07-30 확인한 것** — 팀 시간을 잡기 전에 미리 검증한 결과다.

| 항목 | 결과 |
|---|---|
| `seed.sql`·`cleanup.sql` 이 쓰는 테이블 10종 | 라이브 스키마에 전부 존재 |
| `users` 컬럼(seed 가 INSERT 하는 것) | 일치 |
| 잔여 `k6-load-%` 합성 데이터 | 0건 |
| `/` · `/legal/privacy/` · `/ai/health` | 200 |
| `/api/v1/children` · `/api/v1/drawing-types` | 401 (인증 필요 — 정상) |

---

## 구성

```
infra/k6/
├── lib/         config.js(BASE_URL·토큰·임계값) · checks.js(응답 판정)
├── scenarios/   01 게이트웨이 · 02 인증조회 · 03 업로드 · 04 대화스모크
├── sql/         seed.sql · cleanup.sql
├── tools/       issue-token.mjs · make-png.mjs
└── assets/      synthetic-drawing.png (생성물, 미커밋)
```

| 시나리오 | 이슈 | 인증 | 쓰기 | 무엇을 재나 |
|---|---|---|---|---|
| `01-gateway.js` | 354 ① | ❌ | ❌ | nginx 정적·`/ai/health`·401 인가 경계 |
| `02-authed-read.js` | **635** | ✅ | ❌ | 보호자 진입 읽기 경로(내 정보→아동→이력→리포트) |
| `03-drawing-upload.js` | **636** | ✅ | ✅ | 세션 생성 + 100KB 그림 업로드 + 삭제 |
| `04-conversation-smoke.js` | 354 ④ | ✅ | ✅ | 대화 경로 생존 확인 **1회만** |

### 응답시간 임계값 (계층별)

```
http_req_failed                     < 1%
http_req_duration{tier:static}  p95 < 150ms   정적·헬스체크
http_req_duration{tier:read}    p95 < 400ms   인증 조회
http_req_duration{tier:write}   p95 < 500ms   생성·업로드
```

하나의 p95로 뭉치지 않은 이유: 느린 업로드가 빠른 정적 파일에 희석되면 회귀를 놓친다.

---

## 실행 절차

### 1단계 — 서버에서 준비 (한 번)

```bash
cd infra/k6

# ① 합성 계정 시드 → guardian_user_id 와 child_ids 가 출력된다
kubectl -n dodam exec -i sts/mysql -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot b209' < sql/seed.sql

# ② 합성 그림 생성 (고정 시드 — 매 실행 동일 바이트)
node tools/make-png.mjs

# ③ 액세스 토큰 발급 (JWT_SECRET 은 서버 밖으로 내보내지 않는다)
JWT_SECRET="$(kubectl -n dodam exec deploy/backend -- printenv JWT_SECRET)" \
  node tools/issue-token.mjs --user-id <guardian_user_id> --ttl-minutes 120
```

③이 출력한 **토큰과 child_ids를 측정용 노트북으로 옮긴다.** `JWT_SECRET` 자체는 옮기지 않는다.
`assets/synthetic-drawing.png` 는 노트북에서 `node tools/make-png.mjs` 로 다시 만들면 같은 파일이 나온다.

> **왜 로그인 API를 안 쓰나** — 소셜 로그인은 카카오·네이버를 실제로 호출한다. 합성 계정에는 소셜 연결이 없고,
> 백엔드가 검증하는 것은 서명·발급자·만료·용도(`token_type=access`)뿐이라 같은 Secret으로 직접 서명하면 통과한다.

### 2단계 — 외부 머신에서 측정

```bash
export BASE_URL=https://i15b209.p.ssafy.io
export ACCESS_TOKEN='<1단계 ③ 출력>'
export CHILD_IDS='<1단계 ① 출력>'
export STACK=k3s            # 결과 태그. compose 는 360 컷오버로 사라졌다(2026-07-29)

# 연결 확인 (토큰 불필요, 30초)
k6 run -e VUS=5 -e HOLD=30s scenarios/01-gateway.js

# 스모크 5VU × 2m
k6 run -e VUS=5 -e RAMP_UP=15s -e HOLD=2m \
       --summary-export=results/smoke-read.json scenarios/02-authed-read.js

# 본 측정 20~30VU × 10m
k6 run -e VUS=30 -e RAMP_UP=1m -e HOLD=10m \
       --summary-export=results/ramp-read.json scenarios/02-authed-read.js
k6 run -e VUS=10 -e RAMP_UP=1m -e HOLD=5m \
       --summary-export=results/ramp-upload.json scenarios/03-drawing-upload.js
```

측정 창 동안 **Grafana에서 서버 CPU·메모리를 같이 캡처**한다 — 응답시간만으로는 여유가 있었는지 알 수 없다.

### 3단계 — 정리 (필수)

```bash
# 서버에서: 지워질 행 수를 먼저 눈으로 확인한 뒤 실행
kubectl -n dodam exec -i sts/mysql -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot b209' < sql/cleanup.sql

# MinIO 잔여 객체 확인 (03 을 돌렸다면)
kubectl -n dodam exec sts/minio -- sh -c 'ls -1 /data/dodam/images | wc -l'
```

발급한 토큰 파일이 있다면 **삭제**한다. 만료(기본 2시간) 전까지는 유효한 자격증명이다.

---

## 설계 근거 — 부딪히기 전에 알아야 할 것

**① 아동 1명 = VU 1명.** 백엔드는 아동당 진행 중 세션을 하나만 허용한다
(`POST /drawing-sessions` → 409). VU들이 아동을 공유하면 1명 빼고 전원이 409를 받아
부하 테스트가 아니라 충돌 테스트가 된다. `seed.sql` 의 `@child_count` ≥ 목표 VU.

**② 업로드는 `INTERMEDIATE` + 버전 증가.** `FINAL` 은 세션당 1개 제약이 있어
반복 부하에 쓰면 두 번째부터 `DRAWING_FINAL_SNAPSHOT_EXISTS` 로 떨어진다.

**③ 반복마다 세션을 지운다.** 안 지우면 다음 반복 생성이 409이고, 합성 세션이 운영 DB에 쌓인다.

**④ metadata 파트는 `http.file()` 로 감싼다.** 그래야 `Content-Type: application/json` 이 붙어
Spring `@RequestPart` 가 역직렬화한다. 평문 문자열로 보내면 415다.

**⑤ 401 프로브에는 `expectedStatuses(401)` 를 붙인다.** k6는 기본적으로 2xx/3xx가 아니면
실패로 세므로, 안 붙이면 이 요청 하나 때문에 `http_req_failed < 1%` 가 근거 없이 깨진다.

**⑥ 대화는 `complete` 다음에 시작한다.** 세션 생성 → FINAL 스냅샷 → `drawing-complete` → `conversations`.
`complete` 를 건너뛰면 409 `INVALID_STATE_TRANSITION` 이다 (S15P11B209-674에서 확인).

---

## 참조

- 베이스라인 측정: **S15P11B209-355** → 산출물 `docs/성능/2026-07-25-k6-baseline.md`
- 전환 후 비교·무중단 실증: **S15P11B209-362** → `docs/성능/2026-07-29-k6-after-k3s.md`
- 계약 근거: `backend/.../auth/token/JwtTokenIssuer.java` · `drawing/service/DrawingSnapshotService.java`
