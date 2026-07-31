# 월간 감정 달력 조회 계약서 (as-built / S15P11B209-573)

- 상태: **as-built (구현 완료 기준)**
- 작성: 2026-07-31
- 기준: develop `7842ce6` 코드 + `erd-cloud-schema-v1.2.sql` + `V1__create_initial_schema.sql` 이후 적용 Migration
- 방침: 충돌 시 ① develop 병합 코드 → ② 최신 문서. Notion 라이브 조회 제외.

## 0. 정본 상태 (중요)

- **정본 `docs/api/API_명세서_최종.md`에 감정 달력·월간 집계·통계 엔드포인트 규정이 없다.** 전수 검색에서 `달력 / 캘린더 / calendar / 월간` 0건이며, API ID 목록(`CHILD-01~07`, `DRAWING-01~12`, `REPORT-01~07`, `HISTORY-01~03`, `NOTI-01~05`)에도 해당 항목이 없다.
- 즉 573은 **계약 공백에서 새로 정의한 API**다. 이 문서가 유일한 계약 근거이며, **정본 파일은 이번 작업에서 수정하지 않았다.**
- 정본 반영(섹션 추가·API ID 부여 등)이 필요하면 문서 담당자의 결정 사항이다. 이 문서는 구현된 사실만 기술한다.
- 신규 Flyway Migration 없음. 신규 인덱스 없음(§8 참고).

## 1. 개요

| 항목 | 값 |
| --- | --- |
| 메서드·URI | `GET /api/v1/children/{childId}/emotions/calendar` |
| 권한 | 연결 보호자(GUARDIAN, Bearer). 해당 `childId`와 보호자 관계 필수 |
| 성공 | 200 OK |
| 읽기 전용 | `@Transactional(readOnly = true)`, 조회 전용 Projection |
| 데이터 소스 | `drawing_sessions` ⨝ `drawing_session_emotions` (+ `reports` 스칼라 집계) |

구현 위치:

| 계층 | 파일 |
| --- | --- |
| Controller | `drawing/controller/EmotionCalendarController.java` |
| Service | `drawing/service/EmotionCalendarQueryService.java` |
| Repository | `drawing/repository/DrawingSessionRepository#findEmotionCalendarRows` |
| Projection | `drawing/repository/EmotionCalendarRowProjection.java` |
| 응답 DTO | `drawing/dto/response/EmotionCalendar{Response,DayResponse,SummaryResponse}.java` |

**Controller를 신설한 이유:** `/api/v1/children` prefix는 이미 `ChildController`(Tag `Children`), `DrawingSessionHistoryController`(Tag `Activity History`), `ReportListController`(Tag `Reports`) 세 Controller가 **각자 다른 Tag로 공유**하고 있다. 즉 이 코드베이스의 관례는 "URI prefix 공유 + 유스케이스별 Controller 분리"다. 기존 `DrawingSessionHistoryController`에 끼워 넣으면 그 클래스의 문서화된 책임(활동 기록 목록 페이지 조회)과 Swagger Tag가 넓어지므로, 관례대로 Controller를 분리했다.

## 2. Query 파라미터

| 필드 | 타입 | 필수 | 검증 |
| --- | --- | --- | --- |
| `childId` (path) | long | 필수 | `@Positive`. 0 이하 400 |
| `year` | int | **필수** | `2000 ~ 2100`. 벗어나면 400 |
| `month` | int | **필수** | `1 ~ 12`. 벗어나면 400 |

- 두 파라미터에 기본값을 두지 않았다. 서버 시계에 따라 응답 대상 월이 바뀌는 숨은 의존을 만들지 않기 위해 클라이언트가 항상 명시한다. 누락 시 400 `COMMON_400_004`.
- `year` 상한 2100은 달력 UI가 실수로 보낼 수 있는 극단값(예: 0, 999999)에 대해 무의미한 범위 스캔을 막기 위한 방어값이다.

## 3. 응답

