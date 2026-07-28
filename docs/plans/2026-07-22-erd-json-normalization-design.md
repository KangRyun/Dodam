# ERDCloud Export 기반 관계형 스키마 재설계

## 1. 목적

팀이 ERDCloud에서 Export한 28개 테이블 SQL을 기준 원본으로 삼아 다음 문제를 해결한다.

- 24개 JSON 컬럼을 검색·검증 가능한 관계형 테이블로 분리한다.
- Refresh Token은 MySQL이 아니라 Redis에서 TTL과 회전 정책으로 관리하므로 `refresh_tokens` 테이블을 제거한다.
- Export SQL에 빠진 FK, UNIQUE, CHECK, INDEX, `AUTO_INCREMENT`와 일관된 시간 정밀도를 보강한다.
- API 명세와 다른 물리명·오탈자·중복 저장 구조를 바로잡는다.
- ERDCloud Import용 전체 SQL, 프로젝트용 Flyway 변경 SQL, 전체 테이블 명세가 같은 구조를 설명하게 한다.

이번 작업은 DB 구조와 문서 정합성까지를 범위로 한다. Redis 연동 코드, 인증 API 구현, API 공통 응답 형식 변경은 포함하지 않는다.

## 2. 입력 자료와 우선순위

설계 판단에는 다음 순서를 적용한다.

1. 팀 ERDCloud 최신 Export SQL
2. 아동 그림·대화 서비스 API 전체 명세서 v1.0
3. API 공통 규약, ERD 보강 필요 목록, API–ERD 정합성 검증 보고서
4. 현재 `V1__create_initial_schema.sql`과 구현된 Java Entity
5. 기존 `erd-cloud-schema-v1.1` 제안 문서

문서가 충돌하면 최신 팀 결정과 실제 API 계약을 우선하며, 결정되지 않은 내용은 임의 기능으로 확정하지 않고 명세의 보류·후속 항목으로 기록한다.

## 3. 검토한 대안

### 3.1 모든 JSON을 범용 Key-Value로 변환

테이블 수는 줄지만 타입, FK, 필수값, 값 범위를 DB가 보장하지 못한다. Java 코드도 문자열 파싱과 형 변환에 계속 의존하므로 JSON 컬럼을 제거하는 목적을 충분히 달성하지 못한다.

### 3.2 모든 JSON 형태를 완전한 전용 테이블로 변환

무결성은 가장 강하지만 감사 로그, 알림 부가 정보, 커뮤니티 템플릿처럼 구조가 본질적으로 가변적인 데이터까지 기능별 테이블로 분기해야 한다. 신규 리소스나 템플릿 항목이 생길 때마다 스키마 변경이 필요하다.

### 3.3 고정 업무 데이터는 전용 테이블, 가변 데이터는 도메인 한정 속성 테이블로 변환

채택안이다. 선택지, 감정, Stroke, 자격 증빙처럼 계약이 고정된 데이터는 타입이 명확한 전용 테이블을 사용한다. 감사 로그 등 가변 데이터에는 해당 도메인 밖에서 재사용하지 않는 제한된 속성 테이블을 사용한다. 범용 EAV 플랫폼은 만들지 않는다.

## 4. 공통 물리 설계 규칙

- DBMS는 MySQL 8.0, 문자셋은 `utf8mb4`, 정렬 규칙은 `utf8mb4_0900_ai_ci`를 사용한다.
- 식별 PK는 `BIGINT AUTO_INCREMENT`를 사용한다.
- 시간은 `DATETIME(6)`로 통일하고 서버가 생성하는 시각은 `CURRENT_TIMESTAMP(6)`을 기본값으로 사용한다.
- 비율·정규화 좌표는 범위 CHECK를 둔다. 개수·크기·기간은 음수가 되지 않도록 CHECK를 둔다.
- 상태와 코드값은 API 명세에서 확정된 값만 CHECK로 제한한다. 문서 간 값이 충돌하거나 팀 합의가 필요한 값은 명세에 후보를 기록하되 성급한 CHECK를 추가하지 않는다.
- FK 컬럼에는 조회 방향을 고려한 INDEX를 둔다. 복합 UNIQUE의 선두 컬럼과 중복되는 단일 INDEX는 만들지 않는다.
- 생성 이력이나 법적 증빙은 `RESTRICT`, 부모와 생명주기를 완전히 공유하는 상세 행은 `CASCADE`, 작성자 탈퇴 후 보존할 콘텐츠의 작성자 FK는 `SET NULL`을 기본으로 한다.
- soft delete 대상은 상태값과 `deleted_at`을 함께 사용한다.
- 스토리지에는 영속 식별자인 `storage_key`를 저장한다. 만료되는 presigned URL을 영구 식별자로 사용하지 않는다.
- 민감 원문과 Token 원문은 감사 로그나 속성 테이블에 저장하지 않는다.

