#!/usr/bin/env bash
# 매니페스트 드리프트 점검 — S15P11B209-751
#
# "git 에 있다 ≠ 클러스터에 있다" 를 잡는다.
#
# ★ 왜 필요한가 (2026-07-30 사고)
#   Jenkins 배포 단계는 `kubectl set image` 만 한다. 배포용 SA 에 생성 권한이 없어
#   **의도적으로** 그렇게 설계돼 있고(Jenkinsfile 288~289행), 워크로드·설정 반영은
#   사람이 `kubectl apply -k` 로 하는 전제다. 그런데 그 수동 단계를 상기시키는 장치가
#   없어서, 365 가 backend.yaml 에 넣은 MONGO_APP_* env 가 클러스터에 영영 닿지 않았다.
#   새 파드는 빈 비밀번호로 뜨려다 설정 바인딩 NPE → CrashLoopBackOff → 배포 실패.
#   구 파드가 계속 서빙해서(maxUnavailable: 0) 장애는 없었고, 그래서 더 조용했다.
#
# ★ 왜 `kubectl diff` 를 쓰지 않는가 (설계상 중요)
#   kubectl diff 는 편하지만 내부적으로 이 요청을 보낸다:
#       PATCH /apis/apps/v1/namespaces/dodam/deployments/backend?dryRun=All
#   쿠버네티스는 **dry-run 요청도 실제 쓰기와 동일하게 인가**한다. 따라서 diff 를 쓰려면
#   오버레이에 담긴 모든 종류에 patch 권한이 필요하고, 거기에는 ClusterRole·
#   ClusterRoleBinding 도 포함된다. ClusterRole 을 patch 할 수 있는 잡은 **스스로에게
#   cluster-admin 을 줄 수 있다.** 감시용 크론잡에 줄 권한이 아니다.
#   → 렌더는 로컬에서(`kubectl kustomize`, 클러스터 접근 없음), 클러스터는 `get` 만 한다.
#
# ★ 비교 방식: 동등이 아니라 **포함**이다
#   "매니페스트가 선언한 필드가 라이브에 그대로 있는가" 만 본다.
#   라이브에만 있는 필드(API 서버가 채우는 기본값 — dnsPolicy·terminationMessagePath 등)는
#   애초에 선언된 적이 없으므로 비교 대상이 아니다. 이래서 서버 사이드 병합 없이도
#   기본값 오탐이 생기지 않는다. diff 를 포기하면서 잃는 게 없는 이유다.
#
# 종료 코드
#   0  드리프트 없음
#   1  드리프트 있음  ← Job 실패로 남고 Prometheus/Alertmanager 가 알린다
#   2  점검 자체가 실패(권한·연결·렌더 오류). 1 과 반드시 구분한다 —
#      "못 봤다" 를 "깨끗하다" 로 읽으면 게이트가 없느니만 못하다.
set -uo pipefail

OVERLAY="${OVERLAY:-infra/k8s/overlays/prod}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

hr() { printf '─%.0s' $(seq 1 72); echo; }
hr; echo "매니페스트 드리프트 점검 — ${OVERLAY}"; hr

# ── 1) 렌더 (클러스터 접근 없음) ─────────────────────────────────────────
if ! kubectl kustomize "${OVERLAY}" >"${WORK}/rendered.yaml" 2>"${WORK}/err.txt"; then
  echo "✗ 점검 실패 — 렌더 오류"; sed 's/^/    /' "${WORK}/err.txt" | head -10; exit 2
fi
[ -s "${WORK}/rendered.yaml" ] || { echo "✗ 점검 실패 — 렌더 결과가 비었다"; exit 2; }

# ── 2) 라이브 조회 (get 만) ──────────────────────────────────────────────
# --ignore-not-found: 없는 리소스는 오류가 아니라 **드리프트**다(아래에서 따로 보고).
if ! kubectl get -f "${WORK}/rendered.yaml" -o json --ignore-not-found \
      >"${WORK}/live.json" 2>"${WORK}/err.txt"; then
  echo "✗ 점검 실패 — 라이브 조회 오류"; sed 's/^/    /' "${WORK}/err.txt" | head -10; exit 2
fi
if grep -qE 'is forbidden|Unable to connect|refused' "${WORK}/err.txt"; then
  echo "✗ 점검 실패 — 권한 또는 연결 문제"; sed 's/^/    /' "${WORK}/err.txt" | head -10; exit 2
