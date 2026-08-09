# ERDCloud 통합 스키마 v1.1 명세

## 1. 문서 목적

이 문서는 다음 자료를 함께 검토해 작성한 ERD 리뷰용 Target Model 명세다.

- Jira `S15P11B209-132` 초기 MySQL 스키마
- API 공통 규약(2026-07-21)
- ERD 보강 필요 목록 57건
- API–ERD 정합성 검증 보고서
- 직군별 API 명세 활용 가이드

ERDCloud Import 파일은 `docs/database/erd-cloud-schema-v1.1.sql`이다. 이 SQL은 영문 `snake_case` 물리명과 한국어 `COMMENT` 논리명을 함께 제공한다.

> 이 파일은 ERD 리뷰와 다음 Migration 설계를 위한 Target Model이다. 이미 적용된 `V1__create_initial_schema.sql`을 수정하거나 대체하지 않는다. 상태값과 신규 테이블은 팀 합의 후 별도 Flyway Migration으로 옮겨야 한다.

## 2. ERDCloud Import 방법

1. 기존 ERDCloud 프로젝트를 복제하거나 별도 Version으로 백업한다.
2. SQL Import의 DBMS를 MySQL로 선택한다.
3. `erd-cloud-schema-v1.1.sql` 전체를 UTF-8로 Import한다.
4. Table Comment를 논리명, Table 이름을 물리명으로 표시한다.
5. 도메인별로 사용자·동의, 그림·대화, 분석·리포트, 커뮤니티·운영 영역을 배치한다.
6. Import 후 Table 36개와 FK 관계를 확인한다. ERDCloud가 `CHECK` 내용을 표시하지 않으면 이 문서의 코드값 표를 함께 사용한다.

MySQL 8.4.10 실제 실행 검증 결과는 다음과 같다.

| 항목 | 결과 |
| --- | ---: |
| Table | 36개 |
| Foreign Key | 55개 |
| CHECK Constraint | 57개 |
| 전체 DDL 실행 | 성공 |

## 3. 공통 설계 규칙

- PK는 원칙적으로 `BIGINT NOT NULL AUTO_INCREMENT`다.
- 시각은 `DATETIME(6)`, 날짜는 `DATE`를 사용하며 API에서는 UTC ISO-8601로 변환한다.
- 문자 집합은 `utf8mb4`, Collation은 `utf8mb4_0900_ai_ci`, Engine은 InnoDB다.
- 제약 이름은 `pk_`, `fk_`, `uk_`, `ck_`, `idx_` 접두사를 사용한다.
- API JSON의 ID는 DB `BIGINT`와 대응하는 JSON number다.
- 사용자 입력 파일명이나 절대 파일 경로를 저장하지 않고 `storage_key`만 영속화한다.
- 아동 발화·그림·분석 원문은 로그에 기록하지 않는다. ERD Column 존재가 로그 허용을 의미하지 않는다.
- 커뮤니티 Table은 분석·대화·리포트 Table과 직접 FK로 연결하지 않는다. `complaints`의 신고 대상 참조만 운영상 예외다.
- Soft Delete 대상은 상태값과 `deleted_at`을 함께 사용한다.

## 4. 전체 Table 명세

### 4.1 사용자·인증·동의

