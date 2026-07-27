# 공통 응답 Envelope·오류 코드 계약 v1

- 상태: 확정
- 기준일: 2026-07-27
- 대상: 공개 REST API `/api/v1/**`
- 관련 Jira: `S15P11B209-526`

## 1. 적용 범위

일반 JSON 성공·오류 응답은 이 문서의 Envelope를 사용한다. 다음 응답은
Envelope 대상이 아니다.

- `204 No Content`
- 그림·음성 등 Binary 스트리밍 응답
- Backend와 AI 서버 사이의 `/internal/**` 계약

HTTP Status와 응답 Body의 `code`는 서로 다른 역할을 가진다. HTTP Status는
전송 결과의 표준 의미를, `code`는 앱이 분기할 안정적인 업무 의미를 나타낸다.

## 2. 성공 응답

필드는 `success`, `code`, `message`, `data` 순서로 직렬화한다.

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {}
}
```

| HTTP Status | 기본 code | 용도 |
| --- | --- | --- |
| `200 OK` | `COMMON_200` | 조회·수정·동기 처리 |
| `201 Created` | `COMMON_201` | 리소스 생성 |
| `202 Accepted` | `COMMON_200` | 비동기 처리 접수 |

`202 Accepted`는 HTTP Status로 비동기 접수임을 표현한다. 현재 별도의 공통
`202` 성공 코드는 추가하지 않는다. `data`가 없는 JSON 성공 응답도
`data: null`을 유지한다.

## 3. 오류 응답

```json
{
  "success": false,
  "code": "COMMON_404_001",
  "message": "요청한 리소스를 찾을 수 없습니다.",
  "data": null
}
```

- `success`는 항상 `false`다.
- `code`는 클라이언트 분기 기준이며 배포 후 임의로 변경하지 않는다.
- `message`는 사용자에게 노출 가능한 안전한 기본 설명이다. 앱의 업무 분기나
  다국어 식별 기준으로 사용하지 않는다.
- `data`는 안전하게 가공된 오류 상세이며 상세가 없으면 `null`이다.

오류 응답에는 Exception 이름, Stack Trace, SQL·Constraint 이름, 저장소
절대 경로, Token, Authorization Header, 아동 개인정보, 입력 원문을 포함하지
않는다.

## 4. Validation 오류

Bean Validation처럼 필드 상세를 제공할 수 있는 경우에만 `data`를 다음
구조로 반환한다.

```json
{
  "success": false,
  "code": "COMMON_400_001",
  "message": "요청 값이 올바르지 않습니다.",
  "data": {
    "fieldErrors": [
      {
        "field": "childName",
        "message": "아동 이름은 필수입니다."
      }
    ],
    "globalErrors": [
      "요청 조합이 올바르지 않습니다."
    ]
  }
}
```

- `fieldErrors`는 `field`, `message`만 포함한다.
- `globalErrors`는 특정 필드에 귀속되지 않는 안전한 메시지 목록이다.
- 두 목록은 오류가 없으면 빈 배열이다.
- 사용자 입력 원문인 `rejectedValue`는 반환하지 않는다.
- 목록은 중복을 제거한 뒤 안정적인 순서로 반환한다.

## 5. 공통 오류 코드

| code | HTTP | 의미 |
| --- | --- | --- |
| `COMMON_400_001` | 400 | 요청 값 또는 Validation 오류 |
| `COMMON_400_002` | 400 | Path·Query 값 타입 변환 오류 |
| `COMMON_400_003` | 400 | JSON Body 읽기·역직렬화 오류 |
| `COMMON_400_004` | 400 | 필수 Query·Multipart Part 누락 |
| `COMMON_404_001` | 404 | API 또는 일반 리소스 없음 |
| `COMMON_405_001` | 405 | 지원하지 않는 HTTP Method |
| `COMMON_409_001` | 409 | 데이터 무결성 조건 충돌 |
| `COMMON_500_001` | 500 | 처리되지 않은 서버 오류 |

인증·권한 오류는 현재 `AUTH_401_006`, `AUTH_403_002`처럼 인증 도메인의
안정적인 코드를 사용한다.

## 6. 도메인 오류 코드 규칙

신규 코드는 가능한 경우 `DOMAIN_HTTP_SEQUENCE` 형식을 사용한다.

```text
DRAWING_404_001
AUTH_401_006
```

이미 공개된 의미 기반 코드(`ACTIVE_CONVERSATION_EXISTS`,
`CONVERSATION_NOT_FOUND` 등)는 클라이언트 호환성을 위해 유지한다. 단,
같은 문자열 code를 여러 Enum에서 재사용하면 HTTP Status와 `message`도
같아야 한다. 업무별로 다른 설명이 필요하면 서로 다른 code를 정의한다.

구조형 코드의 `HTTP` 숫자 구간은 실제 HTTP Status와 일치해야 한다. Enum
상수명은 내부 구현 이름이므로 앱에 전달하지 않는다.

## 7. 클라이언트 처리 규칙

- 성공 데이터는 Envelope의 `data`에서 읽는다.
- 오류 분기는 HTTP Status와 `code`를 사용하고 `message` 문자열을 비교하지
  않는다.
- 알 수 없는 추가 JSON 필드는 무시하되 필수 필드 누락은 계약 오류로 본다.
- `401` 재발급 재시도가 실패하면 동일 요청을 반복하지 않고 로그인 상태를
  정리한다.
- Validation은 `data.fieldErrors[].message`와 `data.globalErrors`를 사용한다.

## 8. 이번 버전에서 제외한 필드

기존 종합 명세 초안에 있던 `timestamp`, `requestId`, 최상위 `errors`는 현재
공개 Envelope에 포함하지 않는다. 요청 추적 ID는 생성·전파·로그 마스킹
정책을 함께 설계해야 하므로 별도 버전 계약에서 추가한다.

이 필드를 추가할 때는 Backend Filter, OpenAPI Schema, Flutter Parser,
운영 로그 검색과 E2E를 같은 변경으로 배포해야 한다.
