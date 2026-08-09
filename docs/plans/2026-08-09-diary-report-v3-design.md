# 그림일기 리포트 V3 설계

## 1. 목적과 범위

그림일기 리포트 V3는 리포트 문장을 단순히 늘리는 기능이 아니다. 보호자가 각 내용의 근거와 한계를 확인하고 아이와 다음 대화를 이어 갈 수 있도록 다음 계층을 분리한다.

1. 그림·대화·감정 선택·활동 기록에 남은 원자료
2. 원자료에서 확인된 사실
3. 이번 활동에 한정한 제한적 가설
4. 다른 가능한 설명
5. 보호자가 다음에 확인할 질문
6. 충분한 활동이 쌓였을 때만 제공하는 누적 관찰

단일 그림·색·배치·활동 수치로 성격이나 심리 상태를 단정하지 않는다. 진단명, 위험 확률, 백분위, 또래 비교 점수는 이 리포트의 범위가 아니다. 외부에서 실시한 검증된 선별검사 기록은 기존 `screeningSummary` 영역에 분리해 표시한다.

Jira 작업은 다음과 같이 분리한다.

- `S15P11B209-1018`: 그림일기 리포트 V3 완성형 전환 에픽
- `S15P11B209-1019`: 단일 활동 그림일기 리포트 V3
- `S15P11B209-1020`: 그림일기 누적 관찰 및 최근 기록

## 2. 호환 전략

기존 `diaryInsights`를 폐기하지 않고 `schemaVersion=3`으로 확장한다.

- 새 AI·Backend·Flutter는 V3 필드를 사용한다.
- V3 필드가 없는 기존 V2 리포트는 기존 화면으로 표시한다.
- `diaryInsights`가 없는 레거시 그림일기는 기존 리포트 화면으로 표시한다.
- HTP 리포트의 생성·저장·조회·화면 계약은 변경하지 않는다.
- 기존 리포트 데이터는 마이그레이션 과정에서 추정해 채우지 않는다.

## 3. 생성 아키텍처

```text
그림·대화·감정·활동 기록
        ↓
결정론적 DiarySignalExtractor
        ↓
AI DiaryReportWriter
        ↓
ReportQualityReviewer + 서버 근거 검증
        ↓
Backend 정규화 저장
        ↓
Flutter V3 화면·PDF
```

### 3.1 DiarySignalExtractor

모델이 아니라 서버 코드가 다음 내용을 원자료에서 계산한다.

- 음성 답변, 선택 답변, 건너뜀, STT 확인 필요 건수
- 선택형 답변과 아동이 직접 구성한 발화의 구분
- 이야기 구성 요소별 확인 상태
- 허용된 근거 참조 목록
- 자료 충분도
- 확인하지 못한 항목
- 전체 대화 스냅샷의 순서와 원본 메시지 참조

### 3.2 DiaryReportWriter

AI는 검증된 원자료 범위 안에서 다음 항목만 작성한다.

- 핵심 이야기 제목과 요약
- 그림 관찰의 보호자용 문장
- 확인된 표현
- 이번 활동에 한정한 제한적 가설
- 다른 가능한 설명
- 보호자 확인 질문

근거가 없는 배열은 비워 둔다. 빈 배열을 일반적인 문장으로 채우지 않는다.

### 3.3 ReportQualityReviewer

다음 문제를 검사한다.

- `DUPLICATE_CONTENT`
- `GENERIC_INSIGHT`
- `GENERIC_GUIDANCE`
- `UNSUPPORTED_PREFERENCE`
- `UNSUPPORTED_PSYCHOLOGY`
- `MISSING_ALTERNATIVE_EXPLANATION`
- `ELICITATION_OVERCLAIM`
- `EMOTION_LINK_UNCONFIRMED`
- `MISSING_DATA_DISCLOSURE`
- `CHILD_VOICE_DISTORTION`
- `MISSING_AUDIO_TRANSCRIPT`
- `LONGITUDINAL_OVERCLAIM`

문제가 있는 항목만 제거하며, 검토 실패를 이유로 아이의 원문·그림 설명을 로그에 기록하지 않는다.

## 4. 자료 충분도

`evidenceLevel`은 아이의 능력이나 리포트 점수가 아니라 이번 리포트가 사용할 수 있는 원자료 범위다.

### 4.1 LIMITED

- 아동이 직접 구성한 확인 가능 발화가 없다.
- 그림 관찰 또는 선택 감정 위주다.
- `SESSION_HYPOTHESIS`를 만들지 않는다.
- 객관적 관찰, 선택 내용, 전체 기록, 미확인 항목을 중심으로 표시한다.

### 4.2 PARTIAL

- 확인 가능한 일부 발화가 있으나 사건 흐름이 충분하지 않다.
- `CONFIRMED_EXPRESSION`과 `EXPLORE_NEXT` 중심으로 표시한다.
- 가설은 독립 근거 기준을 충족할 때만 허용한다.