| 논리명 | 물리명 | 핵심 데이터 | 주요 제약과 관계 |
| --- | --- | --- | --- |
| 사용자 | `users` | 역할, 닉네임, 계정 상태, 알림 설정, 온보딩, 로그인·탈퇴 시각 | 최초 가입 중 `role`은 NULL 가능. `account_status` CHECK. 인증·Token·관계·알림의 기준 사용자 |
| 아동 | `children` | 닉네임, 생년월일, 선호 캐릭터, 질문 난이도, 응답 방식, 튜토리얼 진행 | 난이도·튜토리얼·Profile 상태 CHECK. `tutorial_last_step`, `tutorial_completed_at`으로 이어하기 지원 |
| 그림 활동 유형 | `drawing_types` | 활동 코드, 분류, 선택 주체, 권장 연령, 안내와 노출 순서 | `code` UNIQUE. `selectable_by`는 `GUARDIAN`, `GUARDIAN_OR_CHILD` |
| 동의 약관 | `consent_terms` | 약관 코드, 대상 범위, 필수 여부, Version, 철회 영향 | `(term_code, version)` UNIQUE. 약관 코드와 `USER`/`CHILD` 범위 CHECK |
| 인증 계정 | `auth_accounts` | Provider Subject, 로그인 Email, Password Hash, Email 인증 시각 | `(provider, provider_subject)` UNIQUE. Local Email은 Generated Column으로만 UNIQUE |
| Refresh Token | `refresh_tokens` | Token Hash, 기기, 만료·폐기·사용·재사용 감지 시각 | `token_hash` UNIQUE. `replaced_by_token_id` Self FK로 RTR 교체 Chain 추적 |
| 이메일 인증 | `email_verifications` | 인증 계정, 인증 코드 Hash, 만료·검증 시각, 시도 횟수 | 인증 계정 삭제 시 CASCADE. 평문 인증 코드는 저장하지 않음 |
| 보호자-아동 관계 | `guardian_child_relations` | 보호자, 아동, 관계 유형 | `(guardian_user_id, child_id)` UNIQUE. 모든 childId API 소유권 검증의 근거 |
| 동의 이력 | `consent_records` | 약관, 처리자, 대상 아동, 대상 Hash, 동의·철회 증빙 | 이력 보존형 Append 구조. 처리자·아동·대상 Hash별 최신 이력 조회 Index |
| 데이터 내보내기 작업 | `data_export_jobs` | 사용자, 비동기 상태, 파일 Key, 만료·완료·오류 정보 | 사용자별 생성 이력 및 상태별 Worker 조회 Index. 완료 파일은 만료 정책 필요 |

### 4.2 전문가

| 논리명 | 물리명 | 핵심 데이터 | 주요 제약과 관계 |
| --- | --- | --- | --- |
| 전문가 Profile | `expert_profiles` | 공개 이름, 소속, 경력, 전문 분야, 자격 증빙, 검증 상태 | 사용자당 하나만 허용. 자격 정보 변경 시 재심사 전환은 Service 정책으로 처리 |
| 전문가 Follow | `expert_follows` | 보호자 사용자와 전문가 Profile 관계 | `(guardian_user_id, expert_profile_id)` UNIQUE |
| 미술 활동 자료 | `activity_templates` | 작성 전문가, 제목·본문, 연령, 활동 유형, Thumbnail·첨부 Key | 전문가 FK, Soft Delete. 첨부 Key는 JSON 배열로 보관 |

### 4.3 그림 활동·대화

| 논리명 | 물리명 | 핵심 데이터 | 주요 제약과 관계 |
| --- | --- | --- | --- |
| 그림 활동 Session | `drawing_sessions` | 아동, 활동 유형, 입력 방식, 제목, 감정, 상태와 현재 단계 | 아동·유형 FK. 상태와 단계는 최신 API 공통 규약 코드로 CHECK |
| Stroke Batch | `stroke_batches` | Session, Batch·이벤트 순번, 이벤트 수, 획 Payload | `(drawing_session_id, batch_sequence)` UNIQUE. 순번 범위와 양수 이벤트 수 CHECK |
| 그림 파일 | `drawing_assets` | Session, 자산 유형·Version, 오브젝트, 마지막 이벤트 순번, Storage Metadata | 원본 파일명 대신 `storage_key`. Checksum과 크기 보관. Session·유형·Version Index |
| AI 질문 Template | `ai_question_templates` | 그림 유형, Template 유형, 연령·난이도, 목적, 질문·선택지·위험 대응 | 작성·수정자 FK. `NORMAL`, `FALLBACK`, `RISK_RESPONSE` 유형 CHECK |
| 대화 Session | `conversation_sessions` | 그림 Session, 상태, 난이도·캐릭터 Snapshot, 질문 수 | `drawing_session_id` UNIQUE로 그림 Session당 하나. 질문 수 범위 CHECK |
| 대화 Message | `conversation_messages` | Session, 상위 Message, 순번, 발신·Message 유형, Text·음성·선택지 | Session별 순번 UNIQUE. 음성 Storage Key와 SHA-256 Checksum 보관 |
| 대화 Message 음성 변형 | `conversation_message_audio_variants` | Message, Voice, 속도, 음성 Storage Metadata | `(message, voice, speed)` UNIQUE로 TTS Cache 중복 방지 |