## 5. JSON 컬럼 분리 설계

### 5.1 사용자·아동

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `users.notification_settings_json` | `user_notification_settings` | 사용자당 1행 | 설정 키가 고정된 Boolean 값이므로 컬럼 단위 기본값과 NOT NULL을 보장한다. |
| `children.response_modes_json` | `child_response_modes` | 아동당 여러 응답 방식 | 응답 방식 중복을 UNIQUE로 차단하고 허용 코드와 우선순위를 관리한다. |

`user_notification_settings`는 현재 전체 API 명세의 네 설정인 `analysis_completed`, `community`, `service_notice`, `marketing`을 기준으로 한다. 이전 보강 문서의 `pushEnabled`, `reportCreated` 등은 최신 전체 명세와 충돌하므로 별도 컬럼으로 확정하지 않는다.

### 5.2 전문가

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `expert_profiles.specialties_json` | `expert_profile_specialties` | 전문가당 여러 전문 분야 | 필터·검색 대상이며 중복 전문 분야를 방지해야 한다. |
| `expert_profiles.credentials_json` | `expert_credentials`, `expert_credential_files` | 자격 여러 건, 자격별 증빙 파일 여러 건 | 자격별 검증 상태와 증빙 파일을 독립적으로 추적하고 변경 시 재검증할 수 있어야 한다. |

`expert_credentials`는 자격명, 발급기관, 자격번호, 취득일, 만료일, 검증 상태를 관리한다. 증빙은 URL 대신 `storage_key`와 파일 메타데이터를 별도 행으로 저장한다.

### 5.3 그림 Stroke

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `stroke_batches.payload_json` | `stroke_events`, `stroke_event_points`, 배치의 metric delta 컬럼 | 배치당 이벤트 여러 건, 이벤트당 좌표 여러 건 | 이벤트·좌표 순서, 좌표 범위, 필압, 도구와 batch 범위를 DB에서 검증하고 분석 쿼리에서 JSON 파싱을 제거한다. |

`stroke_batches`에는 `payload_checksum_sha256`, `undo_count_delta`, `redo_count_delta`, `erase_count_delta`, `pause_duration_ms_delta`를 둔다. `stroke_events`는 `event_sequence`, `event_type`, `tool`, `color`, `width`, `pressure`를 보관한다. `stroke_event_points`는 `point_sequence`, `x`, `y`, `elapsed_ms`를 보관한다.

다음 무결성을 보장한다.

- `(drawing_session_id, batch_sequence)` UNIQUE
- `(stroke_batch_id, event_sequence)` UNIQUE
- `(stroke_event_id, point_sequence)` UNIQUE
- `first_event_sequence <= last_event_sequence`
- `x`, `y`, `pressure`는 0 이상 1 이하
- 동일 batch sequence의 재요청은 checksum 비교로 멱등 처리

### 5.4 동의·감사·알림의 가변 데이터

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `consent_records.evidence_json` | `consent_record_evidences` | 동의 기록당 증빙 항목 여러 건 | 약관 버전, 화면/문서 식별자, client timestamp 같은 증빙을 항목별로 보존한다. |
| `audit_logs.resource_snapshot_json`, `before_json`, `after_json` | `audit_log_changes` | 감사 로그당 변경 필드 여러 건 | 대상 리소스마다 다른 필드를 하나의 감사 이벤트 안에서 전후 비교하되 범용 업무 저장소로 사용하지 않는다. |
| `notifications.data_json` | `notification_attributes` | 알림당 부가 속성 여러 건 | 알림 유형별 선택 부가값만 격리한다. 핵심 연결은 기존 `related_*_id` FK를 사용한다. |

