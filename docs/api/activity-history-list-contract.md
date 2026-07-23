# 보호자 활동 기록 목록 조회 계약서 (HISTORY-01 / S15P11B209-154, S15P11B209-292)

- 상태: 구현 기준 계약 (draft)
- 작성: 2026-07-24
- 기준: `API_명세서_최종.md` §14 활동 기록(HISTORY-01 §14.1/§14.2) + `erd-cloud-schema-v1.2.sql` + develop 코드(151/153 읽기 프로젝션 관례)
- 방침: 충돌 시 ① develop 병합 코드 → ② 최신 문서. Notion 라이브 조회 제외. 미확정은 합리적 기본값+근거.

## 1. 개요
| 항목 | 값 |
| --- | --- |
| 메서드·URI | `GET /api/v1/children/{childId}/drawing-sessions` |
| 권한 | 연결 보호자(GUARDIAN, Bearer). 해당 childId와 보호자 관계 필수 |
| 성공 | 200 OK (페이지네이션 목록) |
| 읽기 전용 | `@Transactional(readOnly=true)`, 읽기 전용 프로젝션(151/153 관례) |

- 활동 기록은 별도 `activities` 테이블이 아니라 **`drawing_sessions` 기준 read model**(§14 서두). 신규 마이그레이션 없음.
- **삭제된 세션 제외**(soft-delete `deleted_at`), 해당 childId 소유만.

## 2. Query 파라미터 (§14.2)
| 필드 | 타입 | 기본 | 검증/설명 |
| --- | --- | --- | --- |
| from, to | date(ISO) | 없음 | 활동 시작일(started_at) 범위. from<=to |
| drawingTypeCode | string | 없음 | 그림 유형 코드 필터 |
| sessionStatus | `DrawingSessionStatus` | 없음 | 상태 필터(enum 밖 값 400) |
| reportStatus | `ReportStatus` | 없음 | 리포트 상태 필터 |
| page, size | int | 0, 20 | size 상한 100, JPA가 처리할 수 없는 offset은 400 |
| sort | string | `startedAt,desc` | **`startedAt`, `completedAt`만 허용**. `필드,방향` 두 요소 형식이며 같은 시각은 ID로 안정 정렬 |

## 3. 응답 (페이지네이션)
기존 공통 페이지 응답 포맷 재사용(다른 목록 API 관례 따름). 목록 항목:
```
{ drawingSessionId, thumbnailUrl, drawingType{code,name}, title, inputMethod, sessionStatus, currentStage, selectedEmotions[], analysisStatus, reportId, reportStatus, startedAt, completedAt }
```
- `drawingType`은 code+name 객체(다른 API 관례와 통일; 단일 문자열이면 develop 관례 따름).

## 4. 필드 → 소스 매핑 (정확한 컬럼은 ERD로 확정)
| 응답 | 소스 |
| --- | --- |
| drawingSessionId/title/inputMethod/sessionStatus/currentStage/startedAt/completedAt | `drawing_sessions` |
| drawingType(code,name) | `drawing_types`(session.drawing_type_id) |
| thumbnailUrl | `drawing_assets`(THUMBNAIL 최신 버전; 없으면 null) |
| selectedEmotions | `drawing_session_emotions`(아동 본인 선택 — AI 추정 아님) |
| analysisStatus | `analyses`(해당 세션 FINAL/최신 분석 상태; 없으면 null) |
| reportId, reportStatus | `reports`(해당 세션 최신 리포트; 없으면 null) |

## 5. N+1 회피 (중요)
- 세션 페이지를 먼저 조회(필터+정렬+페이징) → 그 세션 ID 목록으로 thumbnail/emotions/analysis/report를 **배치 IN 조회** 후 메모리 조립(151 관례). 항목마다 개별 쿼리 금지.

## 6. 안전
- `selectedEmotions`는 아동이 직접 선택한 감정만. **AI 추정 감정(observed_emotion)·위험도·전문가 전용 필드 노출 금지**(목록 항목에 애초에 없음 — 구조적 비노출).
- 민감정보 로그 미기록.

## 7. 결정 로그 / 기본값
- **d1 (권한):** child→보호자 관계 검증(`GuardianResourceAccessRepository`/child access 재사용). 관계 없으면 403. child 없음 404.
- **d2 (정렬 화이트리스트):** sort 필드는 startedAt/completedAt만. 그 외/형식 오류 400(임의 컬럼 정렬 금지 — 인젝션·성능 방어). NULL은 뒤로 보내고 동일 시각은 ID를 보조 키로 사용한다.
- **d3 (analysis/report 다중건):** 세션당 최신 1건 기준(report는 createdAt·ID 역순, analysisStatus는 최신 FINAL). 규칙은 153/152 관례 참고.
- **d4 (thumbnailUrl):** 서명 URL 규칙이 별도 있으면 재사용, 없으면 asset 저장 URL/키, 그래도 없으면 null.
- **d5 (빈 결과):** 필터 결과 없음은 빈 페이지(200), 오류 아님.

## 8. 에러
| HTTP | code | 조건 |
| --- | --- | --- |
| 400 | INVALID_INPUT_VALUE | from>to, sort 미허용, enum 밖 값, size 범위 초과 |
| 401 | AUTH_UNAUTHORIZED | 토큰 없음/만료 |
| 404 | CHILD_NOT_FOUND | 아동 없음/비활성 **또는 보호자-아동 관계 없음** |
- **as-built(구현 확정):** 권한 없음과 아동 부재를 **모두 404 `CHILD_NOT_FOUND`로 통일**한다(존재 비노출, 형제 API `requireChildAccess` 관례 우선 — develop 코드 기준). §7-d1의 403/404 분리안 대신 이 통일안을 채택. BusinessException→GlobalExceptionHandler.

## 9. 테스트
- 정상 목록(필터 없음), 각 필터(from/to·drawingTypeCode·sessionStatus·reportStatus) 적용, 정렬(startedAt/completedAt asc/desc), 페이지네이션, 빈 결과.
- 권한 없음·child 없음 모두 404(존재 비노출), 잘못된 sort/enum/from>to 400.
- N+1 회피(배치 조회) 확인, selectedEmotions=아동 선택만, report/analysis 없는 세션 null 안전.
- 컨트롤러/서비스/DTO JSON 테스트(151/153 구조). Docker 통합테스트 신규 없음.