### 4.4 분석·리포트

| 논리명 | 물리명 | 핵심 데이터 | 주요 제약과 관계 |
| --- | --- | --- | --- |
| 분석 | `analyses` | 그림 Session, 재시도 원본, 멱등 Key, 입력 Checksum, 상태, Model, 오류 | `idempotency_key` UNIQUE. 상태는 `PENDING→RUNNING→COMPLETED/FAILED` |
| 분석 시각 특징 | `analysis_visual_features` | 점유율, 색상, 명도·채도, 선·배치 특징 | 분석 FK. 비율형 신뢰값은 0~1 범위 사용 |
| 분석 행동 특징 | `analysis_behavior_features` | 활동 시간, 정지·Stroke·Undo·도구·색상 변경 수 | 분석 FK. 물리명은 오타를 고친 `tool_change_count` |
| 분석 탐지 객체 | `analysis_detected_objects` | 분석, 그림 파일, 객체, Confidence, Bounding Box | 분석·그림 파일 FK. Confidence 0~1 CHECK |
| 분석 관찰 결과 | `analysis_observation_results` | 요약, 긍정 신호, 관찰 지점, 보호자 안내, 검토 상태 | 진단 결과가 아닌 관찰 보조자료. 감정 관련 값은 전문가 내부 검토용 |
| 분석 제외 입력 | `analysis_unused_inputs` | 분석에서 제외한 입력 출처·순번·사유·재시도 가능 여부 | 분석 FK. 실패 원문 대신 안전한 요약·Code 저장 |
| 대화 분석 요약 | `analysis_conversation_summaries` | 분석, 대화 Session, 주제·응답·미응답 요약 | PK 물리명은 `conversation_summary_id`. 대화 삭제 시 FK SET NULL |
| 리포트 | `reports` | Session·분석, Version, JSON Section, 한계 고지, PDF 상태·Key | Session별 Version UNIQUE. `limitations_text` NOT NULL. PDF 생성 상태 별도 관리 |
| Storage 삭제 작업 | `storage_deletion_jobs` | Storage Key, Resource, 삭제 상태, 재시도·오류 | DB 행 처리와 Object Storage 삭제를 분리하는 Worker Queue |

### 4.5 커뮤니티·알림·운영

| 논리명 | 물리명 | 핵심 데이터 | 주요 제약과 관계 |
| --- | --- | --- | --- |
| 커뮤니티 게시글 | `community_posts` | 작성자, 유형, 제목·본문, 익명·공개·상태 | 작성자 삭제 시 SET NULL, 게시글은 Soft Delete. 분석·대화 데이터 FK 없음 |
| 댓글 | `comments` | 게시글, 작성자, 본문, 익명·공개·상태 | 게시글 삭제 시 CASCADE, 작성자 삭제 시 SET NULL |
| 게시글 좋아요 | `post_likes` | 게시글과 사용자 관계 | `(post_id, user_id)` UNIQUE로 중복 좋아요 방지 |
| 신고 | `complaints` | 신고자, 대상 유형·FK, 사유, 처리 상태·관리자·결과 | 리포트·게시글·댓글 중 정확히 하나만 대상으로 갖는 CHECK. 대상 물리 삭제 RESTRICT |
| 알림 | `notifications` | 수신자, 유형, 내용, 관련 Resource, 전송·읽음 상태 | 수신자별 최신 조회 Index. 위험 신호는 보호자 전용 응답에서만 사용 |
| Push 기기 Token | `device_tokens` | 사용자, Provider Token·Hash, Platform, Provider, 활성 상태 | `token_hash` UNIQUE. Token 원문은 로그 금지 및 운영 환경 암호화 필요 |
| 감사 Log | `audit_logs` | 처리자, 행위, Resource, 변경 전후 Snapshot, IP | Resource·처리자별 Index. 민감 원문과 Token을 Snapshot에 넣지 않음 |

