# 초기 데이터베이스 스키마 설계

## 기준과 사용 방법

이 문서는 Jira `S15P11B209-132`에서 구성한 MySQL 8.4.10 초기 스키마의 논리명, 물리명과 관계 설계를 설명한다. 실행 스키마와 ERDCloud Import의 단일 기준은
`backend/src/main/resources/db/migration/V1__create_initial_schema.sql`이다.

ERDCloud에는 위 Migration 파일 전체를 SQL Import한다. 모든 Table과 Column의 `COMMENT`에 한국어 논리명을 기록했으므로 영문 `snake_case` 물리명과 함께 확인할 수 있다. Flyway가 이미 적용한 Migration은 수정하지 않고, 이후 변경은 새 버전의 Migration으로 추가한다.

## 공통 물리 규칙

- MySQL 8.4 문법, InnoDB, `utf8mb4`, `utf8mb4_0900_ai_ci`를 사용한다.
- 식별 PK는 `BIGINT NOT NULL AUTO_INCREMENT`를 사용한다.
- 시각 정보는 `DATETIME(6)`으로 통일하며 `updated_at`은 행 수정 시 자동 갱신한다.
- 제약조건과 Index는 `pk_`, `fk_`, `uk_`, `ck_`, `idx_` 접두사를 사용한다.
- MySQL은 사용자 지정 Primary Key 이름을 메타데이터에서 `PRIMARY`로 표시한다.
- 상태값은 API 명세에서 값이 확정된 경우 `CHECK`로 제한하고, 미확정 값은 임의로 고정하지 않는다.
- 구조가 확정된 목록과 Snapshot만 JSON으로 저장한다. 검색·관계·무결성 기준값은 일반 Column과 FK로 관리한다.

## 논리명과 물리명

### 사용자 및 동의

| 논리명 | 물리명 | 주요 책임 |
| --- | --- | --- |
| 사용자 | `users` | 보호자·전문가·관리자 계정의 공통 정보 |
| 아동 | `children` | 활동 대상 아동 Profile |
| 그림 활동 유형 | `drawing_types` | 활동 코드와 노출 기준 |
| 동의 약관 | `consent_terms` | 약관 버전과 시행 정보 |
| 인증 계정 | `auth_accounts` | Local 및 OAuth 인증 식별자 |
| Refresh Token | `refresh_tokens` | Token Hash와 폐기 상태 |
| 전문가 Profile | `expert_profiles` | 전문가 공개 정보와 검증 상태 |
| 전문가 Follow | `expert_follows` | 보호자의 전문가 Follow 관계 |
| 보호자-아동 관계 | `guardian_child_relations` | 아동 접근 권한의 관계 근거 |
| 동의 이력 | `consent_records` | 동의·철회 증빙 이력 |

### 그림 활동 및 대화

| 논리명 | 물리명 | 주요 책임 |
| --- | --- | --- |
| 그림 활동 Session | `drawing_sessions` | 아동 그림 활동의 생명주기와 현재 단계 |
| Stroke Batch | `stroke_batches` | Canvas 입력 Event의 순차 Batch |
| 그림 파일 | `drawing_assets` | 원본·중간·최종 그림 File Metadata |
| AI 질문 Template | `ai_question_templates` | 연령·난이도별 질문 후보 |
| 대화 Session | `conversation_sessions` | 그림 활동에 연결된 대화 진행 상태 |
| 대화 Message | `conversation_messages` | AI·아동·보호자 Message와 응답 데이터 |

### 분석 및 리포트

| 논리명 | 물리명 | 주요 책임 |
| --- | --- | --- |
| 분석 | `analyses` | 분석 요청·재시도·실행 상태 |
| 분석 시각 특징 | `analysis_visual_features` | 색상·배치·선 등 정량 시각 특징 |
| 분석 행동 특징 | `analysis_behavior_features` | Stroke·정지·도구 변경 등 행동 특징 |
| 분석 탐지 객체 | `analysis_detected_objects` | 그림 Asset에서 탐지한 객체와 Bounding Box |
| 분석 관찰 결과 | `analysis_observation_results` | 관찰 요약과 전문가 검토 정보 |
| 분석 제외 입력 | `analysis_unused_inputs` | 분석에서 제외된 입력과 사유 |
| 대화 분석 요약 | `analysis_conversation_summaries` | 대화 주제·발화·응답 요약 |
| 리포트 | `reports` | 보호자용 활동 관찰 리포트 Version |

### 커뮤니티 및 운영

| 논리명 | 물리명 | 주요 책임 |
| --- | --- | --- |
| 커뮤니티 게시글 | `community_posts` | 보호자·전문가 콘텐츠 |
| 댓글 | `comments` | 게시글 댓글 |
| 게시글 좋아요 | `post_likes` | 사용자별 게시글 좋아요 |
| 알림 | `notifications` | 사용자 알림과 전송 상태 |
| 감사 Log | `audit_logs` | 주요 Resource 변경 이력 |

## Preview 보완 사항

| Preview | 적용 결과 | 이유 |
| --- | --- | --- |
| `conversation_sessions.conversation_id` | `drawing_session_id` | 실제 참조 대상이 그림 활동 Session |
| `analysis_detected_objects.drawing_image_id` | `drawing_asset_id` | 존재하는 File Table인 `drawing_assets` 참조 |
| `analysis_behavior_features.tool_chnage_count` | `tool_change_count` | 오탈자 수정 |
| `analysis_conversation_summaries.conversation_sumaary_id` | `conversation_summary_id` | 오탈자 수정 |
| `expert_follows.Key`, `(id, Key)` PK | `Key` 제거, PK `id` | 의미 없는 Column과 복합 PK 제거 |
| `conversation_messages.bounding_box` | `target_object_json.boundingBox` | 같은 정보의 중복 저장 방지 |
| PK 자동 증가 없음 | 29개 PK에 `AUTO_INCREMENT` | 식별자 생성 방식 통일 |
| FK·Unique·Index 없음 | 명시적 제약조건 추가 | 관계 무결성과 중복 방지, 조회 지원 |