`audit_log_changes`는 `field_path`, `value_type`, `snapshot_value`, `before_value`, `after_value`, `is_masked`를 가진다. 값은 감사 표시용 문자열이며 이 테이블을 검색 조건이나 업무 상태의 원본으로 사용하지 않는다. 비밀번호, Token, 아동 음성·대화 원문, 이미지 원본은 저장하지 않고 `is_masked=true`와 마스킹된 설명만 허용한다.

`notification_attributes`도 알림 표시·이동에 필요한 비민감 문자열만 허용한다. 게시글·리포트·그림 세션처럼 FK로 표현 가능한 값은 속성으로 중복 저장하지 않는다.

### 5.5 AI 질문과 대화

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `ai_question_templates.risk_response_json` | `ai_question_template_risk_responses` | 템플릿당 최대 1행 | 활성 여부와 보호자 안내 템플릿의 필수 조건을 보장한다. |
| `ai_question_templates.options_json` | `ai_question_template_options` | 템플릿당 선택지 여러 건 | 선택지 ID·유형·값·표시 순서를 검증한다. |
| `conversation_messages.options_json` | `conversation_message_options` | 질문 메시지당 선택지 여러 건 | 템플릿이 수정되어도 실제 노출된 선택지 snapshot을 보존한다. |
| `conversation_messages.selected_response_json` | `conversation_message_selected_options` | 답변 메시지당 선택 항목 여러 건 | 질문에 존재한 선택지만 참조하도록 하고 표시 문구 snapshot을 보존한다. |
| `conversation_messages.target_object_json`, `bounding_box` | `conversation_message_targets` | 질문 메시지당 최대 1행 | 대상 객체와 Bounding Box의 중복·불일치를 제거하고 탐지 객체 FK를 연결한다. |

선택형 답변은 복수 선택을 허용하므로 단일 selected option FK가 아니라 `conversation_message_selected_options`를 사용한다. 이 테이블은 답변 메시지, 질문 메시지 option, `label_snapshot`, 선택 순서를 기록한다. `conversation_messages.parent_message_id`는 답변이 어떤 질문에 대한 것인지 나타낸다.

`conversation_message_targets`는 `detected_object_id`, 객체 코드·이름 snapshot, `bbox_x`, `bbox_y`, `bbox_width`, `bbox_height`를 보관한다. 원본 탐지 행이 유지되는 동안 FK로 연결하고, 질문 이력 보존을 위해 snapshot도 함께 둔다.

### 5.6 그림 감정

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `drawing_sessions.selected_emotions_json` | `drawing_session_emotions` | 세션당 여러 감정 | 허용 감정, 중복, 선택 순서를 보장하고 활동별 감정 집계를 지원한다. |

감정 코드는 최신 전체 API 명세의 `HAPPY`, `SAD`, `ANGRY`, `SCARED`, `CALM`, `UNKNOWN`을 기준으로 한다. 보강 문서의 `JOY`, `SADNESS`, `ANGER`, `FEAR`, `UNSURE`와 충돌하므로 API 문서 통합 시 별도 정리가 필요하다.

### 5.7 리포트

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `reports.activity_summary_json` | `report_activity_summaries`, `report_activity_notes` | 리포트당 요약 1행, 주의사항 여러 건 | 객관적 활동 수치를 타입이 있는 컬럼으로 보존한다. |
| `reports.observed_features_json` | `report_observed_features` | 리포트당 관찰 항목 여러 건 | 관찰 문장, 근거, 표시 순서와 전문가 공개 범위를 분리한다. |
| `reports.key_conversations_json` | `report_key_conversations` | 리포트당 주요 대화 여러 건 | 질문·답변 메시지를 FK로 연결하고 화면 snapshot을 보존한다. |
| `reports.evidence_json` | `report_evidence_references`, `report_evidence_authors` | 리포트당 근거 여러 건 | RAG 출처와 chunk hash를 구조화하고 저자 목록을 정규화한다. |
| `reports.follow_up_json` | `report_follow_up_guides` | 리포트당 후속 안내 여러 건 | 안내 문장과 상세 설명, 노출 순서를 관리한다. |
| `reports.guardian_questions_json` | `report_guardian_questions` | 리포트당 보호자 질문 여러 건 | 질문 문장과 목적, 순서를 별도 관리한다. |

