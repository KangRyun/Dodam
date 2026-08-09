// ============================================================================
// k6 공통 설정 — 시나리오 3종이 모두 여기서 BASE_URL·토큰·임계값을 가져온다.
//   (S15P11B209-354)
//
// ⚠️ 실아동 데이터 사용 금지(가드레일 9절). 이 디렉토리의 모든 시나리오는
//    sql/seed.sql 로 만든 합성 계정만 사용하고, 끝나면 sql/cleanup.sql 로 지운다.
// ============================================================================

/** 타격 대상. 기본값은 없다 — 실수로 운영을 때리는 걸 막기 위해 명시를 강제한다. */
export const BASE_URL = (() => {
  const raw = __ENV.BASE_URL;
  if (!raw) {
    throw new Error('BASE_URL 을 지정하세요. 예) -e BASE_URL=https://i15b209.p.ssafy.io');
  }
  return raw.replace(/\/+$/, '');
})();

/**
 * 합성 보호자의 Access Token. tools/issue-token.mjs 로 서버에서 오프라인 발급한다.
 * reason: 로그인 API를 부하 경로에 넣으면 카카오·네이버 등 외부 IdP 를 때리게 된다.
 */
export const ACCESS_TOKEN = __ENV.ACCESS_TOKEN || '';

/**
 * 합성 아동 ID 목록(쉼표 구분). VU 하나가 아동 하나를 전담한다.
 *
 * ⚠️ 이 분배가 핵심이다. 백엔드는 **아동당 진행 중 세션을 1개만** 허용해서
 *    (POST /api/v1/drawing-sessions → 409), 여러 VU 가 같은 아동을 쓰면
 *    1명을 뺀 전원이 409 를 받고 부하 테스트가 아니라 충돌 테스트가 된다.
 */
export const CHILD_IDS = (__ENV.CHILD_IDS || '')
  .split(',')
  .map((value) => value.trim())
  .filter((value) => value.length > 0)
  .map(Number);

/** 이번 VU 가 전담할 아동. VU 번호는 1부터 시작한다. */
export function childForCurrentVu() {
  if (CHILD_IDS.length === 0) {
    throw new Error('CHILD_IDS 가 비었습니다. sql/seed.sql 실행 후 README 의 조회 쿼리로 채우세요.');
  }
  return CHILD_IDS[(__VU - 1) % CHILD_IDS.length];
}

/** 시드한 아동 수보다 VU 가 많으면 아동을 공유하게 되어 409 가 터진다 — 먼저 경고한다. */
export function warnIfChildrenAreScarce(vus) {
  if (vus > CHILD_IDS.length) {
    console.warn(
      `⚠️ VU(${vus}) > 합성 아동(${CHILD_IDS.length}) — 아동이 겹쳐 409(진행 중 세션 충돌)가 납니다. ` +
        'sql/seed.sql 의 @child_count 를 늘려 다시 시드하세요.',
    );
  }
}

export function authHeaders() {
  if (!ACCESS_TOKEN) {
    throw new Error('ACCESS_TOKEN 이 없습니다. tools/issue-token.mjs 로 발급하세요.');
  }
  return { Authorization: `Bearer ${ACCESS_TOKEN}`, Accept: 'application/json' };
}

// ── 응답시간 임계값 계층 ─────────────────────────────────────────────────────
// 하나의 p95 로 뭉뚱그리면 "느린 업로드"가 "빠른 정적 파일"에 희석돼 회귀를 놓친다.
// 요청마다 tags.tier 를 붙이고 계층별로 임계값을 건다.
export const TIER = {
  STATIC: 'static', // 정적 파일·헬스체크 — 앱 로직 없음
  READ: 'read', // 인증 조회 — DB 읽기
  WRITE: 'write', // 생성·업로드 — DB 쓰기 + 오브젝트 스토리지
};

/** 세 계층 공통 임계값. 개별 시나리오는 자기가 쓰는 계층만 골라 쓴다. */
export const THRESHOLDS = {
  http_req_failed: ['rate<0.01'],
  [`http_req_duration{tier:${TIER.STATIC}}`]: ['p(95)<150'],
  [`http_req_duration{tier:${TIER.READ}}`]: ['p(95)<400'],
  [`http_req_duration{tier:${TIER.WRITE}}`]: ['p(95)<500'],
};

/** 임계값 중 이번 시나리오가 실제로 측정하는 계층만 남긴다(빈 계층은 k6 가 0건으로 통과시킨다). */
export function thresholdsFor(...tiers) {
  const picked = { http_req_failed: THRESHOLDS.http_req_failed };
  for (const tier of tiers) {
    const key = `http_req_duration{tier:${tier}}`;
    picked[key] = THRESHOLDS[key];
  }
  return picked;
}

/** 모든 실행에 붙는 태그 — 결과 JSON 에서 전/후 비교(362)를 구분하는 축이다. */
export const RUN_TAGS = {
  stack: __ENV.STACK || 'k3s', // 결과 태그. compose 는 360 컷오버로 사라졌다(2026-07-29)
  issue: __ENV.ISSUE || 'S15P11B209-355',
};