`analysis_observation_results.observed_emotion`과 `emotion_confidence`는 Preview를 유지하되 전문가 내부 초안에만 사용한다. 보호자에게 진단 결과처럼 노출하지 않는다.

## 핵심 관계와 삭제 정책

### `ON DELETE CASCADE`

부모 없이 독립적으로 유지할 의미가 없는 종속 데이터에 적용한다.

- 사용자 → 인증 계정, Refresh Token, 보호자-아동 관계, 전문가 Follow, 알림
- 그림 활동 Session → Stroke Batch, 그림 파일, 대화 Session, 분석
- 대화 Session → 대화 Message
- 분석 → 시각 특징, 행동 특징, 탐지 객체, 관찰 결과, 제외 입력, 대화 분석 요약
- 게시글 → 댓글, 좋아요

### `ON DELETE RESTRICT`

삭제 전에 이력 정리 또는 Soft Delete가 필요한 핵심 기록에 적용한다.

- 사용자 → 전문가 Profile
- 아동·그림 활동 유형 → 그림 활동 Session
- 동의 약관 → 동의 이력
- 그림 활동 Session·분석 → 리포트

### `ON DELETE SET NULL`

선택 참조가 사라져도 본문 이력을 보존해야 하는 Nullable FK에 적용한다.

- 그림 활동 시작 사용자, 질문 Template 작성·수정 사용자
- 대화 Message의 상위 Message와 질문 Template
- 분석 재시도 원본, 대화 분석 요약의 대화 Session
- 게시글·댓글 작성자
- 알림 관련 게시글·리포트·그림 활동 Session
- 감사 Log 처리 사용자, 동의 처리 사용자·대상 아동

## Unique 제약

| 제약조건 | 대상 Column | 목적 |
| --- | --- | --- |
| `uk_auth_accounts_provider_subject` | `provider`, `provider_subject` | 인증 Provider 식별자 중복 방지 |
| `uk_auth_accounts_local_login_email` | `local_login_email` | Local 계정 Email 중복 방지 |
| `uk_stroke_batches_session_sequence` | `drawing_session_id`, `batch_sequence` | Session별 Batch 순번 보장 |
| `uk_guardian_child_relations_guardian_child` | `guardian_user_id`, `child_id` | 관계 중복 방지 |
| `uk_analyses_idempotency_key` | `idempotency_key` | 분석 요청 멱등성 보장 |
| `uk_conversation_messages_session_sequence` | `conversation_session_id`, `message_sequence` | 대화 순번 보장 |
| `uk_post_likes_post_user` | `post_id`, `user_id` | 중복 좋아요 방지 |
| `uk_expert_follows_guardian_expert` | `guardian_user_id`, `expert_profile_id` | 중복 Follow 방지 |
| `uk_reports_session_version` | `drawing_session_id`, `report_version` | Session별 리포트 Version 보장 |
| `uk_expert_profiles_users_id` | `users_id` | 사용자당 전문가 Profile 하나 보장 |
| `uk_drawing_types_code` | `code` | 활동 코드 중복 방지 |
| `uk_consent_terms_code_version` | `term_code`, `version` | 약관 Version 중복 방지 |

MySQL에는 부분 Unique Index가 없으므로 `auth_accounts.local_login_email`은 `provider='LOCAL'`일 때만 `login_email`을 반환하는 Stored Generated Column이다. 다른 Provider는 `NULL`이어서 같은 Email을 공유할 수 있다.

## 주요 조회 Index

- 아동별 그림 활동: `idx_drawing_sessions_child_id`
- 그림 활동별 분석: `idx_analyses_drawing_session_id`
- 수신자별 최신 알림: `idx_notifications_recipient_created_at`
- 그림 활동별 리포트: `idx_reports_drawing_session_id`
- 그림 활동별 대화: `idx_conversation_sessions_drawing_session_id`
- 상위 대화 Message: `idx_conversation_messages_parent_message_id`
- 작성자별 댓글·게시글: `idx_comments_author_user_id`, `idx_community_posts_author_created_at`
- Resource별 감사 이력: `idx_audit_logs_resource`

FK Column은 Unique 또는 복합 Index의 선두 Column으로 포함된 경우 해당 Index를 재사용한다.

## JSON Column

- 사용자·아동: `notification_settings_json`, `response_modes_json`
- 전문가·동의: `specialties_json`, `credentials_json`, `evidence_json`
- 그림·대화: `selected_emotions_json`, `payload_json`, `risk_response_json`, `options_json`, `selected_response_json`, `target_object_json`
- 리포트: `activity_summary_json`, `observed_features_json`, `key_conversations_json`, `evidence_json`, `follow_up_json`, `guardian_questions_json`
- 커뮤니티·운영: `template_data_json`, `data_json`, `resource_snapshot_json`, `before_json`, `after_json`

## V1에서 제외한 확장 구조

SQL Preview에 없는 `expert_credentials`, `notification_device_tokens`, `complaints`, `complaint_actions`, `activity_templates`, `consultation_requests`, `consultation_report_shares`, `expert_reviews`, `analysis_evidence_sources`, `expert_review_items`는 생성하지 않았다. 기능과 관계가 확정되면 별도 Jira 이슈의 후속 Flyway Migration으로 추가한다.