보호자 응답에는 객관적 활동 사실과 대화 안내만 제공한다. `observed_emotion`, `emotion_confidence`, 검토 전 `attention_points` 등은 전문가 검토 범위로 제한한다. 리포트에는 `limitations_text`를 항상 유지한다.

RAG 근거는 `source_id`, `title`, `published_year`, `section`, `evidence_type`, `applicability`, `limitations`, `knowledge_base_version`, `retrieved_chunk_hash`를 저장한다. 저자는 순서가 있는 `report_evidence_authors` 행으로 분리한다.

### 5.8 커뮤니티

| 기존 컬럼 | 신규 구조 | 관계 | 분리 이유 |
| --- | --- | --- | --- |
| `community_posts.template_data_json` | `community_post_template_fields` | 게시글당 템플릿 항목 여러 건 | 게시글 유형별 선택 입력을 격리하되 분석·대화·리포트 데이터를 연결하지 못하게 한다. |

템플릿 필드는 `field_code`, `value_type`, `value_text`, `display_order`만 허용한다. 커뮤니티 격리 원칙에 따라 child, drawing session, analysis, conversation, report FK를 두지 않는다.

## 6. Refresh Token 저장 결정

- 최종 MySQL 스키마에 `refresh_tokens` 테이블을 두지 않는다.
- Refresh Token 원문과 hash는 관계형 DB에 저장하지 않는다.
- Redis Key는 사용자·로그인 세션을 식별할 수 있는 서버 내부 ID 기반으로 구성하고 Token 원문을 Key에 포함하지 않는다.
- TTL은 Refresh Token 만료와 일치시킨다.
- RTR은 새 Token 발급 시 기존 세션 값을 원자적으로 교체하고, 재사용이 감지되면 해당 Token family 또는 사용자 세션을 폐기한다.
- 로그아웃·회원 정지·탈퇴 시 관련 Redis 세션을 삭제한다.
- Redis 장애 시 재발급을 허용하는 fail-open 정책을 사용하지 않는다.

기존 API 문서의 `refresh_tokens.token_hash`, `revoked_at`, `last_used_at` 참조는 Redis 기반 계약으로 수정해야 한다.

## 7. Export SQL에서 함께 수정할 구조 오류

- `analysis_detected_objects.drawing_image_id`를 `drawing_asset_id`로 변경한다.
- `conversation_sessions.conversation_id`를 `drawing_session_id`로 변경하고 세션당 대화 1개 UNIQUE를 둔다.
- `analysis_behavior_features.tool_chnage_count`를 `tool_change_count`로 변경한다.
- `analysis_conversation_summaries.conversation_sumaary_id`를 `conversation_summary_id`로 변경한다.
- `expert_follows.Key`를 삭제하고 PK는 `id`, 중복 방지는 `(guardian_user_id, expert_profile_id)` UNIQUE로 처리한다.
- `conversation_messages.bounding_box`와 `target_object_json`을 `conversation_message_targets`로 통합한다.
- `expert_profiles.users_id`를 프로젝트 네이밍에 맞춰 `user_id`로 변경하고 사용자당 전문가 프로필 1개 UNIQUE를 둔다.
- 모든 PK에 `AUTO_INCREMENT`, 모든 관계에 FK를 추가한다.
- Export의 `DATETIME`을 `DATETIME(6)`로 통일한다.
- `users.deleted_at`을 추가하여 `account_status='DELETED'`와 soft delete 시점을 함께 관리한다.
- `drawing_sessions.idempotency_key`를 추가하여 현재 생성 API와 Java Entity의 멱등 계약을 유지한다.
- `drawing_assets.last_event_sequence`, `object_code`를 추가하여 draft 복구와 다중 객체 업로드를 식별한다.
- `conversation_messages.audio_checksum_sha256`, STT confidence 및 보호자 확인 필요 여부를 반영한다.

