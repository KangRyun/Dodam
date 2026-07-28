// ============================================================================
// 시나리오 ④ 대화(LLM) 경로 스모크 — 1 VU × 1회만 (S15P11B209-354)
//
// ⚠️ 부하를 주지 않는다. 대화는 외부 GMS(Gemini) API 를 호출해 **호출당 과금**되고,
//    남의 쿼터를 태운다. "경로가 살아있나"만 1회 확인하고 끝낸다.
//    반복·VU 를 늘리지 말 것. 기본값을 바꾸는 것 자체가 사고다.
//
// ⚠️ 호출 순서 제약 (S15P11B209-674 에서 확인된 것):
//      세션 생성 → FINAL 스냅샷 → **drawing-complete** → conversations
//    complete 를 건너뛰고 conversations 를 부르면 409 INVALID_STATE_TRANSITION 이다.
//    앱이 지금 이 순서를 어겨서 409 가 나고 있다 — 그래서 이 스모크는 앱 버그와
//    무관하게 "서버 계약대로 부르면 되는가"를 가리는 기준선 역할도 한다.
//
// 실행: k6 run -e BASE_URL=... -e ACCESS_TOKEN=... -e CHILD_IDS=<아동1개> \
//            -e DRAWING_TYPE_ID=1 scenarios/04-conversation-smoke.js
// ============================================================================
import http from 'k6/http';
import { group, sleep } from 'k6';
import { BASE_URL, RUN_TAGS, TIER, authHeaders, childForCurrentVu } from '../lib/config.js';
import { checkOk, dataOf } from '../lib/checks.js';

const DRAWING_PNG = open('../assets/synthetic-drawing.png', 'b');

export const options = {
  vus: 1,
  iterations: 1, // ← 고정. 늘리지 말 것(외부 API 과금).
  thresholds: {
    // 임계값을 두지 않는다 — LLM 응답시간은 우리 스택의 성능 지표가 아니다.
    // 성공 여부만 checks 로 본다.
  },
  tags: { ...RUN_TAGS, kind: 'llm-smoke' },
};

export default function conversationSmoke() {
  const headers = authHeaders();
  const jsonHeaders = { ...headers, 'Content-Type': 'application/json' };
  const childId = childForCurrentVu();
  const now = new Date().toISOString();
  const key = () => `k6-smoke-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;

  let sessionId = null;
  let conversationId = null;

  group('1. 세션 생성', () => {
    const response = http.post(
      `${BASE_URL}/api/v1/drawing-sessions`,
      JSON.stringify({
        childId,
        drawingTypeId: Number(__ENV.DRAWING_TYPE_ID || 1),
        inputMethod: 'CANVAS',
        clientStartedAt: now,
      }),
      { headers: { ...jsonHeaders, 'Idempotency-Key': key() }, tags: { tier: TIER.WRITE } },
    );
    checkOk(response, '세션 생성', 201);
    const body = dataOf(response);
    sessionId = body && body.drawingSessionId;
  });
  if (!sessionId) return;

  group('2. FINAL 스냅샷', () => {
    const response = http.post(
      `${BASE_URL}/api/v1/drawing-sessions/${sessionId}/snapshots`,
      {
        file: http.file(DRAWING_PNG, 'k6-smoke.png', 'image/png'),
        metadata: http.file(
          JSON.stringify({ assetType: 'FINAL', assetVersion: 1, capturedAt: now }),
          'metadata.json',
          'application/json',
        ),
      },
      { headers, tags: { tier: TIER.WRITE } },
    );
    checkOk(response, 'FINAL 업로드', 201);
  });

  group('3. 그림 완료 (대화의 선행 조건)', () => {
    const response = http.post(
      `${BASE_URL}/api/v1/drawing-sessions/${sessionId}/complete`,
      JSON.stringify({ conversationSkipped: false, requestReport: true }),
      { headers: { ...jsonHeaders, 'Idempotency-Key': key() }, tags: { tier: TIER.WRITE } },
    );
    // 이 단계가 실패하면 다음 대화 시작은 반드시 409 다 — 원인을 여기서 못 박아 둔다.
    if (!checkOk(response, '그림 완료', 200) && response.status !== 201) {
      console.error(`complete 실패(${response.status}) — 이후 conversations 409 는 이것의 결과다.`);
    }
  });

  group('4. 대화 시작 (LLM 1회)', () => {
    const response = http.post(
      `${BASE_URL}/api/v1/drawing-sessions/${sessionId}/conversations`,
      JSON.stringify({}),
      { headers: { ...jsonHeaders, 'Idempotency-Key': key() }, tags: { tier: 'llm' } },
    );
    const ok = response.status === 200 || response.status === 201;
    if (!ok) {
      console.error(`대화 시작 실패(${response.status}): ${String(response.body).slice(0, 300)}`);
    }
    const body = dataOf(response);
    conversationId = body && (body.conversationId || body.conversationSessionId);
  });

  if (conversationId) {
    group('5. 대화 종료 (정리)', () => {
      const response = http.post(
        `${BASE_URL}/api/v1/conversations/${conversationId}/end`,
        JSON.stringify({}),
        { headers: jsonHeaders, tags: { tier: 'llm' } },
      );
      if (response.status >= 400) {
        console.warn(`대화 종료 실패(${response.status}) — 합성 대화가 남습니다. cleanup.sql 확인.`);
      }
    });
  }

  sleep(1);
}