### 4.3 RICH

- 아동이 직접 구성한 발화와 이야기 흐름, 별도 관찰 근거가 충분하다.
- 최대 두 개의 `SESSION_HYPOTHESIS`를 허용한다.
- 각 가설은 근거, 다른 설명, 확인 질문을 모두 포함해야 한다.

선택형 답변, 예·아니오 답변, 같은 발화에서 파생된 여러 문장은 독립된 아동 발화로 중복 계산하지 않는다.

## 5. API 계약

### 5.1 리포트 상세 확장

기존 `GET /api/v1/reports/{reportId}` 응답의 `diaryInsights`에 다음 필드를 추가한다.

```json
{
  "schemaVersion": 3,
  "dataScope": {
    "evidenceLevel": "LIMITED",
    "summary": "그림과 선택 감정을 중심으로 정리했어요.",
    "confirmedVoiceCount": 0,
    "optionAnswerCount": 1,
    "skippedCount": 3,
    "sttConfirmationCount": 0,
    "visualObservationCount": 2
  },
  "storyComponents": [
    {
      "componentType": "ACTOR",
      "status": "VISUAL_ONLY",
      "text": "인물 형태가 보여요.",
      "evidenceRefs": []
    }
  ],
  "drawingObservations": [
    {
      "text": "하늘 부분에 별과 달 모양이 보여요.",
      "confidence": "HIGH",
      "childConfirmed": false,
      "evidenceRefs": []
    }
  ],
  "transcript": [
    {
      "questionMessageId": 10,
      "answerMessageId": 11,
      "questionText": "오늘 무엇을 그렸는지 이야기해 줄래?",
      "answerText": null,
      "responseType": "SKIPPED",
      "sttStatus": null,
      "audioDurationMs": null,
      "audioAvailable": false,
      "audioUrl": null,
      "elicitationType": "OPEN_INVITATION",
      "createdAt": "2026-08-09T12:00:00+09:00"
    }
  ]
}
```

규칙은 다음과 같다.

- `schemaVersion`이 없으면 V2로 읽는다.
- 목록은 `null` 대신 빈 목록을 반환한다.
- 음성 URL은 DB에 저장하지 않고 조회 시 기존 JWT 인증 Proxy 경로로 만든다.
- 음성 원본이 삭제됐으면 텍스트는 유지하고 `audioAvailable=false`, `audioUrl=null`을 반환한다.
- `responseType`은 `VOICE`, `OPTION`, `TEXT`, `SKIPPED`, `CORRECTION` 중 하나다.
- 선택 답변은 `OPTION`, 건너뛴 질문은 `SKIPPED`로 명시해 직접 발화와 구분한다.

### 5.2 누적 관찰 API

```http
GET /api/v1/children/{childId}/diary-trends?asOfReportId={reportId}&limit=5
```

단일 리포트 스냅샷과 분리한다. 단일 리포트는 생성 시점 내용이 유지되지만 최근 기록은 새 활동이 추가될 때 바뀌기 때문이다.

응답에는 다음을 포함한다.

- 포함된 활동 수와 서로 다른 활동 날짜 수
- 조회 기간
- 이야기 주제 빈도
- 감정 표현 출처 빈도
- 이야기 구성 요소 확인 현황
- 관계 역할 빈도
- 대처·도움 요청 방식
- 음성 답변·선택 답변·건너뜀 변화
- 서버가 기준을 충족해 확인한 반복 관찰

누적 조회 실패는 리포트 상세 조회를 실패시키지 않는다.

## 6. DB 설계

JSON 컬럼을 추가하지 않는다.

### 6.1 기존 테이블 확장

`report_diary_insights`에 다음 컬럼을 추가한다.

- `schema_version`
- `evidence_level`
- `data_scope_summary`
- `visual_observation_count`

기존 음성·선택·건너뜀·STT·근거 건수 컬럼은 재사용한다.

### 6.2 신규 정규화 테이블

- `report_diary_story_components`
  - 구성 요소, 확인 상태, 문장, 노출 순서
- `report_diary_visual_observations`
  - 관찰 문장, 확신도, 아동 확인 여부, 노출 순서
- `report_diary_transcript_entries`
  - 질문·답변 메시지 ID, 텍스트 스냅샷, 응답 유형, STT 상태, 음성 길이, 유도 방식, 시각
- `report_diary_fact_categories`
  - 누적 집계용 주제·관계 역할·대처 방식·감정 표현 출처

근거 참조는 기존 `report_diary_evidence_refs`를 재사용하고 `owner_type`을 확장한다.

## 7. 누적 관찰 기준

