# S15P11B209-307 Access Token 인증 Filter 설계

## 검증 계약

- `/api/v1/*` 요청에 `Authorization` Header가 있으면 `Bearer` Scheme과 JWT를 반드시 검증한다.
- HS256 서명, `iss`, `exp`·`nbf`, `token_type=access`, 숫자형 `sub`를 검증한다.
- `token_type=refresh` Token은 Access 인증 경계에서 거부한다.
- 검증된 `sub`는 `AuthenticatedUser.userId`로 변환해 요청 처리 중에만 `SecurityContext`에 둔다.
- 원본 Token은 Principal, 응답, 로그에 저장하지 않는다. 요청 종료 후 `SecurityContext`를 항상 비운다.
- 잘못된 Token은 HTTP 401과 `AUTH_401_002` 공통 오류 응답으로 차단한다.
- JWT 서버 설정 누락은 임시 Secret으로 대체하지 않고 HTTP 503으로 실패한다.

## 단계적 전환

Filter는 Token이 전달된 요청을 검증하지만 Token이 없는 모든 API를 일괄 차단하지 않는다. Endpoint별 인증 강제와 인증·인가 EntryPoint 통합은 309번에서 적용한다.

아동 조회와 대화 시작은 기존 Resolver가 검증된 `AuthenticatedUser`를 우선 사용하도록 전환했다. `X-Guardian-User-Id` 우회는 `application-test.yml`에서만 켜며 운영 기본 설정은 `false`다. Swagger에는 `bearerAuth` HTTP Bearer JWT Scheme을 제공하고 임시 Header는 공개 명세에서 숨긴다.
