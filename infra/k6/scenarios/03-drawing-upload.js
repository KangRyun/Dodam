// ============================================================================
// 시나리오 ③ 세션 생성 + 합성 그림 업로드 (S15P11B209-636 / 354 의 ③)
//
// 무엇을 재나: 쓰기 경로 전체 — MySQL 쓰기 + MinIO 오브젝트 저장 + 트랜잭션 보상.
//   반복 1회 = 세션 생성 → 스냅샷 업로드 → 세션 삭제.
//
// ⚠️ 마지막 삭제가 선택이 아니라 필수다.
//    백엔드는 **아동당 진행 중 세션 1개**만 허용해서, 지우지 않으면 다음 반복의
//    생성이 전부 409 로 떨어지고 측정값이 무의미해진다.
//    (또한 지우지 않으면 합성 세션이 운영 DB 에 쌓인다.)
//
// ⚠️ 이 시나리오는 실제로 파일을 쓴다. 운영 스택에 돌릴 때는 반드시
//    sql/cleanup.sql 로 뒷정리하고, MinIO 잔여 객체도 README 절차로 확인한다.
//
// 실행: k6 run -e BASE_URL=... -e ACCESS_TOKEN=... -e CHILD_IDS=1,2,3 \
//            scenarios/03-drawing-upload.js
// ============================================================================
import http from 'k6/http';
import { group, sleep } from 'k6';
import {
  BASE_URL,
  RUN_TAGS,
  TIER,
  authHeaders,
  childForCurrentVu,
  thresholdsFor,
  warnIfChildrenAreScarce,
} from '../lib/config.js';
import { checkOk, dataOf } from '../lib/checks.js';

const VUS = Number(__ENV.VUS || 10);

// 합성 이미지. tools/make-png.mjs 로 생성한다(고정 시드 → 매 실행 동일 바이트).
// reason: 초기화 컨텍스트에서 한 번만 읽어 VU 전원이 공유한다. VU 안에서 읽으면
//         VU 수만큼 메모리를 먹는다.
const DRAWING_PNG = open('../assets/synthetic-drawing.png', 'b');

export const options = {
  scenarios: {
    drawingUpload: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: __ENV.RAMP_UP || '1m', target: VUS },
        { duration: __ENV.HOLD || '3m', target: VUS },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: thresholdsFor(TIER.WRITE),
  tags: RUN_TAGS,
};

export function setup() {
  warnIfChildrenAreScarce(VUS);
  // 활동 유형은 시드 데이터(V12)라 고정이다. 첫 항목을 쓰되 환경변수로 덮을 수 있게 둔다.
  if (__ENV.DRAWING_TYPE_ID) {
    return { drawingTypeId: Number(__ENV.DRAWING_TYPE_ID) };
  }
  const types = http.get(`${BASE_URL}/api/v1/drawing-types`, { headers: authHeaders() });
  const body = dataOf(types);
  const list = Array.isArray(body) ? body : body && body.drawingTypes;
  if (!list || list.length === 0) {
    throw new Error('활동 유형을 가져오지 못했습니다. ACCESS_TOKEN 을 확인하세요.');
  }
  return { drawingTypeId: list[0].drawingTypeId || list[0].id };
}

export default function drawingUpload(setupData) {
  const headers = authHeaders();
  const childId = childForCurrentVu();
  const now = new Date().toISOString();
  let sessionId = null;

  group('세션 생성', () => {
    const response = http.post(
      `${BASE_URL}/api/v1/drawing-sessions`,
      JSON.stringify({
        childId,
        drawingTypeId: setupData.drawingTypeId,
        inputMethod: 'CANVAS',
        clientStartedAt: now,
      }),
      {
        headers: { ...headers, 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey() },
        tags: { tier: TIER.WRITE, name: 'POST /drawing-sessions' },
      },
    );
    if (!checkOk(response, '세션 생성', 201)) {
      // 409 라면 앞선 반복이 세션을 남긴 것이다 — VU 대비 아동 수를 먼저 의심한다.
      if (response.status === 409) {
        console.warn(`아동 ${childId} 에 진행 중 세션이 남아 있습니다(409). 삭제 단계 실패 여부를 확인하세요.`);
      }
      return;
    }
    const body = dataOf(response);
    sessionId = body && body.drawingSessionId;
  });

  if (!sessionId) {
    sleep(1);
    return;
  }

  group('스냅샷 업로드', () => {
    // metadata 를 http.file 로 감싸는 게 핵심 — 그래야 파트에 Content-Type: application/json 이
    // 붙고 Spring 의 @RequestPart 가 JSON 으로 역직렬화한다. 평문 문자열로 보내면 415 가 난다.
    //
    // assetType 은 INTERMEDIATE + 버전 증가로 간다. FINAL 은 세션당 1개 제약이 있어
    // 반복 부하에 쓰면 두 번째부터 DRAWING_FINAL_SNAPSHOT_EXISTS 로 떨어진다.
    const response = http.post(
      `${BASE_URL}/api/v1/drawing-sessions/${sessionId}/snapshots`,
      {
        file: http.file(DRAWING_PNG, 'k6-synthetic-drawing.png', 'image/png'),
        metadata: http.file(
          JSON.stringify({ assetType: 'INTERMEDIATE', assetVersion: __ITER + 1, capturedAt: now }),
          'metadata.json',
          'application/json',
        ),
      },
      { headers, tags: { tier: TIER.WRITE, name: 'POST /drawing-sessions/{id}/snapshots' } },
    );
    checkOk(response, '스냅샷 업로드', 201);
  });

  group('세션 정리', () => {
    // 실패하면 아동이 계속 점유돼 다음 반복이 409 가 된다 — 조용히 넘기지 않는다.
    const response = http.del(
      `${BASE_URL}/api/v1/drawing-sessions/${sessionId}`,
      JSON.stringify({ confirmation: 'DELETE' }),
      {
        headers: { ...headers, 'Content-Type': 'application/json' },
        tags: { tier: TIER.WRITE, name: 'DELETE /drawing-sessions/{id}' },
      },
    );
    if (response.status !== 204) {
      console.error(`세션 ${sessionId} 삭제 실패(${response.status}) — 합성 데이터가 남습니다. cleanup.sql 필수.`);
    }
  });

  sleep(Number(__ENV.THINK_TIME || 1));
}

function idempotencyKey() {
  return `k6-${RUN_TAGS.stack}-${__VU}-${__ITER}-${Date.now()}`;
}