fi

# 렌더 결과(YAML)를 JSON 으로 바꾼다. yq 를 쓰지 않는 이유는 의존성을 하나라도 줄이기
# 위해서다 — 이 스크립트는 컨테이너(alpine/k8s)와 개발자 노트북 양쪽에서 돌아야 한다.
# `--dry-run=client` 는 **클러스터에 아무것도 보내지 않는다**(client 이므로).
# 출력은 List 가 아니라 JSON 문서가 연달아 나오는 형태다 — 파서 쪽에서 스트림으로 읽는다.
if ! kubectl create -f "${WORK}/rendered.yaml" --dry-run=client -o json --validate=false \
      >"${WORK}/want.json" 2>"${WORK}/err.txt"; then
  echo "✗ 점검 실패 — 렌더 결과 변환 오류"; sed 's/^/    /' "${WORK}/err.txt" | head -5; exit 2
fi

# ── 3) 비교 ─────────────────────────────────────────────────────────────
python3 - "${WORK}/want.json" "${WORK}/live.json" <<'PY'
import json, re, sys

def load_stream(path):
    """JSON 문서가 연달아 붙어 나오는 출력을 읽는다(kubectl 의 -o json 다중 리소스 형태).
       단일 List 로 오는 경우(kubectl get)도 같이 처리한다."""
    txt = open(path).read().strip()
    if not txt:
        return []
    dec, out, i = json.JSONDecoder(), [], 0
    while i < len(txt):
        obj, end = dec.raw_decode(txt, i)
        out.append(obj)
        i = end
        while i < len(txt) and txt[i] in " \t\r\n":
            i += 1
    flat = []
    for o in out:
        if isinstance(o, dict) and o.get("kind") == "List":
            flat.extend(o.get("items", []))
        else:
            flat.append(o)
    return flat

want = load_stream(sys.argv[1])
live_items = load_stream(sys.argv[2])

def ident(o):
    m = o.get("metadata", {})
    return (o.get("apiVersion", ""), o.get("kind", ""), m.get("namespace", ""), m.get("name", ""))

live_by = {ident(o): o for o in live_items if isinstance(o, dict) and o.get("kind")}

# 무시할 것 —
#   image        : Jenkins 가 SHA 태그로 `set image` 한다. 매니페스트의 :prod 와 항상 다르고,
#                  이게 정상이다. 안 거르면 매 실행마다 울려서 곧 아무도 안 본다.
#   메타데이터    : 서버가 관리하는 값. creationTimestamp 는 kustomize 가 null 로 뱉는데
#                  라이브엔 없거나 실제 시각이라 반드시 걸러야 한다.
IGNORE_KEYS = {"image", "generation", "resourceVersion", "uid", "creationTimestamp",
               "managedFields", "selfLink", "status"}
IGNORE_ANN = {"kubectl.kubernetes.io/last-applied-configuration",
              "deployment.kubernetes.io/revision"}

def key_of(e, k):
    return (e.get("metadata") or {}).get("name") if k == "metadata.name" else e.get(k)

def merge_key(lst):
    """리스트를 순서 무시로 비교하기 위한 키. 쿠버네티스의 patch merge key 를 따른다.
       env 가 대표적이다 — `kubectl set env` 는 목록 끝에 붙이고 매니페스트는 중간에 두는데,
       내용이 같으면 차이가 아니다(2026-07-30 응급 조치로 넣은 MONGO env 3종이 그 경우).

       ⚠️ **고유한 키만 쓴다.** grafana 는 volumeMounts 두 개가 이름이 똑같이
       `provisioning` 이고 mountPath 만 다르다. `name` 을 먼저 본다는 이유로 집어들면
       두 항목이 한 칸에 겹쳐 엉뚱한 불일치가 난다(설계 중 실제로 겪음).
       volumeClaimTemplates 처럼 이름이 metadata 안에 있는 경우도 있어 마지막에 본다."""
    ds = [e for e in lst if isinstance(e, dict)]
    if not ds or len(ds) != len(lst):
        return None
    for k in ("name", "mountPath", "containerPort", "key", "topologyKey", "metadata.name"):
        vals = [key_of(e, k) for e in ds]
        if all(v is not None for v in vals) and len({str(v) for v in vals}) == len(vals):
            return k
    return None

