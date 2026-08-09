#!/usr/bin/env bash
# Jenkins 배포용 kubeconfig 발급 (S15P11B209-359)
#
# 무엇을 만드나: `jenkins-deployer` ServiceAccount 의 토큰이 담긴 kubeconfig 파일 1개.
#   이걸 Jenkins Credentials(Secret file, id: `dodam-kubeconfig`)로 올리면
#   파이프라인이 그 권한으로만 배포한다.
#
# ⚠️ /etc/rancher/k3s/k3s.yaml 을 그대로 쓰지 말 것.
#   그건 **cluster-admin** 이다. 이 Jenkins 는 호스트 docker.sock 을 쥐고 있어 이미 노출면이
#   큰데, 거기에 클러스터 전권까지 얹으면 Jenkins 장악 = 클러스터 장악이 된다.
#   그래서 네임스페이스 한정 ServiceAccount 토큰으로 별도 발급한다.
#
# ⚠️ k8s 1.24+ 부터 ServiceAccount 를 만들어도 토큰 Secret 이 자동 생성되지 않는다.
#   `kubectl create token` 으로 **수명이 있는** 토큰을 직접 받아야 한다.
#   기본 1시간이라 CI 용으로는 짧다 — 아래에서 명시적으로 늘린다.
#   만료되면 파이프라인이 401 로 죽으므로, 만료일을 캘린더에 적어둘 것.
#
# 사용:
#   infra/scripts/issue-deployer-kubeconfig.sh                    # dodam, 90일
#   NAMESPACE=dodam-staging TTL_HOURS=2160 infra/scripts/issue-deployer-kubeconfig.sh
#
# 출력: ./jenkins-deployer.kubeconfig  (600) — Jenkins 에 올린 뒤 **로컬에서 지울 것**

set -uo pipefail

NAMESPACE="${NAMESPACE:-dodam}"
SA="${SA:-jenkins-deployer}"
TTL_HOURS="${TTL_HOURS:-2160}"          # 90일
OUT="${OUT:-./jenkins-deployer.kubeconfig}"
# 파드에서 접근할 때는 kubernetes.default 지만, Jenkins 는 호스트 네트워크 밖(컨테이너)에서
# 부르므로 노드 IP:6443 을 쓴다. 실제 값은 실행 시 확인해 채운다.
APISERVER="${APISERVER:-}"

die() { printf '\n❌ %s\n' "$*" >&2; exit 1; }
ok()  { printf '   ✅ %s\n' "$*"; }

command -v kubectl >/dev/null 2>&1 || die "kubectl 이 없다 — k3s 설치(356) 후에 실행할 것."

# ── 클러스터에 닿는가 (SA 확인보다 **먼저**) ─────────────────────────────────
# ★ 이 검사를 건너뛰면 "접근 실패"가 "SA 가 없다"로 둔갑한다. 2026-07-29 실제로 겪었다:
#   k3s 가 깐 /usr/local/bin/kubectl 은 KUBECONFIG 가 없으면 **root 전용**
#   /etc/rancher/k3s/k3s.yaml 을 본다. 일반 사용자로 실행하면 권한 오류가 나는데
#   `get serviceaccount ... 2>/dev/null` 이 그걸 삼켜, 멀쩡히 있는 SA 를 없다고 보고했다.
#   원인과 다른 진단을 내놓는 오류 메시지는 없는 것보다 나쁘다.
if ! api_err="$(kubectl get --raw /version 2>&1 >/dev/null)"; then
  die "클러스터에 닿지 않는다 — SA 존재 여부는 아직 알 수 없다.
   원인: ${api_err}
   → 흔한 경우 1: KUBECONFIG 미지정. k3s 의 kubectl 은 root 전용 파일을 기본으로 본다.
        예) KUBECONFIG=~/.kube/config $0
   → 흔한 경우 2: k3s 정지. systemctl is-active k3s 로 확인할 것."
fi