## 8. 기존 v1.1 보강 테이블 처리

이전 제안 중 API 구현에 직접 필요한 다음 테이블은 최종 기준 SQL에 유지한다.

- `email_verifications`: Redis 전환 여부가 확정되지 않은 이메일 인증 이력
- `data_export_jobs`: 사용자 데이터 내보내기 비동기 상태
- `conversation_message_audio_variants`: TTS voice·speed별 캐시
- `complaints`, `complaint_actions`: 게시글·댓글·리포트 신고 및 처리 이력
- `notification_device_tokens`: 푸시 기기 Token
- `activity_templates`, `activity_template_attachments`: 전문가 미술 활동 자료와 첨부 파일. 기존 제안의 `attachment_keys_json`도 JSON 0개 원칙에 따라 별도 행으로 분리한다.
- `storage_deletion_jobs`: 오브젝트 스토리지 비동기 삭제 추적

`refresh_tokens`만 제거한다. 아직 API와 정책이 확정되지 않은 상담 공유·전문가 리뷰 확장 테이블은 이번 기준 SQL에 임의로 추가하지 않는다.

## 9. Flyway 적용 전략

ERDCloud Import SQL은 신규 환경을 위한 완전한 기준 스키마로 작성한다. 프로젝트에서는 이미 공유됐을 수 있는 V1 checksum을 바꾸지 않고 후속 Migration을 사용한다.

1. V3 시작 시 `refresh_tokens` 행과 V1에 남은 23개 JSON 컬럼의 비어 있지 않은 값을 검사한다. ERDCloud Export의 별도 `bounding_box`는 V1에서 이미 `target_object_json`에 통합되어 있다.
2. 기존 Token 또는 JSON 업무 데이터가 발견되면 DDL 실행 전에 즉시 중단한다.
3. 검사를 통과한 초기 개발 DB에 신규 관계형 테이블과 필요한 신규 컬럼을 생성한다.
4. JSON 컬럼과 빈 `refresh_tokens` 테이블을 제거한다.
5. FK, UNIQUE, CHECK, INDEX를 적용한다.

현재 V3는 초기 개발 단계의 비어 있는 JSON 저장 구조만 전환한다. 기존 데이터 형태를 추측해 자동 변환하지 않으며, 데이터가 있는 환경은 Redis 이관 또는 세션 만료와 JSON 구조별 데이터 변환 Migration을 V3보다 먼저 적용해야 한다. 운영 데이터가 없는 개발 환경은 clean migration으로 재생성할 수 있다.

## 10. Java 코드 영향

- 현재 구현된 `Child`, `DrawingSession`은 제거 대상 JSON을 직접 매핑하지 않으므로 즉시 컴파일 오류가 발생하지 않는다.
- `DrawingSession.idempotencyKey`와 DB 컬럼은 유지한다.
- 이후 도메인 구현에서는 JSON 문자열이나 `JsonNode` 필드 대신 관계 Entity·Repository를 사용한다.
- Stroke 저장은 batch, event, point를 하나의 Transaction에서 저장하고 batch checksum으로 중복을 판별한다.
- 선택 답변은 질문 option 존재 여부를 검증한 후 snapshot 행을 저장한다.
- Refresh Token Repository/JPA Entity를 만들지 않고 인증 구현 시 Redis 전용 저장소 추상화를 사용한다.
- 현재 공통 응답 envelope 구현과 첨부 API 공통 규약의 “envelope 없음”은 별도 계약 결정이 필요하다. DB 변경에 섞어 수정하지 않는다.
- 현재 일부 Java Javadoc이 콘솔에서 깨져 보이는 문제는 파일 인코딩 또는 PowerShell 출력 인코딩을 별도 점검하며, DB 설계 변경으로 덮어쓰지 않는다.