```json
{
  "success": true,
  "code": "COMMON_200",
  "data": {
    "year": 2026,
    "month": 7,
    "days": [
      {
        "date": "2026-07-03",
        "representativeEmotion": "HAPPY",
        "emotions": ["HAPPY", "CALM"],
        "activityCount": 2,
        "completedReportCount": 1
      }
    ],
    "summary": {
      "activityCount": 12,
      "topEmotion": "HAPPY",
      "completedReportCount": 5
    }
  }
}
```

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `year`, `month` | int | 요청 값을 그대로 반환(클라이언트가 응답 정합을 확인할 수 있게) |
| `days` | array | **활동이 있는 날만** 일자 오름차순. 활동 없는 날은 **생략** |
| `days[].date` | date(ISO) | **KST 기준 일자** (§4) |
| `days[].representativeEmotion` | `EmotionType` \| null | 그날 마지막 활동의 첫 선택 감정 (§5) |
| `days[].emotions` | `EmotionType[]` | 그날 선택 감정 전체(중복 제거, 처음 선택된 순서) |
| `days[].activityCount` | long | 그날 활동 수. **감정 개수에 부풀지 않음** (§7) |
| `days[].completedReportCount` | long | 그날 활동에 연결된 `report_status = 'COMPLETED'` 리포트 수 |
| `summary.activityCount` | long | 그 달 활동 수 |
| `summary.topEmotion` | `EmotionType` \| null | 그 달 최다 선택 감정. 동수면 감정 코드 이름 사전순 (§6) |
| `summary.completedReportCount` | long | 그 달 완료 리포트 수 |

`EmotionType` = `HAPPY, SAD, ANGRY, SCARED, CALM, UNKNOWN` (`DrawingEmotionCode`, DB CHECK `ck_drawing_session_emotions_code`와 1:1. 정본 `API_명세서_최종.md:286`과 일치).

## 4. 날짜 경계 = KST (Asia/Seoul) — HISTORY-01과 다름

**확정 규칙**

- 요청 `year`/`month`를 **KST 월 시작 ~ 다음 달 시작(미만)** 으로 해석한다.
- 저장 값 `drawing_sessions.started_at`은 **UTC 벽시계 `LocalDateTime`** 이다(`DrawingSessionService`가 `LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)`로 기록, `DrawingSession` Javadoc "서버가 결정한 UTC 기준 시작 시각").
- 따라서 조회 범위는 **KST 월 경계를 UTC로 환산**해 전달한다.
  - 2026-07 요청 → `from >= 2026-06-30T15:00` (KST 07-01 00:00), `to < 2026-07-31T15:00` (KST 08-01 00:00)
- 응답 `days[].date` 도 저장 값을 다시 KST로 환산한 **KST 일자**다.
- 시간대 상수는 `EmotionCalendarQueryService.CALENDAR_ZONE = ZoneId.of("Asia/Seoul")`. 이 코드베이스 main 소스에서 `Asia/Seoul`을 Java로 다루는 첫 지점이다(기존에는 `ZoneOffset.UTC`만 사용).

**HISTORY-01과의 차이 (의도된 차이)**

| | HISTORY-01 `GET .../drawing-sessions` | HISTORY 달력(573) |
| --- | --- | --- |
| 날짜 경계 | **UTC** — `from.atStartOfDay()`를 UTC 저장 값과 직접 비교 | **KST** |
| 결과 | KST 00:00~09:00 활동이 전날 범위로 집계됨 | 사용자가 보는 날짜와 칸이 일치 |

- 573에서 **HISTORY-01의 경계 규칙을 바꾸지 않았다.** 목록 API는 이슈 범위 밖이고, 변경하면 기존 클라이언트의 `from`/`to` 의미가 조용히 바뀐다.
- 달력만 KST로 정한 근거: 달력은 "며칠에 무슨 감정이었나"를 칸으로 보여주는 UI이므로 9시간 skew가 월 첫날·마지막날 칸에서 **눈에 보이게** 틀린다. 목록은 정렬된 나열이라 같은 skew가 드러나지 않는다.
- 회귀 테스트로 고정한 경계: KST 월 첫날 00:30(UTC 전월 말일 15:30) 활동이 **해당 월 1일 칸**에 들어가고, KST 월말 23:30(UTC 말일 14:30) 활동이 **그 달에 남는다**.

## 5. 대표 감정 규칙 (`representativeEmotion`)

- **그날 `started_at`이 가장 늦은 활동**의 **첫 선택 감정**(`selection_order` 최소)이다.
- 그 마지막 활동이 감정을 선택하지 않았으면 `null`이다 — 같은 날 이전 활동에 감정이 있어도 `null`이다.
- 시작 시각이 같으면 `drawing_sessions.id`가 큰 활동을 뒤로 둬 결정적으로 만든다.

**이 규칙을 택한 이유:** 짝 FE 이슈 510이 이미 전용 API 없이 활동 목록을 받아 클라이언트에서 같은 규칙으로 집계하고 있다(`frontend/mobile/lib/features/guardian/presentation/widgets/mind_calendar_card.dart` `reduceDailyEmotions`: 그날 `startedAt` 최신 활동의 `selectedEmotions.first`). 573은 그 집계를 서버로 승격하는 이슈이므로 **표시 결과가 달라지지 않도록 동일 규칙을 재현**했다.

