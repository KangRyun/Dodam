// ============================================================================
// 응답 판정 헬퍼 (S15P11B209-354)
//
// 왜 따로 두나: k6 의 http_req_failed 는 "200~399 가 아니면 실패"가 기본이다.
// 그런데 401 프로브처럼 **에러가 정답인 요청**이 섞이면 실패율이 부풀어
// `http_req_failed < 1%` 임계값이 근거 없이 깨진다. 그래서 그런 요청에는
// expectedStatuses 를 따로 붙여 "이 상태코드가 정상"이라고 알려준다.
// ============================================================================
import http from 'k6/http';
import { check } from 'k6';

/** 이 상태코드가 나오는 게 정상이라고 k6 에 알리는 요청 옵션. */
export function expecting(status) {
  return { responseCallback: http.expectedStatuses(status) };
}

/** 2xx 계열 성공 판정 + 본문 존재 확인. */
export function checkOk(response, name, expectedStatus = 200) {
  return check(response, {
    [`${name} → ${expectedStatus}`]: (r) => r.status === expectedStatus,
    [`${name} 본문 있음`]: (r) => r.body !== null && r.body.length > 0,
  });
}

/** 프로젝트 공통 응답 봉투(ApiResponse)에서 data 를 꺼낸다. 실패하면 null. */
export function dataOf(response) {
  try {
    const parsed = response.json();
    return parsed && Object.prototype.hasOwnProperty.call(parsed, 'data') ? parsed.data : parsed;
  } catch (_error) {
    return null;
  }
}