kubectl -n "$NAMESPACE" get serviceaccount "$SA" >/dev/null 2>&1 \
  || die "ServiceAccount ${NAMESPACE}/${SA} 가 없다. (클러스터 접근은 정상이다)
   먼저 매니페스트를 적용할 것: kubectl apply -k infra/k8s/overlays/staging"

# ── API 서버 주소 ────────────────────────────────────────────────────────────
# 현재 kubeconfig 의 server 를 그대로 쓰되, 127.0.0.1 이면 Jenkins 컨테이너에서 닿지 않는다.
#   (컨테이너의 127.0.0.1 은 자기 자신이다 — 이 프로젝트에서 DB_HOST 로 겪은 것과 같은 함정)
if [ -z "$APISERVER" ]; then
  APISERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
fi
case "$APISERVER" in
  *127.0.0.1*|*localhost*)
    NODE_IP="$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
    [ -n "$NODE_IP" ] || die "노드 InternalIP 를 못 찾았다. APISERVER=https://<IP>:6443 로 직접 지정할 것."
    APISERVER="https://${NODE_IP}:6443"
    printf '   ⚠️  API 주소가 루프백이라 노드 IP 로 바꿨다: %s\n' "$APISERVER"
    printf '      (Jenkins 컨테이너의 127.0.0.1 은 자기 자신이라 클러스터에 닿지 않는다)\n'
    ;;
esac

# ── 토큰·CA 발급 ─────────────────────────────────────────────────────────────
TOKEN="$(kubectl -n "$NAMESPACE" create token "$SA" --duration="${TTL_HOURS}h" 2>/dev/null)" \
  || die "토큰 발급 실패. --duration 상한(기본 최대 8760h)을 넘겼거나 권한이 없다."
[ -n "$TOKEN" ] || die "빈 토큰이 발급됐다."

CA_B64="$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
if [ -z "$CA_B64" ]; then
  CA_PATH="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority}')"
  [ -n "$CA_PATH" ] && [ -r "$CA_PATH" ] || die "클러스터 CA 를 못 읽었다(경로: ${CA_PATH:-없음})."
  CA_B64="$(base64 -w0 < "$CA_PATH")"
fi

umask 077
cat > "$OUT" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: dodam
    cluster:
      server: ${APISERVER}
      certificate-authority-data: ${CA_B64}
contexts:
  - name: dodam
    context:
      cluster: dodam
      namespace: ${NAMESPACE}
      user: ${SA}
current-context: dodam
users:
  - name: ${SA}
    user:
      token: ${TOKEN}
EOF
chmod 600 "$OUT"
ok "생성: $OUT (600)"

# ── ★ 검증 — "파일을 만들었다"와 "그 권한으로 실제 되는가"는 다르다 ────────────
printf '\n▸ 발급된 자격으로 실제 동작 확인\n'
if KUBECONFIG="$OUT" kubectl get deployments >/dev/null 2>&1; then
  ok "deployments 조회 성공 (배포에 필요한 권한 확인)"
else
  die "발급은 됐는데 조회가 안 된다 — RoleBinding 이 적용됐는지 확인할 것:
   kubectl -n ${NAMESPACE} get rolebinding jenkins-deployer"
fi

# 넘지 말아야 할 선도 확인한다. 여기서 성공하면 권한이 과하게 열린 것이다.
if KUBECONFIG="$OUT" kubectl get secrets >/dev/null 2>&1; then
  printf '   🔴 Secret 을 읽을 수 있다 — 권한이 과하다. Role 을 확인할 것.\n'
  exit 1
else
  ok "Secret 읽기 차단됨 (의도한 최소권한)"
fi

cat <<EOF

다음:
  1) Jenkins → Manage Jenkins → Credentials → Secret file
     ID: dodam-kubeconfig   File: ${OUT}
  2) 올린 뒤 로컬 파일 삭제:  shred -u ${OUT}   (또는 rm)
  3) 만료: 약 $((TTL_HOURS / 24))일 뒤 — 만료되면 파이프라인이 401 로 죽는다. 캘린더에 적어둘 것.
EOF