**`emotions`를 함께 주는 이유:** 대표 감정 하나만 주면 "표시 정책 변경 = 서버 변경"이 된다. 그날 감정 전체를 함께 주면 클라이언트가 대표 선정 규칙을 바꾸거나 여러 감정을 함께 표시하도록 바꿔도 **BE 무변경**으로 대응할 수 있다. `representativeEmotion`은 현재 동작 호환용, `emotions`는 확장용이다.

## 6. 월 최다 감정 (`topEmotion`) / tie-break

- 그 달 대상 활동의 감정을 **활동당 감정 1건씩** 센다(같은 세션에 같은 감정이 두 번 들어갈 수 없다 — `uk_drawing_session_emotions_session_emotion`).
- 최다 수가 **동수면 감정 코드 이름의 사전순(`Enum.name()` 오름차순)** 으로 앞서는 값을 선택한다.
  - 사전순: `ANGRY < CALM < HAPPY < SAD < SCARED < UNKNOWN`
  - 예) `SCARED` 1건 vs `CALM` 1건 → `CALM`
- 규칙을 명시하는 이유: 동수일 때 Map 순회 순서에 맡기면 같은 데이터가 배포마다 다른 값을 낼 수 있다. 사전순은 데이터·구현과 무관하게 재현 가능하다.
- 그 달에 선택 감정이 전혀 없으면 `null`(활동은 있어도 감정을 아무도 고르지 않은 경우 포함).

## 7. 집계 정확성 — 조인 곱셈 방어 (중요)

`drawing_sessions` 1건 ↔ `drawing_session_emotions` N건이므로 조인 결과 행이 감정 수만큼 늘어난다. 그대로 세면 `activityCount`가 부풀어 **보호자에게 활동 수를 과다 표시**한다.

구현 방식:

1. Repository는 **활동 × 감정 flat 행**을 한 Query로 반환한다(감정 없는 활동도 `emotionCode = null`인 1행).
2. Service가 **세션 식별자로 먼저 묶어** 활동 단위로 되돌린 뒤(`LinkedHashMap<Long, SessionAggregate>`) 일자·월 집계를 한다. 활동 수와 리포트 수는 **활동당 1회만** 누적된다.
3. `completedReportCount`는 조인이 아니라 **`count(*)` 스칼라 Subquery**로 세어 행이 늘어나지 않는다.
4. 네이티브 Query에서 `EXISTS`를 boolean으로 직접 매핑하지 않는다(MySQL `EXISTS`는 BIGINT를 반환해 `ClassCastException` → 500). 판정이 필요하면 `count(*)` + 비교를 쓴다.

회귀 테스트로 고정: 감정 3건인 활동 1건 → `activityCount = 1`, `completedReportCount`도 1회만 합산. 실 MySQL 통합 테스트에서도 같은 단언을 둔다.

`completedReportCount`의 의미: **완료 리포트 행 수**(distinct `reports.id`)다. FE 510이 계산하던 "최신 리포트가 COMPLETED인 활동 수"와는 한 활동에 리포트 버전이 여럿일 때(`uk_reports_session_version`) 값이 달라질 수 있다. 필드 이름대로 "리포트 수"를 세는 쪽을 택했다.

## 8. 성능

- **활동당 개별 Query 없음(N+1 금지).** 활동·감정·완료 리포트 수를 **단일 Query 1회**로 읽는다(`activity-history-list-contract.md:47`의 배치 조회 원칙과 동일 취지).
- Query 형태: `drawing_sessions` LEFT JOIN `drawing_session_emotions` 1회 + `reports` `count(*)` 스칼라 Subquery. `order by ds.started_at, ds.id, e.selection_order, e.id`로 집계 입력 순서를 결정적으로 고정한다.
- 네이티브 SQL을 쓰되 **DB 고유 시간대 함수(`convert_tz` 등)를 쓰지 않는다.** KST 환산은 전부 Java에서 하므로 Query가 이식 가능하고(H2 MySQL 모드 슬라이스 테스트 포함) 시간대 테이블 적재에 의존하지 않는다.
- **한계 — 인덱스 공백:** `drawing_sessions`의 기존 인덱스는 `idx_drawing_sessions_child_id (child_id, created_at)`, `idx_drawing_sessions_active_child (child_id, session_status, deleted_at)` 이고 **`started_at` 선행 인덱스가 없다.** 이 API는 `child_id` + `started_at` 범위 스캔이므로 `(child_id, started_at)` 인덱스가 있으면 유리하다. 다만 (a) 조회 단위가 한 아동의 한 달이라 데이터량이 작고 (b) `child_id` 선행 인덱스로 후보를 좁힌 뒤 범위 스캔이 가능하므로, **573에서는 스키마를 변경하지 않았다.** 인덱스 추가는 팀 스키마 변경이므로 필요성만 여기 기록한다.
- `drawing_session_emotions`는 `(drawing_session_id, emotion_code)` UNIQUE가 leftmost prefix 역할을 해 조인 조건에 인덱스 문제가 없다.

