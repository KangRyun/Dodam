// ============================================================================
// 시나리오 ② 인증·핵심 조회 (S15P11B209-635 / 354 의 ②)
//
// 무엇을 재나: 보호자가 앱을 켰을 때 실제로 흐르는 읽기 경로.
//   내 정보 → 아동 목록 → 아동 상세 → 활동 이력 → 활동 유형
//   전부 DB 읽기라서 커넥션 풀·인덱스가 병목이면 여기서 먼저 드러난다.
//
// ⚠️ 쓰기가 없다 — 반복 실행해도 데이터가 늘지 않는다. 그래서 이 시나리오는
//    운영 스택에서 돌려도 상대적으로 안전하고, 베이스라인의 주력이다.
//
// 실행: k6 run -e BASE_URL=... -e ACCESS_TOKEN=... -e CHILD_IDS=1,2,3 \
//            scenarios/02-authed-read.js
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

const VUS = Number(__ENV.VUS || 20);

export const options = {
  scenarios: {
    authedRead: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: __ENV.RAMP_UP || '1m', target: VUS },
        { duration: __ENV.HOLD || '5m', target: VUS },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '15s',
    },
  },
  thresholds: thresholdsFor(TIER.READ),
  tags: RUN_TAGS,
};

export function setup() {
  warnIfChildrenAreScarce(VUS);
}

export default function authedRead() {
  const headers = authHeaders();
  const childId = childForCurrentVu();
  const read = (name, path) =>
    http.get(`${BASE_URL}${path}`, { headers, tags: { tier: TIER.READ, name } });

  group('보호자 진입', () => {
    checkOk(read('GET /users/me', '/api/v1/users/me'), '내 정보');
    checkOk(read('GET /children', '/api/v1/children'), '아동 목록');
  });

  group('아동 상세·이력', () => {
    const detail = read('GET /children/{id}', `/api/v1/children/${childId}`);
    checkOk(detail, '아동 상세');
    // reason: 200 이어도 다른 보호자의 아동이 섞여 나오면 인가 사고다. 부하 중에도 확인한다.
    const body = dataOf(detail);
    if (body && body.childId && Number(body.childId) !== Number(childId)) {
      console.error(`인가 이상: 요청한 아동(${childId})과 응답 아동(${body.childId})이 다릅니다`);
    }

    checkOk(
      read('GET /children/{id}/drawing-sessions', `/api/v1/children/${childId}/drawing-sessions?page=0&size=20`),
      '활동 이력',
    );
    checkOk(read('GET /children/{id}/reports', `/api/v1/children/${childId}/reports?page=0&size=20`), '리포트 목록');
  });

  group('공통 메타·알림', () => {
    checkOk(read('GET /drawing-types', '/api/v1/drawing-types'), '활동 유형');
    checkOk(read('GET /notifications', '/api/v1/notifications?page=0&size=20'), '알림함');
  });

  sleep(Number(__ENV.THINK_TIME || 1));
}