- 1~2회: 누적 영역을 표시하지 않는다.
- 3~4회: `최근 기록`으로만 표시한다.
- 5회 이상: `반복해서 나타난 내용`을 표시할 수 있다.
- 반복 관찰 카드에는 최소 3개 활동, 서로 다른 2일 이상, 관련된 아동 직접 구성 발화 2건 이상이 필요하다.
- 같은 답변이나 같은 날짜의 재생성 리포트는 독립 근거로 중복 계산하지 않는다.
- 실명은 집계하지 않고 보호자, 형제자매, 친구, 선생님, 기타 역할로 변환한다.
- 비교 기준은 또래가 아니라 같은 아이의 이전 활동이다.

## 8. Flutter 화면

단일 활동 V3는 다음 순서로 표시한다.

1. 완성 그림과 한 줄 이야기
2. 이번 기록의 자료 범위
3. 그림에서 확인된 표현
4. 이야기 구성 지도
5. 아이가 직접 들려준 말
6. 확인된 표현과 제한적 가설
7. 다른 가능한 설명과 확인 질문
8. 이번에는 확인하지 못한 내용
9. 오늘 마음 나누기
10. 최근 활동 비교
11. 접이식 전체 대화·음성·활동 상세

화면은 근거 ID나 내부 enum을 그대로 노출하지 않는다. 자료 충분도는 점수나 진행률로 표현하지 않는다. `LIMITED` 상태에서도 해석을 억지로 만들지 않고 객관적 관찰과 전체 기록을 충분히 보여 준다.

누적 조회가 실패하면 최근 활동 비교만 숨기고 단일 리포트는 그대로 표시한다.

## 9. PDF

PDF는 화면과 같은 근거 계층을 사용한다.

- 전체 대화 텍스트를 포함한다.
- 음성이 있는 발화에는 `앱에서 음성 재생 가능` 표시를 붙인다.
- 실제로 동작하는 리포트 딥링크가 마련되기 전에는 QR을 생성하지 않는다.
- 음성 파일 자체는 PDF에 포함하지 않는다.
- 단일 활동의 심리 점수·레이더 차트는 만들지 않는다.

## 10. 부분 실패와 안전

- AI가 특정 섹션을 잘못 생성하면 그 섹션만 제거한다.
- V3 전체 조립이 실패하면 V2 또는 레거시 리포트로 폴백한다.
- 근거 참조가 요청 원자료에 없으면 해당 항목을 저장하지 않는다.
- 가설에 대안 설명이나 확인 질문이 없으면 가설을 저장하지 않는다.
- 누적 기준을 충족하지 못하면 빈 목록과 기준 안내를 반환한다.
- 로그에는 리포트 ID, 품질 코드, 필드 경로만 기록하고 아이 발화·그림 설명은 기록하지 않는다.

## 11. 검증

### 11.1 고정 Fixture

- `LIMITED`: 선택 감정 한 건과 건너뛴 질문만 있음
- `PARTIAL`: 선택 답변과 일부 확인된 직접 발화가 있음
- `RICH`: 직접 발화, 이야기 흐름, 별도 그림 관찰이 충분함

### 11.2 AI

- 자료 충분도 경계
- 선택 답변과 직접 발화 구분
- 가설 최대 두 개와 대안·질문 필수 조건
- 일반론·중복·감정 연결 과장 검토 코드
- 개인 원문을 포함하지 않는 검토 로그

### 11.3 Backend

- Flyway 마이그레이션과 JSON 컬럼 부재 검증
- V3 저장·조회 왕복
- 기존 V2·HTP 역직렬화 회귀
- 음성 존재·삭제·STT 확인 필요 상태
- 보호자 소유권과 누적 조회 권한
- 누적 임계값 2회, 3회 같은 날짜, 3회 서로 다른 날짜, 5회 경계

### 11.4 Flutter

- LIMITED/PARTIAL/RICH Widget 테스트
- 빈 섹션과 V2 폴백
- 음성 재생 가능·삭제·오류 상태
- 누적 조회 부분 실패
- 화면 dispose 뒤 늦은 응답 안전성
- 리포트 본문·PDF 저장·공유 회귀
- 태블릿과 모바일 스크린샷 테스트

### 11.5 완료 검증

- AI 테스트 전체
- Backend `clean test`, `spotlessCheck`, `javadoc`
- Flutter 정적 분석과 전체 테스트
- 생성 Javadoc `build/docs/javadoc/index.html` 확인
- 실제 LIMITED·PARTIAL·RICH 응답의 앱 표시 확인

## 12. 구현 순서

1. `S15P11B209-1019`: AI·Backend·Flutter 단일 활동 V3를 종단으로 구현한다.
2. 단일 활동 V3가 병합된 최신 `develop`에서 `S15P11B209-1020` 브랜치를 만든다.
3. 누적 정규화·조회·Flutter 최근 기록을 구현한다.
4. 각 작업은 독립 MR과 검증 결과를 가진다.