_SUFFIX = {"m": 1e-3, "": 1, "k": 1e3, "M": 1e6, "G": 1e9, "T": 1e12, "P": 1e15, "E": 1e18,
           "Ki": 2**10, "Mi": 2**20, "Gi": 2**30, "Ti": 2**40, "Pi": 2**50, "Ei": 2**60}

def quantity(v):
    """쿠버네티스 수량 표기를 숫자로. `1000m` 과 `1` 은 같은 값인데 문자열로는 다르다 —
       API 서버가 정규화해 저장하므로 그대로 비교하면 영원히 불일치로 뜬다."""
    m = re.fullmatch(r"(\d+(?:\.\d+)?)([a-zA-Z]*)", str(v))
    if not m or m.group(2) not in _SUFFIX:
        return None
    return float(m.group(1)) * _SUFFIX[m.group(2)]

def diffs(w, l, path=""):
    if isinstance(w, dict):
        if not isinstance(l, dict):
            yield (path, "타입 불일치", None); return
        for k, v in w.items():
            if k in IGNORE_KEYS:
                continue
            p = f"{path}.{k}"
            if k == "annotations" and isinstance(v, dict):
                v = {a: b for a, b in v.items() if a not in IGNORE_ANN}
                if not v:
                    continue
            if k not in l:
                yield (p, v, None); continue
            yield from diffs(v, l[k], p)
    elif isinstance(w, list):
        if not isinstance(l, list):
            yield (path, "타입 불일치", None); return
        mk = merge_key(w)
        if mk:
            lm = {str(key_of(e, mk)): e for e in l if isinstance(e, dict) and key_of(e, mk) is not None}
            for e in w:
                kv = str(key_of(e, mk))
                p = f"{path}[{kv}]"
                if kv not in lm:
                    yield (p, e, None); continue
                yield from diffs(e, lm[kv], p)
        else:
            for e in w:
                if e not in l:
                    yield (f"{path}[]", e, None)
    else:
        if w == l:
            return
        qw, ql = quantity(w), quantity(l)
        if qw is not None and ql is not None and qw == ql:
            return                      # `1000m` == `1` — 표기만 다르다
        yield (path, w, l)

def brief(v, n=70):
    s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False, sort_keys=True)
    return s if len(s) <= n else s[:n] + "…"

missing, changed, total = [], [], 0
for w in want:
    if not isinstance(w, dict) or not w.get("kind"):
        continue
    i = ident(w)
    label = f"{w['kind']}/{i[3]}" + (f" (ns={i[2]})" if i[2] else "")
    if i not in live_by:
        missing.append(label); continue
    ds = list(diffs(w, live_by[i]))
    if ds:
        changed.append((label, ds)); total += len(ds)

if not missing and not changed:
    print("✅ 드리프트 없음 — 매니페스트가 선언한 것이 클러스터에 모두 반영돼 있다")
    sys.exit(0)

print("★ 반영되지 않은 매니페스트 변경이 있다\n")
for m in missing:
    print(f"  {m}\n      리소스 자체가 클러스터에 없다 — 한 번도 apply 되지 않았다")
for label, ds in changed:
    print(f"  {label}")
    for p, w, l in ds[:8]:
        if l is None:
            print(f"      {p}  ← 없음 (매니페스트: {brief(w)})")
        else:
            print(f"      {p}  라이브={brief(l, 34)}  매니페스트={brief(w, 34)}")
    if len(ds) > 8:
        print(f"      … 외 {len(ds) - 8}건")
print(f"\n  합계: 누락 리소스 {len(missing)}개 · 불일치 필드 {total}개")
sys.exit(1)
PY
RC=$?

if [ "${RC}" -eq 1 ]; then
  echo
  hr
  cat <<'GUIDE'
반영 방법 — ⚠️ `kubectl apply -k overlays/prod` 를 통째로 돌리지 말 것.
  이미지 태그가 :prod 로 되돌아가 방금 배포한 빌드가 사라진다(Jenkinsfile 297행).

  ConfigMap  : kubectl -n dodam patch cm <name> --type merge -p '{"data":{...}}'
               (base 통째 apply 도 금지 — prod overlay 의 AI_*_MODE=http 가 mock 으로 회귀)
  Deployment : kubectl -n dodam set env deployment/<name> --from=secret/dodam-secrets --keys=...
               또는 필요한 필드만 kubectl patch
  새 리소스   : kubectl apply -f <해당 파일 하나만>

  자세한 절차는 infra/k8s/README.md 참조.
GUIDE
fi
exit "${RC}"