## 5. v1.1 변경 내역

### 기존 V1에서 이미 반영된 Preview 수정

- `conversation_sessions.conversation_id`를 `drawing_session_id`로 수정했다.
- `analysis_behavior_features.tool_chnage_count`를 `tool_change_count`로 수정했다.
- `analysis_conversation_summaries.conversation_sumaary_id`를 `conversation_summary_id`로 수정했다.
- 탐지 객체의 그림 참조를 존재하는 `drawing_assets.id`로 연결했다.
- 모든 식별 PK에 자동 증가, FK·UNIQUE·CHECK·조회 Index를 명시했다.

### v1.1에서 보강한 Column·제약

- `users`: 온보딩 전 `role` NULL 허용, `deleted_at`, `DORMANT`·`DELETED` 상태 추가
- `children`: 튜토리얼 마지막 단계·완료 시각 추가, 난이도 Code 정렬
- `drawing_types`: 선택 주체를 `GUARDIAN`, `GUARDIAN_OR_CHILD`로 정렬
- `consent_terms`: 약관 Code·대상 범위 CHECK와 철회 영향 문구 추가
- `refresh_tokens`: Token Hash UNIQUE, RTR 교체 Self FK와 재사용 감지 시각 추가
- `guardian_child_relations`: 관계 유형 CHECK 추가
- `consent_records`: 처리자·대상 아동의 최신 이력 조회 Index 추가
- `drawing_sessions`: 공통 규약의 상태·단계 Code 반영
- `drawing_assets`: `object_code`, `last_event_sequence` 추가
- `ai_question_templates`: Template·연령·난이도 CHECK 추가
- `conversation_sessions`: 그림 Session당 하나 UNIQUE, 캐릭터 Snapshot 추가
- `conversation_messages`: 음성 Checksum과 공통 Message·음성 처리 Code 반영
- `analyses`: 비동기 분석 상태를 `PENDING`, `RUNNING`, `COMPLETED`, `FAILED`로 정렬
- `reports`: `pdf_status` 추가
- `notifications`: 공통 알림 유형 Code 반영

### 신규 Table

- `email_verifications`
- `data_export_jobs`
- `conversation_message_audio_variants`
- `complaints`
- `device_tokens`
- `activity_templates`
- `storage_deletion_jobs`

## 6. JSON Column 계약

JSON은 관계·검색 기준이 아닌 구조화 Snapshot에만 사용한다. 내부 Key는 API의 camelCase를 유지한다.

| Column | 기준 구조 |
| --- | --- |
| `users.notification_settings_json` | `pushEnabled`, `analysisCompleted`, `reportCreated`, `communityReply`, `expertNewPost`, `marketing`, `termsUpdated` 등 Boolean 설정 객체 |
| `children.response_modes_json` | `VOICE`, `OPTION` 값의 배열 |
| `stroke_batches.payload_json` | `seq`, `type`, `x`, `y`, `t`, `pressure`, `tool`, `color`, `thickness`를 갖는 이벤트 배열 |
| `expert_profiles.credentials_json` | `licenseName`, `issuer`, `proofFileKeys`를 갖는 자격 목록 |
| `ai_question_templates.options_json` | `optionId`, `optionType`, `value`, `label`을 갖는 선택지 배열 |
| `conversation_messages.options_json` | 질문 시점 선택지 Snapshot |
| `conversation_messages.selected_response_json` | 선택한 응답의 ID·유형·값 Snapshot |
| `conversation_messages.target_object_json` | 대상 객체와 `boundingBox {x, y, width, height}` |
| `reports.*_json` | API 리포트 상세 응답 Section의 Snapshot. `limitations_text`와 위험 신호 접근 통제는 일반 Column·Service에서 별도 강제 |
| `activity_templates.attachment_keys_json` | 절대 URL이 아닌 Storage Key 문자열 배열 |
| `audit_logs.before_json`, `after_json` | 민감 원문과 Token을 제거한 변경 Snapshot |