## 11. 산출물

- `docs/database/erd-cloud-schema-v1.2.sql`: ERDCloud 재등록용 전체 DDL
- `docs/database/erd-cloud-schema-v1.2-spec.md`: 모든 테이블·컬럼·관계·제약·논리명 명세
- `backend/src/main/resources/db/migration/V3__normalize_json_columns.sql`: 현재 V1·V2에서 목표 구조로 전환하는 Flyway Migration
- 본 설계 문서: 결정 근거와 코드 영향

기존 v1.1 파일은 비교 기록으로 유지하며 최종 기준 문서는 v1.2로 명확히 구분한다.

## 12. 검증 기준

- ERDCloud용 SQL에 `JSON` 타입과 `refresh_tokens` 테이블이 없어야 한다.
- 모든 테이블에 PK가 있고 관계 컬럼에는 유효한 FK가 있어야 한다.
- FK가 참조하는 컬럼 타입과 signed 여부가 일치해야 한다.
- UNIQUE·CHECK·INDEX 이름이 중복되지 않아야 한다.
- MySQL 8.0에서 전체 DDL과 Flyway Migration이 성공해야 한다.
- `SELECT COUNT(*)` 기준으로 기대한 테이블 수와 생성된 테이블 수가 일치해야 한다.
- `information_schema`에서 JSON 컬럼 0개, orphan FK 0개를 확인해야 한다.
- `clean test`, `spotlessCheck`, `javadoc`을 실행해 현재 Java 코드와 Migration의 충돌이 없어야 한다.
- 전체 명세의 모든 물리 테이블이 SQL에 존재하고 SQL의 모든 테이블이 명세에 설명되어야 한다.
- 한글 COMMENT와 Markdown이 UTF-8로 정상 표시되어야 한다.

## 13. 명시적 비범위 및 후속 합의 항목

- Redis client 설정과 Refresh Token 발급·회전 코드 구현
- API 공통 성공·오류 envelope 계약 변경
- API 문서 간 enum 충돌의 전면 개정
- 상담 요청, 리포트 공유, 전문가 리뷰 도메인의 신규 기능 구현
- 임의의 진단·위험 점수 컬럼 추가

위 항목은 이번 스키마가 방해하지 않도록 확장 가능성을 유지하되, 구현된 기능처럼 DDL에 선반영하지 않는다.

## 14. 2026-07-28 HTP·그림일기 확장 기준

이번 출시 활동은 `HTP`와 `ART_DIARY`로 제한한다. 이 결정은 기존 정규화 원칙을 바꾸지 않으며, 활동별 신규 구조는 후속 Flyway Migration으로만 추가한다.

### HTP

- HTP는 `HOUSE`, `TREE`, `PERSON` 세 단계와 세 개의 `drawing_sessions`를 하나의 묶음으로 관리한다.
- 단계 주제의 정본은 신규 `htp_assessment_steps.drawing_subject`다.
- `drawing_assets.object_code`는 다중 객체 업로드 식별 목적으로 만들어진 nullable 컬럼이므로 HTP 주제 저장에 재사용하지 않는다.
- `UNIQUE (htp_assessment_id, step_order)`, `UNIQUE (htp_assessment_id, drawing_subject)`, `UNIQUE (drawing_session_id)`로 중복 단계를 방지한다.
- `drawing_subject`는 `HOUSE`, `TREE`, `PERSON`만 허용한다.

### 그림일기

- 그림일기는 기존 `drawing_sessions` 한 건과 FINAL 자산 한 건을 중심으로 구성하므로 별도 활동 묶음 테이블을 만들지 않는다.
- 시작 전·종료 후 감정 2회 저장안은 이번 출시에서 제외한다. 기존 세션당 Reflection 1회 구조를 유지한다.
- `FREE_DRAWING`, `EMOTION_COLORING`, `WEATHER_MIND` 기준 데이터는 과거 참조를 위해 삭제하지 않고 비활성화한다.

세부 계약은 `2026-07-28-htp-service-contract.md`와 `2026-07-28-art-diary-service-contract.md`를 따른다.