## 9. 대상 활동 제외 조건

| 조건 | 근거 |
| --- | --- |
| `deleted_at is null` | Soft Delete 전 Query 관례 |
| `session_status not in ('DELETED', 'ABANDONED')` | **HISTORY-01 `findHistoryPage`와 동일** |
| `child_id = :childId` | 요청 아동만 |
| `started_at >= from and < to` | KST 월 경계 환산값, 반경계(HISTORY-01과 같은 패턴) |

- **`FAILED`는 제외하지 않는다.** 이슈 설계 메모는 "`ABANDONED`·`FAILED` 제외(활동 기록 목록 관례 확인해 동일하게, 다르면 관례 우선)"였으나, 실측한 관례(`DrawingSessionRepository#findHistoryPage`)는 **`DELETED`와 `ABANDONED`만 제외하고 `FAILED`는 노출**한다. 지시대로 **관례를 우선**해 `FAILED`를 포함했다.
  - 실질적 근거: `FAILED`는 "처리 오류로 활동을 완료하지 못한" 상태다(`DrawingSessionStatus`). 아동이 그림을 그리고 감정을 골랐는데 서버 처리가 실패한 경우가 여기 해당하므로, 달력에서 지우면 아동의 기록이 사라진 것처럼 보인다. 목록 API와 달력이 같은 집합을 보여주는 편이 정합적이다.

## 10. 감정 출처 = 아동 선택만 (AI 추정 배제)

- 유일한 감정 소스는 **`drawing_session_emotions`** (아동이 회고 단계에서 직접 고른 감정).
- **`analysis_observation_results.observed_emotion` / `emotion_confidence`, `conversation_summaries.expressed_emotion` 등 AI 추정 감정, 위험도, 전문가 전용 필드는 조회 대상에 포함하지 않는다.**
  - 근거: `docs/api/activity-history-list-contract.md:50`(AI 추정 감정·위험도·전문가 전용 필드 노출 금지), `API_명세서_최종.md:1416`(보호자 응답에 `observedEmotion`/`emotionConfidence` 포함 금지), `:2281`, `:1042`, `:2481`(보호자에게 진단형 감정 추정 노출 금지).
  - 구조적 비노출: `observed_emotion` / `emotion_confidence`는 **Java Entity에 매핑 자체가 없다**(`AnalysisObservationResult`의 `@Column` 목록에 없음). 573은 이 테이블을 조인하지 않는다.

## 11. `UNKNOWN` 정책

- `UNKNOWN`("잘 모르겠어요")은 **유효한 아동 응답**이다(`API_명세서_최종.md:893`, `DRAWING-10`에서 다른 감정과 동시 선택 불가).
- 서버는 `UNKNOWN`을 **숨기지 않고 그대로 반환**한다. `emotions`에 포함되고, `representativeEmotion`이 될 수 있고, `topEmotion` 후보에도 들어간다.
- 근거: 서버가 저장된 아동의 응답을 임의로 지우면 "감정을 고르지 않음"과 "모르겠다고 답함"이 구분 불가능해진다. **표시 방법은 클라이언트 판단**이다.
- 참고(FE 현황, 수정 대상 아님): `mind_emotion.dart`의 `MindEmotion.fromApi`가 `UNKNOWN`을 매핑하지 않아 현재 "기록 없음"으로 처리한다. 서버 정책과 의미가 다르므로 FE 담당자가 표시 규칙을 정할 여지가 있다.

## 12. 에러