JSON Schema의 세부 필수 Key와 Version은 API 상세 페이지·AI 계약과 함께 확정해야 한다. 구조 변경 시 Column을 즉시 늘리기보다 JSON Schema Version 정책을 먼저 정한다.

## 7. 코드값 기준

| 대상 | 값 |
| --- | --- |
| 사용자 역할 | `GUARDIAN`, `EXPERT`, `ADMIN` |
| 계정 상태 | `PENDING`, `ACTIVE`, `DORMANT`, `SUSPENDED`, `DELETED` |
| 질문 난이도 | `PRESCHOOL`, `ELEMENTARY`, `DEVELOPMENTAL_SUPPORT`, `CUSTOM` |
| 튜토리얼 | `NOT_STARTED`, `IN_PROGRESS`, `COMPLETED`, `SKIPPED` |
| 그림 입력 방식 | `CANVAS`, `UPLOAD` |
| 그림 Session 상태·단계 | `DRAFT`, `DRAWING`, `CONVERSING`, `ANALYZING`, `ANALYZED`, `COMPLETED`, `FAILED`, `DELETED` |
| 분석 상태 | `PENDING`, `RUNNING`, `COMPLETED`, `FAILED` |
| 대화 상태 | `CONVERSING`, `COMPLETED` |
| Message 발신자 | `AI`, `CHILD`, `GUARDIAN`, `SYSTEM` |
| Message 유형 | `QUESTION`, `ANSWER_VOICE`, `ANSWER_OPTION`, `SYSTEM` |
| 리포트 상태 | `GENERATING`, `COMPLETED`, `FAILED`, `HIDDEN` |
| PDF 상태 | `NONE`, `GENERATING`, `READY`, `FAILED` |
| 신고 대상 | `REPORT`, `POST`, `COMMENT` |
| 신고 상태 | `PENDING`, `REVIEWING`, `RESOLVED`, `REJECTED` |
| 알림 유형 | `REPORT_COMPLETED`, `ANALYSIS_FAILED`, `RISK_SIGNAL`, `COMMUNITY_COMMENT`, `EXPERT_ANSWER`, `NOTICE` |

## 8. 현재 코드와의 불일치 및 후속 조치

다음 항목은 ERD v1.1을 Runtime DB에 적용하기 전에 반드시 코드와 API 명세를 함께 정렬해야 한다.

1. 현재 Java의 그림 Session 상태는 `IN_PROGRESS` 중심이고 v1.1은 공통 규약의 세부 상태를 사용한다. Entity Enum, Service 상태 전이, API 예시를 동시에 수정해야 한다.
2. 현재 Java의 질문 난이도는 `LOWER_ELEMENTARY`, `UPPER_ELEMENTARY`, `SUPPORT`를 사용하지만 v1.1은 최신 문서의 `ELEMENTARY`, `DEVELOPMENTAL_SUPPORT`, `CUSTOM`을 사용한다.
3. 기존 공통 성공·오류 응답 구현은 첨부 API 공통 규약의 Envelope 없는 성공 응답 및 오류 Code 이름 규칙과 다르다. Storage·ERD 작업에서 전역 응답을 임의 수정하지 않는다.
4. 공통 파일 규약은 PNG/JPEG만 허용한다. WEBP 지원 여부를 다시 열려면 API 명세, Storage 검증과 APP 업로드 제한을 함께 변경한다.
5. `sender_type`은 공통 규약의 AI/CHILD 두 값보다 기능 요구사항의 보호자 도움·시스템 Message를 보존하기 위해 네 값을 유지했다. API 응답 노출 범위를 확정해야 한다.
6. `community_posts.post_type`, `question_purpose`, `activity_templates.activity_type`, 캐릭터 Code는 문서 간 최종 열거값이 부족해 현재 V1 또는 자유 Code를 유지했다.
7. `notification_settings_json`, 리포트 JSON과 AI `risk_response_json`은 API 예시가 첫 Schema다. BE·AI·APP 합의 후 Version이 있는 JSON Schema로 고정해야 한다.
8. 이메일 인증을 Redis로만 운영하기로 결정하면 `email_verifications`는 Target Model에서 제외할 수 있다.

