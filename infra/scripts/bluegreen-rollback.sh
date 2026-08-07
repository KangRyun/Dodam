#!/usr/bin/env bash
# 도담 — 블루-그린 롤백(직전 색으로 되돌림). bluegreen-deploy.sh --rollback 의 얇은 래퍼.
#   사용법: infra/scripts/bluegreen-rollback.sh <backend|ai|web>
#   동작:   해당 서비스를 직전 색(반대 색)이 마지막에 돌던 태그로 다시 띄우고 스위치를 되돌린다.
#           엔진·롤백 로직은 전부 bluegreen-deploy.sh 에 있다(단일 구현).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/bluegreen-deploy.sh" --rollback "$@"