| HTTP | code | 조건 |
| --- | --- | --- |
| 400 | `COMMON_400_001` (`INVALID_INPUT_VALUE`) | `month` 1~12 밖, `year` 2000~2100 밖, `childId` 0 이하 |
| 400 | `COMMON_400_002` (`INVALID_TYPE_VALUE`) | `year`/`month`가 정수가 아님 |
| 400 | `COMMON_400_004` (`MISSING_REQUEST_PARAMETER`) | `year` 또는 `month` 누락 |
| 401 | `AUTH_401_006` (`AUTHENTICATION_REQUIRED`) | 인증 Principal 없음 |
| 404 | `CHILD_404_001` (`CHILD_NOT_FOUND`) | 아동 없음/비활성 **또는 보호자-아동 관계 없음** |

- 권한 없음과 아동 부재를 **모두 404 `CHILD_NOT_FOUND`로 통일**한다 — 식별자 존재 여부 비노출. `GuardianResourceAccessValidator.requireChildAccess()` 재사용이며 HISTORY-01·CHILD 계열과 동일하다(`activity-history-list-contract.md:66` as-built 규칙과 일치).
- 인증은 `CurrentAuthenticatedUserResolver.requireUserId()`가 담당하고, 예외는 `GlobalExceptionHandler`가 공통 `ApiErrorResponse`로 변환한다. 응답에 예외 원문·Stack Trace·SQL·제약명을 담지 않는다.
- 조건에 맞는 활동이 없으면 **오류가 아니라** `days: []` + 0/`null` 요약의 200이다.

## 13. 테스트 (구현 범위)

| 계층 | 파일 | 고정한 규칙 |
| --- | --- | --- |
| Controller | `drawing/controller/EmotionCalendarControllerTest` | 200 구조·필드, `month` 0/13 400, `year` 1999/2101 400, 파라미터 누락 400, 타입 오류 400, `childId` 0 400, 401, 404 |
| Service | `drawing/service/EmotionCalendarQueryServiceTest` | KST→UTC 조회 범위, 월 첫날 00:30·월말 23:30 경계, **감정 다건 시 activityCount 불변(조인 곱셈 회귀)**, 대표 감정 = 최신 활동 첫 감정, 최신 활동 감정 없으면 `null`, 감정 중복 제거, 활동 없는 날 생략, 최다 감정, tie-break, `UNKNOWN` 포함, 리포트 수 활동당 1회, 빈 달, 권한 실패 시 조회 안 함 |
| Repository | `drawing/repository/EmotionCalendarRepositoryTest` (H2 MySQL 모드) | 감정당 1행, 감정 없으면 `emotionCode = null` 1행, 정렬, Soft Delete·`DELETED`·`ABANDONED` 제외(`FAILED` 포함), 범위 반경계, 다른 아동 제외, `COMPLETED` 리포트만 카운트 |
| 통합 | `drawing/EmotionCalendarIntegrationTest` (Testcontainers 실 MySQL) | HTTP 관통 — KST 경계로 월이 갈리는 활동, 하루 다건 집계, 조인 곱셈 방어, 빈 달, 타인 아동 404, `month` 13 400, 미인증 401 |

기존 테스트는 삭제·비활성화하지 않았다.

## 14. 한계 / 후속 (사실만 기록)

- **FE는 아직 이 API를 호출하지 않는다.** `frontend/mobile`·`frontend/web` 전체에서 `emotion-calendar` / `emotions/calendar` / `MonthlyEmotion*` / `EmotionCalendar*` 문자열·타입 0건이고, 달력 카드는 여전히 `GET children/{childId}/drawing-sessions?size=100`으로 받아 클라이언트에서 집계한다. **전환은 FE 담당자의 작업이며 이 이슈에서 FE 코드를 수정하지 않았다.**
- 서버 전환 시 해소되는 FE 현재 결함 2건:
  1. `size: 100`이 서버 `MAX_PAGE_SIZE`(100) 상한과 같아 **한 달 활동이 100건을 넘으면 조용히 잘린다.** 달력 API는 페이지 상한이 없어 월 전체를 집계한다.
  2. FE가 만드는 `from`/`to`는 로컬(KST) 날짜인데 HISTORY-01은 UTC 경계로 해석해 **월 경계 9시간 skew**가 생긴다. 달력 API는 KST 경계로 계산한다(§4).
- `(child_id, started_at)` 인덱스 없음 — §8. 스키마 변경은 이 이슈 범위 밖.
- `topEmotion`의 tie-break는 사전순이며, "가장 최근에 선택된 감정 우선" 같은 다른 정책이 요구되면 계약 변경이 필요하다.
- `summary.completedReportCount`의 셈 기준(리포트 행 수 vs 최신 리포트가 완료인 활동 수)은 §7 말미 참고. FE 표시 문구와 의미를 맞출 필요가 있으면 확인이 필요하다.