## 9. ERD 보강 57건 처리 기준

### DDL에 반영

- 가입 중 역할 미정, 사용자 Soft Delete·휴면, Refresh Token RTR, 이메일 인증, 데이터 내보내기
- 동의 Code·대상 범위·철회 안내·최신 이력 조회 Index
- 튜토리얼 진행 정보, 질문 난이도, 보호자 관계 유형
- 그림 선택 주체, 자산 오브젝트·Stroke 동기화 순번, Session 상태, Preview 오탈자
- 대화 Session UNIQUE·상태·난이도·캐릭터 Snapshot, 음성 Checksum·TTS 변형 Cache
- 신고, PDF 생성 상태, Storage 비동기 삭제, Push 기기 Token, 미술 활동 자료
- 분석·알림 상태 Code와 주요 Template Code

### Column을 추가하지 않는 것이 정상

- 아동 중복 등록은 보호자 관계와 닉네임·생년월일을 Service에서 조회한다. 아동은 여러 보호자와 연결될 수 있어 `children` 단독 UNIQUE로 강제하지 않는다.
- 알림 “모두 읽음”은 수신자의 미확인 행에 `read_at`을 일괄 갱신하는 API 동작이므로 별도 Column이 필요 없다.
- 게시글 좋아요·댓글 수와 `likedByMe`는 관계 Table 집계·사용자별 조회 결과다.
- 관리자 Dashboard 수치는 현재 실시간 집계값이다. 성능 문제가 측정되기 전 집계 Table을 만들지 않는다.
- 전문가 자격 변경 시 `verification_status=PENDING` 전환은 Service 상태 전이이며 별도 Column이 필요 없다.
- 커뮤니티 Notion Domain Select 옵션은 협업 도구 Metadata 문제로 DB DDL 대상이 아니다.
- 위험 신호는 `analysis_observation_results.attention_points`와 리포트 JSON에 저장하되 보호자 전용 DTO·인가에서 노출을 제한한다.

### 팀 합의 전 보류

- 캐릭터 Code Master Table 도입 여부
- 대화 종료 사유와 음성 녹음 종료 조건을 분석 지표로 영속화할지 여부
- 게시글·질문 목적·미술 활동 유형의 최종 Code 목록
- 리포트·알림 설정·위험 대응 JSON의 필수 Key와 Schema Version
- Local 이메일 인증을 DB와 Redis 중 어디에 저장할지
- 대시보드 성능 측정 후 집계 Table 또는 Materialized 집계 방식 도입 여부

## 10. Migration 적용 원칙

- 이미 공유 환경에 적용된 V1은 수정하지 않는다.
- 이 문서의 모든 변경을 한 번에 Runtime DB에 적용하지 않는다.
- 상태 Code 변경은 기존 데이터 변환과 Java Enum 배포 순서를 포함한 별도 Migration으로 분리한다.
- 신규 Table은 실제 API Jira 범위별 Migration으로 나눈다.
- FK로 연결된 Object Storage 삭제는 DB Transaction과 분리하고 `storage_deletion_jobs`로 추적한다.
- Migration 전 MySQL 8.4 Testcontainers로 FK, CHECK, Index와 삭제 정책을 재검증한다.
