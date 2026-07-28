// ============================================================================
// 시나리오 ① 게이트웨이·정적·AI 헬스·인가 경계 (S15P11B209-354)
//
// 무엇을 재나: nginx 가 앞단에서 얼마나 버티는지 + 뒤쪽 서비스가 살아있는지.
//   - 인증이 필요 없어서 **토큰·시드 없이 단독 실행**할 수 있다. 연결 확인용 1번 타자.
//   - 401 프로브는 "인가가 실제로 막고 있나"를 부하 중에도 확인한다.
//     보안 경계는 한가할 때만 지켜져선 안 된다.
//
// 실행: k6 run -e BASE_URL=https://... scenarios/01-gateway.js
// ============================================================================
import http from 'k6/http';
import { group, sleep } from 'k6';
import { BASE_URL, RUN_TAGS, TIER, thresholdsFor } from '../lib/config.js';
import { checkOk, expecting } from '../lib/checks.js';

export const options = {
  scenarios: {
    gateway: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: __ENV.RAMP_UP || '30s', target: Number(__ENV.VUS || 10) },
        { duration: __ENV.HOLD || '2m', target: Number(__ENV.VUS || 10) },
        { duration: '15s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: thresholdsFor(TIER.STATIC),
  tags: RUN_TAGS,
};

export default function gateway() {
  group('정적 자원', () => {
    const landing = http.get(`${BASE_URL}/`, { tags: { tier: TIER.STATIC, name: 'GET /' } });
    checkOk(landing, '랜딩');

    // 628 로 올린 약관 페이지. 정적 경로가 살아있는지 겸사겸사 확인한다.
    const privacy = http.get(`${BASE_URL}/legal/privacy/`, {
      tags: { tier: TIER.STATIC, name: 'GET /legal/privacy/' },
    });
    checkOk(privacy, '개인정보처리방침');
  });

  group('AI 서비스 헬스', () => {
    // nginx 의 location /ai/ 는 proxy_pass 끝 '/' 로 접두를 떼고 ai:8000/health 로 보낸다.
    const health = http.get(`${BASE_URL}/ai/health`, {
      tags: { tier: TIER.STATIC, name: 'GET /ai/health' },
    });
    checkOk(health, 'AI health');
  });

  group('인가 경계', () => {
    // 토큰 없이 보호 경로 → 401 이 "정상"이다. expecting() 으로 알려주지 않으면
    // 이 요청 하나 때문에 http_req_failed 가 치솟아 임계값이 헛되이 깨진다.
    const unauthorized = http.get(`${BASE_URL}/api/v1/children`, {
      tags: { tier: TIER.STATIC, name: 'GET /api/v1/children (무토큰)' },
      ...expecting(401),
    });
    checkOk(unauthorized, '무토큰 차단', 401);
  });

  sleep(1);
}
