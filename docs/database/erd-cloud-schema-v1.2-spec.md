# ERDCloud 통합 스키마 v1.2 전체 명세

## 1. 문서 목적

팀 ERDCloud Export SQL과 API 명세를 기준으로 관계형 구조를 확정한 문서다. ERDCloud 재등록용 기준 SQL은 [erd-cloud-schema-v1.2.sql](./erd-cloud-schema-v1.2.sql)이며, 프로젝트 전환 Migration은 `V3__normalize_json_columns.sql`이다.

- 대상 DB: MySQL 8.0 이상(검증: MySQL 8.4.10)
- 문자셋/정렬: `utf8mb4` / `utf8mb4_0900_ai_ci`
- 업무 테이블: 62개
- JSON 타입 컬럼: 0개
- Refresh Token 테이블: 없음(Redis 관리)
- 시간 기준: `DATETIME(6)`, API 노출은 UTC ISO-8601

## 2. ERDCloud Import 방법

1. ERDCloud 새 ERD에서 MySQL을 선택한다.
2. `erd-cloud-schema-v1.2.sql` 전체를 Import한다.
3. Import 후 테이블 수 62개와 FK 연결을 확인한다.
4. 이 파일은 신규 환경의 기준 DDL이다. 실행 이력이 있는 프로젝트 DB에는 Flyway V3를 적용한다.

## 3. 핵심 결정

### 3.1 Refresh Token

Refresh Token은 MySQL 테이블에 저장하지 않는다. Redis에서 로그인 세션 식별자, Token family, TTL, 회전 상태를 관리한다. 재발급은 기존 값을 원자적으로 교체하고 재사용 감지 시 관련 세션을 폐기한다. 로그아웃·정지·탈퇴 시 Redis Key를 삭제하며 Redis 장애 시 재발급을 허용하는 fail-open 정책을 사용하지 않는다. V3 적용 전에 기존 `refresh_tokens` 행이 하나라도 있으면 Migration이 중단되므로, Redis 이관 또는 전체 세션 만료 정책을 먼저 수행해야 한다.

### 3.2 JSON 분리 원칙

고정 구조는 타입이 명확한 전용 하위 테이블로 분리한다. 감사·알림·커뮤니티의 가변 값은 해당 도메인에서만 사용하는 속성 테이블로 제한하며 업무 상태의 원본으로 사용하지 않는다.

| 기존 JSON 구조 | 신규 저장 구조 | 분리 이유 |
| --- | --- | --- |
| `users.notification_settings_json` | `user_notification_settings` | 고정 Boolean 설정을 사용자별 1:1 행으로 검증 |
| `children.response_modes_json` | `child_response_modes` | 복수 응답 방식의 중복과 허용 코드 검증 |
| `expert_profiles.specialties_json` | `expert_profile_specialties` | 전문 분야 검색·필터 및 중복 방지 |
| `expert_profiles.credentials_json` | `expert_credentials`, `expert_credential_files` | 자격별 검증 상태와 증빙 파일 이력 분리 |
| `stroke_batches.payload_json` | `stroke_events`, `stroke_event_points` | 이벤트·좌표 순서와 수치 범위 검증 |
| `consent_records.evidence_json` | `consent_record_evidences` | 동의 행위의 증빙 항목 보존 |
| `audit_logs.resource_snapshot_json` | `audit_log_changes.snapshot_value` | 리소스별 가변 Snapshot을 감사 범위로 제한 |
| `audit_logs.before_json` | `audit_log_changes.before_value` | 변경 필드 단위 전 값 보존 |
| `audit_logs.after_json` | `audit_log_changes.after_value` | 변경 필드 단위 후 값 보존 |
| `notifications.data_json` | `notification_attributes` | 비민감 부가값만 격리하고 핵심 관계는 FK 사용 |
| `ai_question_templates.risk_response_json` | `ai_question_template_risk_responses` | 활성 여부와 보호자 안내 필수 조건 검증 |
| `ai_question_templates.options_json` | `ai_question_template_options` | Template 선택지의 식별자·값·순서 검증 |
| `conversation_messages.options_json` | `conversation_message_options` | 실제 노출 선택지 Snapshot 보존 |
| `conversation_messages.selected_response_json` | `conversation_message_selected_options` | 질문 선택지 FK와 선택 당시 문구 보존 |
| `conversation_messages.target_object_json` | `conversation_message_targets` | 탐지 객체와 Bounding Box 통합 |
| `conversation_messages.bounding_box` | `conversation_message_targets` | Export의 중복 Bounding Box 제거(V1에서는 이미 통합) |
| `drawing_sessions.selected_emotions_json` | `drawing_session_emotions` | 감정 코드·중복·선택 순서 검증 |
| `reports.activity_summary_json` | `report_activity_summaries`, `report_activity_notes` | 객관적 활동 수치와 주의사항 분리 |
| `reports.observed_features_json` | `report_observed_features` | 관찰 항목과 공개 범위 관리 |
| `reports.key_conversations_json` | `report_key_conversations` | 질문·답변 메시지 FK와 Snapshot 보존 |
| `reports.evidence_json` | `report_evidence_references`, `report_evidence_authors` | RAG 출처·저자·chunk hash 정규화 |
| `reports.follow_up_json` | `report_follow_up_guides` | 후속 안내 문장과 순서 관리 |
| `reports.guardian_questions_json` | `report_guardian_questions` | 보호자 질문과 목적·순서 관리 |
| `community_posts.template_data_json` | `community_post_template_fields` | 커뮤니티 격리를 유지한 Template 항목 저장 |
| `activity_templates.attachment_keys_json (기존 v1.1 제안)` | `activity_template_attachments` | 새 기준 SQL에 JSON이 다시 유입되지 않도록 첨부 파일별 행으로 분리 |

### 3.3 Export SQL 보정

- conversation_sessions.conversation_id → drawing_session_id
- analysis_detected_objects.drawing_image_id → drawing_asset_id
- analysis_behavior_features.tool_chnage_count → tool_change_count
- analysis_conversation_summaries.conversation_sumaary_id → conversation_summary_id
- expert_follows.Key 제거, (guardian_user_id, expert_profile_id) UNIQUE 적용
- expert_profiles.users_id → user_id
- 모든 식별 PK의 AUTO_INCREMENT, FK, UNIQUE, CHECK, 조회 INDEX 보강
- DATETIME(6)와 한글 COMMENT 통일

## 4. 공통 관계·삭제 정책

- 부모와 생명주기를 공유하는 선택지·좌표·상세 행은 ON DELETE CASCADE를 사용한다.
- 법적 증빙이나 신고 대상처럼 이력을 보존해야 하는 관계는 RESTRICT를 사용한다.
- 콘텐츠는 보존하되 탈퇴 사용자를 분리할 수 있어야 하는 작성자 관계는 SET NULL을 사용한다.
- 장문 storage_key는 utf8mb4 index 한도를 피하기 위해 SHA-256 hash에 UNIQUE를 적용하고 원문 Key를 함께 저장한다.
- 커뮤니티 영역에는 아동·그림·대화·분석·리포트 FK를 두지 않는다.

## 5. 사용자·인증·동의

### 사용자 (`users`)

**역할:** 사용자 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 사용자 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 사용자 ID |
| 사용자 역할 | `role` | `varchar(20)` | N | `-` | - | 사용자 역할 |
| 닉네임 | `nickname` | `varchar(50)` | Y | `-` | - | 닉네임 |
| 계정 상태 | `account_status` | `varchar(20)` | N | `PENDING` | - | 계정 상태 |
| 프로필 이미지 URL | `profile_image_url` | `varchar(1000)` | Y | `-` | - | 프로필 이미지 URL |
| 온보딩 완료 여부 | `is_completed` | `tinyint(1)` | N | `0` | - | 온보딩 완료 여부 |
| 마지막 로그인 일시 | `last_login_at` | `datetime(6)` | Y | `-` | - | 마지막 로그인 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | `-` | - | 계정 탈퇴 처리 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)

**CHECK 제약**

- `ck_users_account_status`: `(`account_status` in (_utf8mb4\'PENDING\',_utf8mb4\'ACTIVE\',_utf8mb4\'SUSPENDED\',_utf8mb4\'DELETED\'))`
- `ck_users_role`: `(`role` in (_utf8mb4\'GUARDIAN\',_utf8mb4\'EXPERT\',_utf8mb4\'ADMIN\'))`

### 인증 계정 (`auth_accounts`)

**역할:** 인증 계정 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 인증 계정 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 인증 계정 ID |
| 사용자 ID | `user_id` | `bigint` | N | `-` | INDEX, FK → users.id | 사용자 ID |
| 인증 제공자 | `provider` | `varchar(20)` | N | `-` | INDEX | 인증 제공자 |
| 인증 제공자 사용자 식별자 | `provider_subject` | `varchar(255)` | N | `-` | - | 인증 제공자 사용자 식별자 |
| 로그인 이메일 | `login_email` | `varchar(255)` | Y | `-` | - | 로그인 이메일 |
| Local 인증 이메일 중복 검사용 생성값 | `local_login_email` | `varchar(255)` | Y | `-` | UNIQUE, STORED GENERATED | Local 인증 이메일 중복 검사용 생성값 |
| 비밀번호 해시 | `password_hash` | `varchar(255)` | Y | `-` | - | 비밀번호 해시 |
| 이메일 인증 일시 | `email_verified_at` | `datetime(6)` | Y | `-` | - | 이메일 인증 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `fk_auth_accounts_user_id`: INDEX (`user_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_auth_accounts_local_login_email`: UNIQUE (`local_login_email`)
- `uk_auth_accounts_provider_subject`: UNIQUE (`provider`, `provider_subject`)

**관계·삭제 정책**

- `fk_auth_accounts_user_id`: `user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_auth_accounts_local_credentials`: `((`provider` <> _utf8mb4\'LOCAL\') or ((`login_email` is not null) and (`password_hash` is not null)))`
- `ck_auth_accounts_provider`: `(`provider` in (_utf8mb4\'LOCAL\',_utf8mb4\'KAKAO\',_utf8mb4\'GOOGLE\',_utf8mb4\'NAVER\'))`

### 이메일 인증 (`email_verifications`)

**역할:** 이메일 인증 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 이메일 인증 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 이메일 인증 ID |
| 인증 계정 ID | `auth_account_id` | `bigint` | N | `-` | INDEX, FK → auth_accounts.id | 인증 계정 ID |
| 인증 코드 Hash | `verification_code_hash` | `char(64)` | N | `-` | - | 인증 코드 Hash |
| 만료 일시 | `expires_at` | `datetime(6)` | N | `-` | - | 만료 일시 |
| 인증 완료 일시 | `verified_at` | `datetime(6)` | Y | `-` | - | 인증 완료 일시 |
| 인증 시도 횟수 | `attempt_count` | `smallint` | N | `0` | - | 인증 시도 횟수 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `idx_email_verifications_account_expires_at`: INDEX (`auth_account_id`, `expires_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_email_verifications_auth_account_id`: `auth_account_id` → `auth_accounts`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_email_verifications_attempt_count`: `(`attempt_count` >= 0)`

### 사용자 알림 설정 (`user_notification_settings`)

**역할:** 사용자 알림 설정 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 사용자 ID | `user_id` | `bigint` | N | `-` | PK, FK → users.id | 사용자 ID |
| 분석 완료 알림 수신 여부 | `analysis_completed` | `tinyint(1)` | N | `1` | - | 분석 완료 알림 수신 여부 |
| 커뮤니티 알림 수신 여부 | `community` | `tinyint(1)` | N | `1` | - | 커뮤니티 알림 수신 여부 |
| 서비스 공지 수신 여부 | `service_notice` | `tinyint(1)` | N | `1` | - | 서비스 공지 수신 여부 |
| 마케팅 알림 수신 여부 | `marketing` | `tinyint(1)` | N | `0` | - | 마케팅 알림 수신 여부 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`user_id`)

**관계·삭제 정책**

- `fk_user_notification_settings_user_id`: `user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION

### 아동 (`children`)

**역할:** 아동 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 아동 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 아동 ID |
| 닉네임 | `nickname` | `varchar(50)` | N | `-` | - | 닉네임 |
| 생년월일 | `birth_date` | `date` | N | `-` | - | 생년월일 |
| 프로필 이미지 URL | `profile_image_url` | `varchar(1000)` | Y | `-` | - | 프로필 이미지 URL |
| 선호 캐릭터 | `preferred_character` | `varchar(50)` | Y | `-` | - | 선호 캐릭터 |
| 질문 난이도 | `question_difficulty` | `varchar(30)` | N | `PRESCHOOL` | - | 질문 난이도 |
| 튜토리얼 상태 | `tutorial_status` | `varchar(20)` | N | `NOT_STARTED` | - | 튜토리얼 상태 |
| 프로필 상태 | `profile_status` | `varchar(20)` | N | `ACTIVE` | - | 프로필 상태 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | `-` | - | 삭제 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)

**CHECK 제약**

- `ck_children_profile_status`: `(`profile_status` in (_utf8mb4\'ACTIVE\',_utf8mb4\'DELETED\'))`
- `ck_children_question_difficulty`: `(`question_difficulty` in (_utf8mb4\'PRESCHOOL\',_utf8mb4\'LOWER_ELEMENTARY\',_utf8mb4\'UPPER_ELEMENTARY\',_utf8mb4\'SUPPORT\'))`
- `ck_children_tutorial_status`: `(`tutorial_status` in (_utf8mb4\'NOT_STARTED\',_utf8mb4\'IN_PROGRESS\',_utf8mb4\'COMPLETED\',_utf8mb4\'SKIPPED\'))`

### 아동 응답 방식 (`child_response_modes`)

**역할:** 아동 응답 방식 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 아동 응답 방식 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 아동 응답 방식 ID |
| 아동 ID | `child_id` | `bigint` | N | `-` | INDEX, FK → children.id | 아동 ID |
| 응답 방식 | `response_mode` | `varchar(20)` | N | `-` | - | 응답 방식 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_child_response_modes_child_mode`: UNIQUE (`child_id`, `response_mode`)
- `uk_child_response_modes_child_order`: UNIQUE (`child_id`, `display_order`)

**관계·삭제 정책**

- `fk_child_response_modes_child_id`: `child_id` → `children`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_child_response_modes_mode`: `(`response_mode` in (_utf8mb4\'VOICE\',_utf8mb4\'EMOJI\',_utf8mb4\'COLOR\',_utf8mb4\'PICTURE\',_utf8mb4\'TEXT\'))`
- `ck_child_response_modes_order`: `(`display_order` >= 0)`

### 보호자-아동 관계 (`guardian_child_relations`)

**역할:** 보호자-아동 관계 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 보호자-아동 관계 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 보호자-아동 관계 ID |
| 보호자 사용자 ID | `guardian_user_id` | `bigint` | N | `-` | INDEX, FK → users.id | 보호자 사용자 ID |
| 아동 ID | `child_id` | `bigint` | N | `-` | INDEX, FK → children.id | 아동 ID |
| 관계 유형 | `relationship_type` | `varchar(30)` | N | `-` | - | 관계 유형 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `fk_guardian_child_relations_child_id`: INDEX (`child_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_guardian_child_relations_guardian_child`: UNIQUE (`guardian_user_id`, `child_id`)

**관계·삭제 정책**

- `fk_guardian_child_relations_child_id`: `child_id` → `children`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_guardian_child_relations_guardian_id`: `guardian_user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION

### 동의 약관 (`consent_terms`)

**역할:** 동의 약관 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 동의 약관 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 동의 약관 ID |
| 약관 코드 | `term_code` | `varchar(50)` | N | `-` | INDEX | 약관 코드 |
| 동의 대상 범위 | `target_scope` | `varchar(10)` | N | `-` | - | 동의 대상 범위 |
| 필수 여부 | `is_required` | `tinyint(1)` | N | `-` | - | 필수 여부 |
| 약관 버전 | `version` | `varchar(30)` | N | `-` | - | 약관 버전 |
| 약관 제목 | `title` | `varchar(150)` | N | `-` | - | 약관 제목 |
| 내용 URL | `content_url` | `varchar(1000)` | Y | `-` | - | 내용 URL |
| 시행 일시 | `effective_at` | `datetime(6)` | N | `-` | - | 시행 일시 |
| 활성 여부 | `is_active` | `tinyint(1)` | N | `1` | - | 활성 여부 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_consent_terms_code_version`: UNIQUE (`term_code`, `version`)

### 동의 이력 (`consent_records`)

**역할:** 동의 이력 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 동의 이력 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 동의 이력 ID |
| 동의 약관 ID | `consent_term_id` | `bigint` | N | `-` | INDEX, FK → consent_terms.id | 동의 약관 ID |
| 처리 사용자 ID | `actor_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 처리 사용자 ID |
| 동의 대상 아동 ID | `subject_child_id` | `bigint` | Y | `-` | INDEX, FK → children.id | 동의 대상 아동 ID |
| 동의 대상 참조 Hash | `subject_reference_hash` | `char(64)` | N | `-` | INDEX | 동의 대상 참조 Hash |
| 동의 또는 철회 유형 | `action` | `varchar(20)` | N | `-` | - | 동의 또는 철회 유형 |
| IP 주소 | `ip_address` | `varchar(45)` | Y | `-` | - | IP 주소 |
| User-Agent | `user_agent` | `varchar(500)` | Y | `-` | - | User-Agent |
| 기록 일시 | `recorded_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 기록 일시 |

**인덱스·유일성**

- `fk_consent_records_actor_user_id`: INDEX (`actor_user_id`)
- `fk_consent_records_subject_child_id`: INDEX (`subject_child_id`)
- `fk_consent_records_term_id`: INDEX (`consent_term_id`)
- `idx_consent_records_subject_hash`: INDEX (`subject_reference_hash`, `recorded_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_consent_records_actor_user_id`: `actor_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_consent_records_subject_child_id`: `subject_child_id` → `children`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_consent_records_term_id`: `consent_term_id` → `consent_terms`(`id`), DELETE RESTRICT, UPDATE NO ACTION

**CHECK 제약**

- `ck_consent_records_action`: `(`action` in (_utf8mb4\'AGREE\',_utf8mb4\'WITHDRAW\'))`

### 동의 증빙 항목 (`consent_record_evidences`)

**역할:** 동의 증빙 항목 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 동의 증빙 항목 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 동의 증빙 항목 ID |
| 동의 이력 ID | `consent_record_id` | `bigint` | N | `-` | INDEX, FK → consent_records.id | 동의 이력 ID |
| 증빙 항목 코드 | `evidence_key` | `varchar(80)` | N | `-` | - | 증빙 항목 코드 |
| 값 유형 | `value_type` | `varchar(20)` | N | `STRING` | - | 값 유형 |
| 증빙 값 | `value_text` | `text` | N | `-` | - | 증빙 값 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_consent_record_evidences_record_key`: UNIQUE (`consent_record_id`, `evidence_key`)

**관계·삭제 정책**

- `fk_consent_record_evidences_record_id`: `consent_record_id` → `consent_records`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_consent_record_evidences_type`: `(`value_type` in (_utf8mb4\'STRING\',_utf8mb4\'NUMBER\',_utf8mb4\'BOOLEAN\',_utf8mb4\'DATETIME\'))`

### 데이터 내보내기 작업 (`data_export_jobs`)

**역할:** 데이터 내보내기 작업 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 데이터 내보내기 작업 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 데이터 내보내기 작업 ID |
| 사용자 ID | `user_id` | `bigint` | N | `-` | INDEX, FK → users.id | 사용자 ID |
| 내보내기 상태 | `export_status` | `varchar(20)` | N | `PENDING` | INDEX | 내보내기 상태 |
| 내보내기 파일 저장 Key | `storage_key` | `varchar(1000)` | Y | `-` | - | 내보내기 파일 저장 Key |
| 다운로드 만료 일시 | `expires_at` | `datetime(6)` | Y | `-` | - | 다운로드 만료 일시 |
| 완료 일시 | `completed_at` | `datetime(6)` | Y | `-` | - | 완료 일시 |
| 오류 코드 | `error_code` | `varchar(80)` | Y | `-` | - | 오류 코드 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `idx_data_export_jobs_status_created_at`: INDEX (`export_status`, `created_at`)
- `idx_data_export_jobs_user_created_at`: INDEX (`user_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_data_export_jobs_user_id`: `user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_data_export_jobs_status`: `(`export_status` in (_utf8mb4\'PENDING\',_utf8mb4\'PROCESSING\',_utf8mb4\'COMPLETED\',_utf8mb4\'FAILED\',_utf8mb4\'EXPIRED\'))`

## 6. 전문가·활동 자료

### 전문가 프로필 (`expert_profiles`)

**역할:** 전문가 프로필 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 전문가 프로필 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 전문가 프로필 ID |
| 표시 이름 | `display_name` | `varchar(80)` | N | `-` | - | 표시 이름 |
| 프로필 이미지 URL | `profile_image_url` | `varchar(1000)` | Y | `-` | - | 프로필 이미지 URL |
| 소속 기관 | `organization` | `varchar(150)` | Y | `-` | - | 소속 기관 |
| 직책 | `position_title` | `varchar(100)` | Y | `-` | - | 직책 |
| 경력 연수 | `career_years` | `smallint` | N | `0` | - | 경력 연수 |
| 소개 | `introduction` | `text` | Y | `-` | - | 소개 |
| 상담 가능 여부 | `is_consultation_available` | `tinyint(1)` | N | `0` | - | 상담 가능 여부 |
| 검증 상태 | `verification_status` | `varchar(20)` | N | `PENDING` | - | 검증 상태 |
| 근무지 | `workplace` | `varchar(255)` | Y | `-` | - | 근무지 |
| 연락처 | `contact_phone` | `varchar(30)` | Y | `-` | - | 연락처 |
| 연락 이메일 | `contact_email` | `varchar(255)` | Y | `-` | - | 연락 이메일 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | `-` | - | 삭제 일시 |
| 사용자 ID | `user_id` | `bigint` | N | `-` | UNIQUE, FK → users.id | 사용자 ID |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_expert_profiles_user_id`: UNIQUE (`user_id`)

**관계·삭제 정책**

- `fk_expert_profiles_user_id`: `user_id` → `users`(`id`), DELETE RESTRICT, UPDATE NO ACTION

**CHECK 제약**

- `ck_expert_profiles_career_years`: `(`career_years` >= 0)`
- `ck_expert_profiles_verification_status`: `(`verification_status` in (_utf8mb4\'PENDING\',_utf8mb4\'VERIFIED\',_utf8mb4\'REJECTED\',_utf8mb4\'REVIEW_REQUIRED\'))`

### 전문가 전문 분야 (`expert_profile_specialties`)

**역할:** 전문가 전문 분야 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 전문가 전문 분야 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 전문가 전문 분야 ID |
| 전문가 프로필 ID | `expert_profile_id` | `bigint` | N | `-` | INDEX, FK → expert_profiles.id | 전문가 프로필 ID |
| 전문 분야 코드 | `specialty_code` | `varchar(50)` | N | `-` | - | 전문 분야 코드 |
| 전문 분야명 Snapshot | `specialty_name` | `varchar(100)` | N | `-` | - | 전문 분야명 Snapshot |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_expert_profile_specialties_profile_code`: UNIQUE (`expert_profile_id`, `specialty_code`)

**관계·삭제 정책**

- `fk_expert_profile_specialties_profile_id`: `expert_profile_id` → `expert_profiles`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_expert_profile_specialties_order`: `(`display_order` >= 0)`

### 전문가 자격 (`expert_credentials`)

**역할:** 전문가 자격 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 전문가 자격 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 전문가 자격 ID |
| 전문가 프로필 ID | `expert_profile_id` | `bigint` | N | `-` | INDEX, FK → expert_profiles.id | 전문가 프로필 ID |
| 자격명 | `license_name` | `varchar(150)` | N | `-` | - | 자격명 |
| 발급 기관 | `issuer` | `varchar(150)` | N | `-` | - | 발급 기관 |
| 자격 번호 | `credential_number` | `varchar(100)` | Y | `-` | - | 자격 번호 |
| 취득일 | `acquired_on` | `date` | Y | `-` | - | 취득일 |
| 만료일 | `expires_on` | `date` | Y | `-` | - | 만료일 |
| 검증 상태 | `verification_status` | `varchar(20)` | N | `PENDING` | - | 검증 상태 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `idx_expert_credentials_profile_status`: INDEX (`expert_profile_id`, `verification_status`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_expert_credentials_profile_id`: `expert_profile_id` → `expert_profiles`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_expert_credentials_dates`: `((`expires_on` is null) or (`acquired_on` is null) or (`expires_on` >= `acquired_on`))`
- `ck_expert_credentials_status`: `(`verification_status` in (_utf8mb4\'PENDING\',_utf8mb4\'VERIFIED\',_utf8mb4\'REJECTED\',_utf8mb4\'REVIEW_REQUIRED\'))`

### 전문가 자격 증빙 파일 (`expert_credential_files`)

**역할:** 전문가 자격 증빙 파일 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 전문가 자격 증빙 파일 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 전문가 자격 증빙 파일 ID |
| 전문가 자격 ID | `expert_credential_id` | `bigint` | N | `-` | INDEX, FK → expert_credentials.id | 전문가 자격 ID |
| 증빙 파일 저장 Key | `storage_key` | `varchar(1000)` | N | `-` | - | 증빙 파일 저장 Key |
| 증빙 파일 저장 Key SHA-256 Hash | `storage_key_hash` | `char(64)` | N | `-` | UNIQUE | 증빙 파일 저장 Key SHA-256 Hash |
| 원본 파일명 | `file_name` | `varchar(255)` | Y | `-` | - | 원본 파일명 |
| MIME 유형 | `mime_type` | `varchar(100)` | Y | `-` | - | MIME 유형 |
| 파일 크기(Byte) | `file_size_bytes` | `bigint` | Y | `-` | - | 파일 크기(Byte) |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_expert_credential_files_key_hash`: UNIQUE (`storage_key_hash`)
- `uk_expert_credential_files_order`: UNIQUE (`expert_credential_id`, `display_order`)

**관계·삭제 정책**

- `fk_expert_credential_files_credential_id`: `expert_credential_id` → `expert_credentials`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_expert_credential_files_order`: `(`display_order` >= 0)`
- `ck_expert_credential_files_size`: `((`file_size_bytes` is null) or (`file_size_bytes` > 0))`

### 전문가 팔로우 (`expert_follows`)

**역할:** 전문가 팔로우 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 전문가 팔로우 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 전문가 팔로우 ID |
| 보호자 사용자 ID | `guardian_user_id` | `bigint` | N | `-` | INDEX, FK → users.id | 보호자 사용자 ID |
| 전문가 프로필 ID | `expert_profile_id` | `bigint` | N | `-` | INDEX, FK → expert_profiles.id | 전문가 프로필 ID |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `fk_expert_follows_expert_profile_id`: INDEX (`expert_profile_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_expert_follows_guardian_expert`: UNIQUE (`guardian_user_id`, `expert_profile_id`)

**관계·삭제 정책**

- `fk_expert_follows_expert_profile_id`: `expert_profile_id` → `expert_profiles`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_expert_follows_guardian_user_id`: `guardian_user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION

### 미술 활동 자료 (`activity_templates`)

**역할:** 미술 활동 자료 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 미술 활동 자료 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 미술 활동 자료 ID |
| 전문가 프로필 ID | `expert_profile_id` | `bigint` | N | `-` | INDEX, FK → expert_profiles.id | 전문가 프로필 ID |
| 자료 제목 | `title` | `varchar(200)` | N | `-` | - | 자료 제목 |
| 자료 요약 | `summary` | `text` | Y | `-` | - | 자료 요약 |
| 자료 내용 | `content` | `longtext` | N | `-` | - | 자료 내용 |
| 권장 연령 그룹 | `age_group` | `varchar(30)` | N | `-` | - | 권장 연령 그룹 |
| 활동 유형 | `activity_type` | `varchar(50)` | N | `-` | - | 활동 유형 |
| Thumbnail 저장 Key | `thumbnail_key` | `varchar(1000)` | Y | `-` | - | Thumbnail 저장 Key |
| 공개 여부 | `is_visible` | `tinyint(1)` | N | `1` | INDEX | 공개 여부 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | `-` | - | 삭제 일시 |

**인덱스·유일성**

- `idx_activity_templates_expert_created_at`: INDEX (`expert_profile_id`, `created_at`)
- `idx_activity_templates_visible_created_at`: INDEX (`is_visible`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_activity_templates_expert_profile_id`: `expert_profile_id` → `expert_profiles`(`id`), DELETE RESTRICT, UPDATE NO ACTION

### 미술 활동 자료 첨부 파일 (`activity_template_attachments`)

**역할:** 미술 활동 자료 첨부 파일 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 미술 활동 자료 첨부 파일 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 미술 활동 자료 첨부 파일 ID |
| 미술 활동 자료 ID | `activity_template_id` | `bigint` | N | `-` | INDEX, FK → activity_templates.id | 미술 활동 자료 ID |
| 첨부 파일 저장 Key | `storage_key` | `varchar(1000)` | N | `-` | - | 첨부 파일 저장 Key |
| 첨부 파일 저장 Key SHA-256 Hash | `storage_key_hash` | `char(64)` | N | `-` | UNIQUE | 첨부 파일 저장 Key SHA-256 Hash |
| 원본 파일명 | `file_name` | `varchar(255)` | Y | `-` | - | 원본 파일명 |
| MIME 유형 | `mime_type` | `varchar(100)` | Y | `-` | - | MIME 유형 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_activity_template_attachments_key_hash`: UNIQUE (`storage_key_hash`)
- `uk_activity_template_attachments_order`: UNIQUE (`activity_template_id`, `display_order`)

**관계·삭제 정책**

- `fk_activity_template_attachments_template_id`: `activity_template_id` → `activity_templates`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_activity_template_attachments_order`: `(`display_order` >= 0)`

## 7. 그림 활동

### 그림 활동 유형 (`drawing_types`)

**역할:** 그림 활동 유형 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 그림 활동 유형 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 그림 활동 유형 ID |
| 코드 | `code` | `varchar(50)` | N | `-` | UNIQUE | 코드 |
| 그림 활동 유형명 | `name` | `varchar(100)` | N | `-` | - | 그림 활동 유형명 |
| 활동 분류 | `activity_category` | `varchar(20)` | N | `-` | - | 활동 분류 |
| 선택 가능 주체 | `selectable_by` | `varchar(20)` | N | `-` | - | 선택 가능 주체 |
| 권장 최소 연령 | `recommended_age_min` | `tinyint` | Y | `-` | - | 권장 최소 연령 |
| 권장 최대 연령 | `recommended_age_max` | `tinyint` | Y | `-` | - | 권장 최대 연령 |
| 안내 문구 | `guide_text` | `text` | Y | `-` | - | 안내 문구 |
| 활성 여부 | `is_active` | `tinyint(1)` | N | `1` | - | 활성 여부 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_drawing_types_code`: UNIQUE (`code`)

**CHECK 제약**

- `ck_drawing_types_activity_category`: `(`activity_category` in (_utf8mb4\'ASSESSMENT\',_utf8mb4\'GENERAL\'))`
- `ck_drawing_types_age_range`: `((`recommended_age_min` is null) or (`recommended_age_max` is null) or (`recommended_age_min` <= `recommended_age_max`))`
- `ck_drawing_types_selectable_by`: `(`selectable_by` in (_utf8mb4\'GUARDIAN\',_utf8mb4\'CHILD\',_utf8mb4\'BOTH\'))`

### 그림 활동 세션 (`drawing_sessions`)

**역할:** 그림 활동 세션 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 그림 활동 세션 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 그림 활동 세션 ID |
| 아동 ID | `child_id` | `bigint` | N | `-` | INDEX, FK → children.id | 아동 ID |
| 그림 활동 유형 ID | `drawing_type_id` | `bigint` | N | `-` | INDEX, FK → drawing_types.id | 그림 활동 유형 ID |
| 시작 사용자 ID | `started_by_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 시작 사용자 ID |
| 입력 방식 | `input_method` | `varchar(20)` | N | `-` | - | 입력 방식 |
| 그림 제목 | `title` | `varchar(200)` | Y | `-` | - | 그림 제목 |
| 표현한 감정 내용 | `expressed_emotion_text` | `text` | Y | `-` | - | 표현한 감정 내용 |
| 세션 상태 | `session_status` | `varchar(20)` | N | `IN_PROGRESS` | - | 세션 상태 |
| 현재 단계 | `current_stage` | `varchar(30)` | N | `DRAWING` | - | 현재 단계 |
| 시작 일시 | `started_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 시작 일시 |
| 완료 일시 | `completed_at` | `datetime(6)` | Y | `-` | - | 완료 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | `-` | - | 삭제 일시 |
| 그림 활동 세션 생성 요청 멱등성 Key | `idempotency_key` | `varchar(100)` | Y | `-` | UNIQUE | 그림 활동 세션 생성 요청 멱등성 Key |

**인덱스·유일성**

- `fk_drawing_sessions_drawing_type_id`: INDEX (`drawing_type_id`)
- `fk_drawing_sessions_started_by_user_id`: INDEX (`started_by_user_id`)
- `idx_drawing_sessions_active_child`: INDEX (`child_id`, `session_status`, `deleted_at`)
- `idx_drawing_sessions_child_id`: INDEX (`child_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_drawing_sessions_idempotency_key`: UNIQUE (`idempotency_key`)

**관계·삭제 정책**

- `fk_drawing_sessions_child_id`: `child_id` → `children`(`id`), DELETE RESTRICT, UPDATE NO ACTION
- `fk_drawing_sessions_drawing_type_id`: `drawing_type_id` → `drawing_types`(`id`), DELETE RESTRICT, UPDATE NO ACTION
- `fk_drawing_sessions_started_by_user_id`: `started_by_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION

**CHECK 제약**

- `ck_drawing_sessions_current_stage`: `(`current_stage` in (_utf8mb4\'DRAWING\',_utf8mb4\'ANALYZING\',_utf8mb4\'CONVERSING\',_utf8mb4\'REFLECTION\',_utf8mb4\'REPORTING\',_utf8mb4\'COMPLETED\'))`
- `ck_drawing_sessions_input_method`: `(`input_method` in (_utf8mb4\'CANVAS\',_utf8mb4\'UPLOAD\'))`
- `ck_drawing_sessions_session_status`: `(`session_status` in (_utf8mb4\'IN_PROGRESS\',_utf8mb4\'COMPLETED\',_utf8mb4\'FAILED\',_utf8mb4\'ABANDONED\',_utf8mb4\'DELETED\'))`

### 그림 활동 선택 감정 (`drawing_session_emotions`)

**역할:** 그림 활동 선택 감정 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 그림 활동 선택 감정 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 그림 활동 선택 감정 ID |
| 그림 활동 세션 ID | `drawing_session_id` | `bigint` | N | `-` | INDEX, FK → drawing_sessions.id | 그림 활동 세션 ID |
| 감정 코드 | `emotion_code` | `varchar(20)` | N | `-` | - | 감정 코드 |
| 선택 순서 | `selection_order` | `smallint` | N | `0` | - | 선택 순서 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_drawing_session_emotions_session_emotion`: UNIQUE (`drawing_session_id`, `emotion_code`)
- `uk_drawing_session_emotions_session_order`: UNIQUE (`drawing_session_id`, `selection_order`)

**관계·삭제 정책**

- `fk_drawing_session_emotions_session_id`: `drawing_session_id` → `drawing_sessions`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_drawing_session_emotions_code`: `(`emotion_code` in (_utf8mb4\'HAPPY\',_utf8mb4\'SAD\',_utf8mb4\'ANGRY\',_utf8mb4\'SCARED\',_utf8mb4\'CALM\',_utf8mb4\'UNKNOWN\'))`
- `ck_drawing_session_emotions_order`: `(`selection_order` >= 0)`

### Stroke 배치 (`stroke_batches`)

**역할:** Stroke 배치 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| Stroke 배치 ID | `id` | `bigint` | N | `-` | PK, auto_increment | Stroke 배치 ID |
| 그림 활동 세션 ID | `drawing_session_id` | `bigint` | N | `-` | INDEX, FK → drawing_sessions.id | 그림 활동 세션 ID |
| 배치 순번 | `batch_sequence` | `int` | N | `-` | - | 배치 순번 |
| 첫 이벤트 순번 | `first_event_sequence` | `bigint` | N | `-` | - | 첫 이벤트 순번 |
| 마지막 이벤트 순번 | `last_event_sequence` | `bigint` | N | `-` | - | 마지막 이벤트 순번 |
| 이벤트 수 | `event_count` | `int` | N | `-` | - | 이벤트 수 |
| 배치 Payload SHA-256 Checksum | `payload_checksum_sha256` | `char(64)` | N | `-` | - | 배치 Payload SHA-256 Checksum |
| 실행 취소 증가량 | `undo_count_delta` | `int` | N | `0` | - | 실행 취소 증가량 |
| 다시 실행 증가량 | `redo_count_delta` | `int` | N | `0` | - | 다시 실행 증가량 |
| 지우기 증가량 | `erase_count_delta` | `int` | N | `0` | - | 지우기 증가량 |
| 일시 정지 시간 증가량(ms) | `pause_duration_ms_delta` | `bigint` | N | `0` | - | 일시 정지 시간 증가량(ms) |
| 클라이언트 생성 일시 | `client_created_at` | `datetime(6)` | Y | `-` | - | 클라이언트 생성 일시 |
| 수신 일시 | `received_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 수신 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_stroke_batches_session_sequence`: UNIQUE (`drawing_session_id`, `batch_sequence`)

**관계·삭제 정책**

- `fk_stroke_batches_session_id`: `drawing_session_id` → `drawing_sessions`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_stroke_batches_event_count`: `(`event_count` > 0)`
- `ck_stroke_batches_metric_deltas`: `((`undo_count_delta` >= 0) and (`redo_count_delta` >= 0) and (`erase_count_delta` >= 0) and (`pause_duration_ms_delta` >= 0))`
- `ck_stroke_batches_sequence_range`: `(`first_event_sequence` <= `last_event_sequence`)`

### Stroke 이벤트 (`stroke_events`)

**역할:** Stroke 이벤트 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| Stroke 이벤트 ID | `id` | `bigint` | N | `-` | PK, auto_increment | Stroke 이벤트 ID |
| Stroke 배치 ID | `stroke_batch_id` | `bigint` | N | `-` | INDEX, FK → stroke_batches.id | Stroke 배치 ID |
| 전체 이벤트 순번 | `event_sequence` | `bigint` | N | `-` | - | 전체 이벤트 순번 |
| 이벤트 유형 | `event_type` | `varchar(30)` | N | `-` | - | 이벤트 유형 |
| 그리기 도구 | `tool` | `varchar(30)` | Y | `-` | - | 그리기 도구 |
| 색상 코드 | `color` | `char(9)` | Y | `-` | - | 색상 코드 |
| 선 굵기 | `width` | `decimal(8,3)` | Y | `-` | - | 선 굵기 |
| 이벤트 대표 필압 | `pressure` | `decimal(6,5)` | Y | `-` | - | 이벤트 대표 필압 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_stroke_events_batch_sequence`: UNIQUE (`stroke_batch_id`, `event_sequence`)

**관계·삭제 정책**

- `fk_stroke_events_batch_id`: `stroke_batch_id` → `stroke_batches`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_stroke_events_pressure`: `((`pressure` is null) or ((`pressure` >= 0) and (`pressure` <= 1)))`
- `ck_stroke_events_sequence`: `(`event_sequence` >= 0)`
- `ck_stroke_events_width`: `((`width` is null) or (`width` > 0))`

### Stroke 이벤트 좌표 (`stroke_event_points`)

**역할:** Stroke 이벤트 좌표 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| Stroke 좌표 ID | `id` | `bigint` | N | `-` | PK, auto_increment | Stroke 좌표 ID |
| Stroke 이벤트 ID | `stroke_event_id` | `bigint` | N | `-` | INDEX, FK → stroke_events.id | Stroke 이벤트 ID |
| 이벤트 내부 좌표 순번 | `point_sequence` | `int` | N | `-` | - | 이벤트 내부 좌표 순번 |
| 정규화 X 좌표 | `x` | `decimal(8,6)` | N | `-` | - | 정규화 X 좌표 |
| 정규화 Y 좌표 | `y` | `decimal(8,6)` | N | `-` | - | 정규화 Y 좌표 |
| 이벤트 시작 후 경과 시간(ms) | `elapsed_ms` | `bigint` | N | `-` | - | 이벤트 시작 후 경과 시간(ms) |
| 좌표별 필압 | `pressure` | `decimal(6,5)` | Y | `-` | - | 좌표별 필압 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_stroke_event_points_event_sequence`: UNIQUE (`stroke_event_id`, `point_sequence`)

**관계·삭제 정책**

- `fk_stroke_event_points_event_id`: `stroke_event_id` → `stroke_events`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_stroke_event_points_coordinates`: `((`x` >= 0) and (`x` <= 1) and (`y` >= 0) and (`y` <= 1))`
- `ck_stroke_event_points_elapsed`: `(`elapsed_ms` >= 0)`
- `ck_stroke_event_points_pressure`: `((`pressure` is null) or ((`pressure` >= 0) and (`pressure` <= 1)))`
- `ck_stroke_event_points_sequence`: `(`point_sequence` >= 0)`

### 그림 파일 (`drawing_assets`)

**역할:** 그림 파일 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 그림 파일 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 그림 파일 ID |
| 그림 활동 세션 ID | `drawing_session_id` | `bigint` | N | `-` | INDEX, FK → drawing_sessions.id | 그림 활동 세션 ID |
| 파일 유형 | `asset_type` | `varchar(20)` | N | `-` | - | 파일 유형 |
| 파일 버전 | `asset_version` | `int` | N | `1` | - | 파일 버전 |
| 파일 저장 Key | `storage_key` | `varchar(1000)` | N | `-` | - | 파일 저장 Key |
| 파일 URL | `file_url` | `varchar(1000)` | Y | `-` | - | 파일 URL |
| MIME 유형 | `mime_type` | `varchar(100)` | N | `-` | - | MIME 유형 |
| 파일 크기(Byte) | `file_size_bytes` | `bigint` | N | `-` | - | 파일 크기(Byte) |
| 이미지 너비(px) | `width_px` | `int` | Y | `-` | - | 이미지 너비(px) |
| 이미지 높이(px) | `height_px` | `int` | Y | `-` | - | 이미지 높이(px) |
| SHA-256 Checksum | `checksum_sha256` | `char(64)` | N | `-` | - | SHA-256 Checksum |
| 자산에 반영된 마지막 Stroke 이벤트 순번 | `last_event_sequence` | `bigint` | Y | `-` | - | 자산에 반영된 마지막 Stroke 이벤트 순번 |
| 다중 객체 업로드 식별 코드 | `object_code` | `varchar(50)` | Y | `-` | - | 다중 객체 업로드 식별 코드 |
| 만료 일시 | `expires_at` | `datetime(6)` | Y | `-` | - | 만료 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `idx_drawing_assets_session_type`: INDEX (`drawing_session_id`, `asset_type`, `asset_version`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_drawing_assets_session_id`: `drawing_session_id` → `drawing_sessions`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_drawing_assets_asset_type`: `(`asset_type` in (_utf8mb4\'DRAFT\',_utf8mb4\'INTERMEDIATE\',_utf8mb4\'FINAL\',_utf8mb4\'UPLOADED\',_utf8mb4\'THUMBNAIL\',_utf8mb4\'TIMELAPSE\'))`
- `ck_drawing_assets_file_size`: `(`file_size_bytes` >= 0)`
- `ck_drawing_assets_last_event_sequence`: `((`last_event_sequence` is null) or (`last_event_sequence` >= 0))`

## 8. 대화·질문

### AI 질문 Template (`ai_question_templates`)

**역할:** AI 질문 Template 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| AI 질문 Template ID | `id` | `bigint` | N | `-` | PK, auto_increment | AI 질문 Template ID |
| 그림 활동 유형 ID | `drawing_type_id` | `bigint` | Y | `-` | INDEX, FK → drawing_types.id | 그림 활동 유형 ID |
| 생성자 사용자 ID | `created_by_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 생성자 사용자 ID |
| 수정자 사용자 ID | `updated_by_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 수정자 사용자 ID |
| Template 유형 | `template_type` | `varchar(20)` | N | `-` | - | Template 유형 |
| 연령 그룹 | `age_group` | `varchar(30)` | N | `-` | - | 연령 그룹 |
| 질문 난이도 | `difficulty` | `varchar(30)` | N | `-` | - | 질문 난이도 |
| 질문 목적 | `question_purpose` | `varchar(50)` | N | `-` | - | 질문 목적 |
| 질문 내용 | `question_text` | `text` | N | `-` | - | 질문 내용 |
| 활성 여부 | `is_active` | `tinyint(1)` | N | `1` | - | 활성 여부 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `fk_ai_question_templates_created_by_id`: INDEX (`created_by_user_id`)
- `fk_ai_question_templates_updated_by_id`: INDEX (`updated_by_user_id`)
- `idx_ai_question_templates_lookup`: INDEX (`drawing_type_id`, `age_group`, `difficulty`, `is_active`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_ai_question_templates_created_by_id`: `created_by_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_ai_question_templates_drawing_type_id`: `drawing_type_id` → `drawing_types`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_ai_question_templates_updated_by_id`: `updated_by_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION

### AI 질문 Template 위험 응답 안내 (`ai_question_template_risk_responses`)

**역할:** AI 질문 Template 위험 응답 안내 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| AI 질문 Template ID | `question_template_id` | `bigint` | N | `-` | PK, FK → ai_question_templates.id | AI 질문 Template ID |
| 위험 응답 안내 활성 여부 | `is_enabled` | `tinyint(1)` | N | `0` | - | 위험 응답 안내 활성 여부 |
| 보호자 안내 Template | `guardian_guide_template` | `text` | Y | `-` | - | 보호자 안내 Template |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`question_template_id`)

**관계·삭제 정책**

- `fk_ai_question_template_risk_responses_template_id`: `question_template_id` → `ai_question_templates`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_ai_question_template_risk_responses_guide`: `((`is_enabled` = false) or (`guardian_guide_template` is not null))`

### AI 질문 Template 선택지 (`ai_question_template_options`)

**역할:** AI 질문 Template 선택지 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| AI 질문 Template 선택지 ID | `id` | `bigint` | N | `-` | PK, auto_increment | AI 질문 Template 선택지 ID |
| AI 질문 Template ID | `question_template_id` | `bigint` | N | `-` | INDEX, FK → ai_question_templates.id | AI 질문 Template ID |
| API 선택지 식별자 | `option_key` | `varchar(80)` | N | `-` | - | API 선택지 식별자 |
| 선택지 유형 | `option_type` | `varchar(30)` | N | `-` | - | 선택지 유형 |
| 선택지 값 | `option_value` | `varchar(255)` | N | `-` | - | 선택지 값 |
| 표시 문구 | `label` | `varchar(200)` | N | `-` | - | 표시 문구 |
| 표시 Emoji | `emoji` | `varchar(20)` | Y | `-` | - | 표시 Emoji |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_ai_question_template_options_template_key`: UNIQUE (`question_template_id`, `option_key`)
- `uk_ai_question_template_options_template_order`: UNIQUE (`question_template_id`, `display_order`)

**관계·삭제 정책**

- `fk_ai_question_template_options_template_id`: `question_template_id` → `ai_question_templates`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_ai_question_template_options_order`: `(`display_order` >= 0)`

### 대화 세션 (`conversation_sessions`)

**역할:** 대화 세션 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 대화 세션 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 대화 세션 ID |
| 대화 상태 | `conversation_status` | `varchar(20)` | N | `CONVERSING` | - | 대화 상태 |
| 난이도 적용값 | `difficulty_snapshot` | `varchar(30)` | N | `-` | - | 난이도 적용값 |
| 최대 질문 수 | `max_question_count` | `smallint` | N | `10` | - | 최대 질문 수 |
| 현재 질문 수 | `question_count` | `smallint` | N | `0` | - | 현재 질문 수 |
| 시작 일시 | `started_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 시작 일시 |
| 완료 일시 | `completed_at` | `datetime(6)` | Y | `-` | - | 완료 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 그림 활동 세션 ID | `drawing_session_id` | `bigint` | N | `-` | UNIQUE, FK → drawing_sessions.id | 그림 활동 세션 ID |

**인덱스·유일성**

- `idx_conversation_sessions_drawing_session_id`: INDEX (`drawing_session_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_conversation_sessions_drawing_session_id`: UNIQUE (`drawing_session_id`)

**관계·삭제 정책**

- `fk_conversation_sessions_drawing_session_id`: `drawing_session_id` → `drawing_sessions`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_conversation_sessions_question_count`: `((`max_question_count` > 0) and (`question_count` >= 0) and (`question_count` <= `max_question_count`))`
- `ck_conversation_sessions_status`: `(`conversation_status` in (_utf8mb4\'CONVERSING\',_utf8mb4\'COMPLETED\',_utf8mb4\'FAILED\'))`

### 대화 메시지 (`conversation_messages`)

**역할:** 대화 메시지 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 대화 메시지 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 대화 메시지 ID |
| 대화 세션 ID | `conversation_session_id` | `bigint` | N | `-` | INDEX, FK → conversation_sessions.id | 대화 세션 ID |
| 상위 메시지 ID | `parent_message_id` | `bigint` | Y | `-` | INDEX, FK → conversation_messages.id | 상위 메시지 ID |
| 질문 Template ID | `question_template_id` | `bigint` | Y | `-` | INDEX, FK → ai_question_templates.id | 질문 Template ID |
| 메시지 순번 | `message_sequence` | `int` | N | `-` | - | 메시지 순번 |
| 발신자 유형 | `sender_type` | `varchar(20)` | N | `-` | - | 발신자 유형 |
| 메시지 유형 | `message_type` | `varchar(30)` | N | `-` | - | 메시지 유형 |
| 원문 Text | `raw_text` | `text` | Y | `-` | - | 원문 Text |
| 음성 인식 Text | `stt_text` | `text` | Y | `-` | - | 음성 인식 Text |
| 음성 파일 저장 Key | `audio_storage_key` | `varchar(1000)` | Y | `-` | - | 음성 파일 저장 Key |
| 음성 파일 URL | `audio_url` | `varchar(1000)` | Y | `-` | - | 음성 파일 URL |
| 음성 파일 SHA-256 Checksum | `audio_checksum_sha256` | `char(64)` | Y | `-` | - | 음성 파일 SHA-256 Checksum |
| 음성 처리 상태 | `speech_status` | `varchar(20)` | Y | `-` | - | 음성 처리 상태 |
| STT 신뢰도 | `stt_confidence` | `decimal(5,4)` | Y | `-` | - | STT 신뢰도 |
| 보호자 확인 필요 여부 | `needs_guardian_confirmation` | `tinyint(1)` | N | `0` | - | 보호자 확인 필요 여부 |
| 건너뜀 여부 | `is_skipped` | `tinyint(1)` | N | `0` | - | 건너뜀 여부 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `fk_conversation_messages_template_id`: INDEX (`question_template_id`)
- `idx_conversation_messages_parent_message_id`: INDEX (`parent_message_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_conversation_messages_id_parent`: UNIQUE (`id`, `parent_message_id`), 선택 응답이 자신의 상위 질문을 함께 참조할 때 사용
- `uk_conversation_messages_session_sequence`: UNIQUE (`conversation_session_id`, `message_sequence`)

**관계·삭제 정책**

- `fk_conversation_messages_parent_message_id`: `parent_message_id` → `conversation_messages`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_conversation_messages_session_id`: `conversation_session_id` → `conversation_sessions`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_conversation_messages_template_id`: `question_template_id` → `ai_question_templates`(`id`), DELETE SET NULL, UPDATE NO ACTION

**CHECK 제약**

- `ck_conversation_messages_message_type`: `(`message_type` in (_utf8mb4\'QUESTION\',_utf8mb4\'VOICE_ANSWER\',_utf8mb4\'OPTION_ANSWER\',_utf8mb4\'TEXT_ANSWER\',_utf8mb4\'SYSTEM_NOTICE\'))`
- `ck_conversation_messages_sender_type`: `(`sender_type` in (_utf8mb4\'AI\',_utf8mb4\'CHILD\',_utf8mb4\'GUARDIAN\',_utf8mb4\'SYSTEM\'))`
- `ck_conversation_messages_speech_status`: `((`speech_status` is null) or (`speech_status` in (_utf8mb4\'NOT_REQUIRED\',_utf8mb4\'PENDING\',_utf8mb4\'PROCESSING\',_utf8mb4\'SUCCESS\',_utf8mb4\'FAILED\')))`
- `ck_conversation_messages_stt_confidence`: `((`stt_confidence` is null) or ((`stt_confidence` >= 0) and (`stt_confidence` <= 1)))`

### 대화 메시지 선택지 Snapshot (`conversation_message_options`)

**역할:** 대화 메시지 선택지 Snapshot 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 대화 메시지 선택지 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 대화 메시지 선택지 ID |
| 질문 메시지 ID | `conversation_message_id` | `bigint` | N | `-` | INDEX, FK → conversation_messages.id | 질문 메시지 ID |
| 원본 Template 선택지 ID | `template_option_id` | `bigint` | Y | `-` | INDEX, FK → ai_question_template_options.id | 원본 Template 선택지 ID |
| API 선택지 식별자 Snapshot | `option_key` | `varchar(80)` | N | `-` | - | API 선택지 식별자 Snapshot |
| 선택지 유형 Snapshot | `option_type` | `varchar(30)` | N | `-` | - | 선택지 유형 Snapshot |
| 선택지 값 Snapshot | `option_value` | `varchar(255)` | N | `-` | - | 선택지 값 Snapshot |
| 표시 문구 Snapshot | `label` | `varchar(200)` | N | `-` | - | 표시 문구 Snapshot |
| 표시 Emoji Snapshot | `emoji` | `varchar(20)` | Y | `-` | - | 표시 Emoji Snapshot |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `fk_conversation_message_options_template_option_id`: INDEX (`template_option_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_conversation_message_options_message_id`: UNIQUE (`conversation_message_id`, `id`), 선택 응답이 질문과 선택지의 소속을 함께 검증할 때 사용
- `uk_conversation_message_options_message_key`: UNIQUE (`conversation_message_id`, `option_key`)
- `uk_conversation_message_options_message_order`: UNIQUE (`conversation_message_id`, `display_order`)

**관계·삭제 정책**

- `fk_conversation_message_options_message_id`: `conversation_message_id` → `conversation_messages`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_conversation_message_options_template_option_id`: `template_option_id` → `ai_question_template_options`(`id`), DELETE SET NULL, UPDATE NO ACTION

**CHECK 제약**

- `ck_conversation_message_options_order`: `(`display_order` >= 0)`

### 대화 메시지 선택 응답 (`conversation_message_selected_options`)

**역할:** 대화 메시지 선택 응답 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 대화 선택 응답 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 대화 선택 응답 ID |
| 답변 메시지 ID | `answer_message_id` | `bigint` | N | `-` | 복합 FK → conversation_messages.id | 답변 메시지 ID |
| 질문 메시지 ID | `question_message_id` | `bigint` | N | `-` | 복합 FK → conversation_messages.parent_message_id, conversation_message_options.conversation_message_id | 답변의 상위 질문이면서 선택지 소유자인 메시지 ID |
| 질문 메시지 선택지 ID | `message_option_id` | `bigint` | N | `-` | 복합 FK → conversation_message_options.id | 질문 메시지 선택지 ID |
| 선택 당시 표시 문구 | `label_snapshot` | `varchar(200)` | N | `-` | - | 선택 당시 표시 문구 |
| 선택 순서 | `selection_order` | `smallint` | N | `0` | - | 선택 순서 |

**인덱스·유일성**

- `fk_conversation_message_selected_options_answer_question`: INDEX (`answer_message_id`, `question_message_id`)
- `fk_conversation_message_selected_options_question_option`: INDEX (`question_message_id`, `message_option_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_conversation_message_selected_options_answer_option`: UNIQUE (`answer_message_id`, `message_option_id`)
- `uk_conversation_message_selected_options_answer_order`: UNIQUE (`answer_message_id`, `selection_order`)

**관계·삭제 정책**

- `fk_conversation_message_selected_options_answer_question`: (`answer_message_id`, `question_message_id`) → `conversation_messages`(`id`, `parent_message_id`), DELETE CASCADE, UPDATE NO ACTION. 답변이 실제로 해당 질문의 자식인지 보장한다.
- `fk_conversation_message_selected_options_question_option`: (`question_message_id`, `message_option_id`) → `conversation_message_options`(`conversation_message_id`, `id`), DELETE CASCADE, UPDATE NO ACTION. 선택지가 해당 질문에 속하는지 보장한다.

**CHECK 제약**

- `ck_conversation_message_selected_options_order`: `(`selection_order` >= 0)`

### 대화 메시지 대상 객체 (`conversation_message_targets`)

**역할:** 대화 메시지 대상 객체 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 질문 메시지 ID | `conversation_message_id` | `bigint` | N | `-` | PK, FK → conversation_messages.id | 질문 메시지 ID |
| 분석 탐지 객체 ID | `detected_object_id` | `bigint` | Y | `-` | INDEX, FK → analysis_detected_objects.detected_object_id | 분석 탐지 객체 ID |
| 객체 코드 Snapshot | `object_code` | `varchar(50)` | Y | `-` | - | 객체 코드 Snapshot |
| 객체명 Snapshot | `object_name` | `varchar(100)` | Y | `-` | - | 객체명 Snapshot |
| Bounding Box X 좌표 | `bbox_x` | `decimal(8,6)` | N | `-` | - | Bounding Box X 좌표 |
| Bounding Box Y 좌표 | `bbox_y` | `decimal(8,6)` | N | `-` | - | Bounding Box Y 좌표 |
| Bounding Box 너비 | `bbox_width` | `decimal(8,6)` | N | `-` | - | Bounding Box 너비 |
| Bounding Box 높이 | `bbox_height` | `decimal(8,6)` | N | `-` | - | Bounding Box 높이 |

**인덱스·유일성**

- `fk_conversation_message_targets_detected_object_id`: INDEX (`detected_object_id`)
- `PRIMARY`: PRIMARY KEY (`conversation_message_id`)

**관계·삭제 정책**

- `fk_conversation_message_targets_detected_object_id`: `detected_object_id` → `analysis_detected_objects`(`detected_object_id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_conversation_message_targets_message_id`: `conversation_message_id` → `conversation_messages`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_conversation_message_targets_bbox`: `((`bbox_x` >= 0) and (`bbox_x` <= 1) and (`bbox_y` >= 0) and (`bbox_y` <= 1) and (`bbox_width` > 0) and (`bbox_width` <= 1) and (`bbox_height` > 0) and (`bbox_height` <= 1) and ((`bbox_x` + `bbox_width`) <= 1) and ((`bbox_y` + `bbox_height`) <= 1))`

### 대화 메시지 음성 변형 (`conversation_message_audio_variants`)

**역할:** 대화 메시지 음성 변형 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 대화 음성 변형 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 대화 음성 변형 ID |
| 대화 메시지 ID | `conversation_message_id` | `bigint` | N | `-` | INDEX, FK → conversation_messages.id | 대화 메시지 ID |
| 음성 코드 | `voice_code` | `varchar(50)` | N | `-` | - | 음성 코드 |
| 재생 속도 | `speech_speed` | `decimal(4,2)` | N | `1.00` | - | 재생 속도 |
| 음성 파일 저장 Key | `storage_key` | `varchar(1000)` | N | `-` | - | 음성 파일 저장 Key |
| 음성 파일 SHA-256 Checksum | `checksum_sha256` | `char(64)` | N | `-` | - | 음성 파일 SHA-256 Checksum |
| MIME 유형 | `mime_type` | `varchar(100)` | N | `-` | - | MIME 유형 |
| 파일 크기(Byte) | `file_size_bytes` | `bigint` | N | `-` | - | 파일 크기(Byte) |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_conversation_audio_variant`: UNIQUE (`conversation_message_id`, `voice_code`, `speech_speed`)

**관계·삭제 정책**

- `fk_conversation_audio_variant_message_id`: `conversation_message_id` → `conversation_messages`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_conversation_audio_variant_size`: `(`file_size_bytes` > 0)`
- `ck_conversation_audio_variant_speed`: `(`speech_speed` between 0.80 and 1.20)`

## 9. 분석·리포트

### 분석 (`analyses`)

**역할:** 분석 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 분석 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 분석 ID |
| 그림 활동 세션 ID | `drawing_session_id` | `bigint` | N | `-` | INDEX, FK → drawing_sessions.id | 그림 활동 세션 ID |
| 재시도 원본 분석 ID | `retry_of_analysis_id` | `bigint` | Y | `-` | INDEX, FK → analyses.id | 재시도 원본 분석 ID |
| 분석 유형 | `analysis_type` | `varchar(20)` | N | `-` | - | 분석 유형 |
| Idempotency Key | `idempotency_key` | `varchar(100)` | N | `-` | UNIQUE | Idempotency Key |
| 입력 SHA-256 Checksum | `input_checksum_sha256` | `char(64)` | Y | `-` | - | 입력 SHA-256 Checksum |
| 분석 상태 | `analysis_status` | `varchar(20)` | N | `PENDING` | - | 분석 상태 |
| 분석 실행 사유 | `trigger_reason` | `varchar(30)` | Y | `-` | - | 분석 실행 사유 |
| Model 이름 | `model_name` | `varchar(100)` | Y | `-` | - | Model 이름 |
| Model 버전 | `model_version` | `varchar(100)` | Y | `-` | - | Model 버전 |
| 신뢰도 | `confidence` | `decimal(5,4)` | Y | `-` | - | 신뢰도 |
| 오류 코드 | `error_code` | `varchar(80)` | Y | `-` | - | 오류 코드 |
| 오류 메시지 | `error_message` | `text` | Y | `-` | - | 오류 메시지 |
| 요청 일시 | `requested_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 요청 일시 |
| 시작 일시 | `started_at` | `datetime(6)` | Y | `-` | - | 시작 일시 |
| 분석 완료 일시 | `completed_at` | `datetime(6)` | Y | `-` | - | 분석 완료 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `fk_analyses_retry_of_analysis_id`: INDEX (`retry_of_analysis_id`)
- `idx_analyses_drawing_session_id`: INDEX (`drawing_session_id`, `requested_at`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_analyses_idempotency_key`: UNIQUE (`idempotency_key`)

**관계·삭제 정책**

- `fk_analyses_drawing_session_id`: `drawing_session_id` → `drawing_sessions`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_analyses_retry_of_analysis_id`: `retry_of_analysis_id` → `analyses`(`id`), DELETE SET NULL, UPDATE NO ACTION

**CHECK 제약**

- `ck_analyses_confidence`: `((`confidence` is null) or ((`confidence` >= 0) and (`confidence` <= 1)))`
- `ck_analyses_status`: `(`analysis_status` in (_utf8mb4\'PENDING\',_utf8mb4\'PROCESSING\',_utf8mb4\'PARTIAL_SUCCESS\',_utf8mb4\'SUCCESS\',_utf8mb4\'FAILED\'))`
- `ck_analyses_trigger_reason`: `((`trigger_reason` is null) or (`trigger_reason` in (_utf8mb4\'PAUSE\',_utf8mb4\'INTERVAL\',_utf8mb4\'STROKE_COUNT\',_utf8mb4\'CHANGE_RATIO\',_utf8mb4\'USER_REQUEST\',_utf8mb4\'DRAWING_COMPLETE\',_utf8mb4\'ACTIVITY_COMPLETE\',_utf8mb4\'RETRY\')))`
- `ck_analyses_type`: `(`analysis_type` in (_utf8mb4\'INTERMEDIATE\',_utf8mb4\'FINAL\'))`

### 분석 시각 특징 (`analysis_visual_features`)

**역할:** 분석 시각 특징 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 시각 특징 ID | `visual_feature_id` | `bigint` | N | `-` | PK, auto_increment | 시각 특징 ID |
| 분석 ID | `analysis_id` | `bigint` | N | `-` | INDEX, FK → analyses.id | 분석 ID |
| Canvas 점유 비율 | `canvas_coverage_ratio` | `decimal(5,4)` | Y | `-` | - | Canvas 점유 비율 |
| 주요 색상 | `primary_color` | `varchar(20)` | Y | `-` | - | 주요 색상 |
| 주요 색상 비율 | `primary_color_ratio` | `decimal(5,4)` | Y | `-` | - | 주요 색상 비율 |
| 사용 색상 수 | `used_color_count` | `int` | Y | `-` | - | 사용 색상 수 |
| 평균 명도 | `average_brightness` | `decimal(6,3)` | Y | `-` | - | 평균 명도 |
| 평균 채도 | `average_saturation` | `decimal(6,3)` | Y | `-` | - | 평균 채도 |
| 평균 선 굵기 | `average_line_thickness` | `decimal(8,3)` | Y | `-` | - | 평균 선 굵기 |
| 선 굵기 편차 | `line_thickness_deviation` | `decimal(8,3)` | Y | `-` | - | 선 굵기 편차 |
| Edge 밀도 | `edge_density` | `decimal(5,4)` | Y | `-` | - | Edge 밀도 |
| 채움 비율 | `fill_ratio` | `decimal(5,4)` | Y | `-` | - | 채움 비율 |
| 겹침 비율 | `overlap_ratio` | `decimal(5,4)` | Y | `-` | - | 겹침 비율 |
| 대칭 점수 | `symmetry_score` | `decimal(5,4)` | Y | `-` | - | 대칭 점수 |
| 무게 중심 X 좌표 | `center_of_mass_x` | `decimal(8,6)` | Y | `-` | - | 무게 중심 X 좌표 |
| 무게 중심 Y 좌표 | `center_of_mass_y` | `decimal(8,6)` | Y | `-` | - | 무게 중심 Y 좌표 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `idx_analysis_visual_features_analysis_id`: INDEX (`analysis_id`)
- `PRIMARY`: PRIMARY KEY (`visual_feature_id`)

**관계·삭제 정책**

- `fk_analysis_visual_features_analysis_id`: `analysis_id` → `analyses`(`id`), DELETE CASCADE, UPDATE NO ACTION

### 분석 행동 특징 (`analysis_behavior_features`)

**역할:** 분석 행동 특징 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 행동 특징 ID | `behavior_feature_id` | `bigint` | N | `-` | PK, auto_increment | 행동 특징 ID |
| 분석 ID | `analysis_id` | `bigint` | N | `-` | INDEX, FK → analyses.id | 분석 ID |
| 입력 방식 | `input_method` | `varchar(30)` | Y | `-` | - | 입력 방식 |
| 그림 소요 시간(ms) | `drawing_duration_ms` | `bigint` | Y | `-` | - | 그림 소요 시간(ms) |
| 실제 그림 시간(ms) | `active_drawing_duration_ms` | `bigint` | Y | `-` | - | 실제 그림 시간(ms) |
| 일시 정지 횟수 | `pause_count` | `int` | Y | `-` | - | 일시 정지 횟수 |
| 전체 일시 정지 시간(ms) | `total_pause_duration_ms` | `bigint` | Y | `-` | - | 전체 일시 정지 시간(ms) |
| Stroke 수 | `stroke_count` | `int` | Y | `-` | - | Stroke 수 |
| 평균 Stroke 속도 | `average_stroke_speed` | `decimal(10,3)` | Y | `-` | - | 평균 Stroke 속도 |
| 평균 Stroke 길이 | `average_stroke_length` | `decimal(10,3)` | Y | `-` | - | 평균 Stroke 길이 |
| 실행 취소 횟수 | `undo_count` | `int` | Y | `-` | - | 실행 취소 횟수 |
| 다시 실행 횟수 | `redo_count` | `int` | Y | `-` | - | 다시 실행 횟수 |
| 지우기 횟수 | `erase_count` | `int` | Y | `-` | - | 지우기 횟수 |
| Canvas 전체 지우기 횟수 | `canvas_clear_count` | `int` | Y | `-` | - | Canvas 전체 지우기 횟수 |
| 도구 변경 횟수 | `tool_change_count` | `int` | Y | `-` | - | 도구 변경 횟수 |
| 색상 변경 횟수 | `color_change_count` | `int` | Y | `-` | - | 색상 변경 횟수 |
| 평균 압력 | `average_pressure` | `decimal(8,3)` | Y | `-` | - | 평균 압력 |
| 압력 편차 | `pressure_deviation` | `decimal(8,3)` | Y | `-` | - | 압력 편차 |
| 저장 횟수 | `save_count` | `int` | Y | `-` | - | 저장 횟수 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `idx_analysis_behavior_features_analysis_id`: INDEX (`analysis_id`)
- `PRIMARY`: PRIMARY KEY (`behavior_feature_id`)

**관계·삭제 정책**

- `fk_analysis_behavior_features_analysis_id`: `analysis_id` → `analyses`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_analysis_behavior_features_input_method`: `((`input_method` is null) or (`input_method` in (_utf8mb4\'CANVAS\',_utf8mb4\'UPLOAD\')))`

### 분석 탐지 객체 (`analysis_detected_objects`)

**역할:** 분석 탐지 객체 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 탐지 객체 ID | `detected_object_id` | `bigint` | N | `-` | PK, auto_increment | 탐지 객체 ID |
| 분석 ID | `analysis_id` | `bigint` | N | `-` | INDEX, FK → analyses.id | 분석 ID |
| 그림 파일 ID | `drawing_asset_id` | `bigint` | N | `-` | INDEX, FK → drawing_assets.id | 그림 파일 ID |
| 객체 코드 | `object_code` | `varchar(50)` | Y | `-` | - | 객체 코드 |
| 객체명 | `object_name` | `varchar(100)` | Y | `-` | - | 객체명 |
| 신뢰도 점수 | `confidence_score` | `decimal(5,4)` | Y | `-` | - | 신뢰도 점수 |
| Bounding Box X 좌표 | `bbox_x` | `decimal(8,6)` | Y | `-` | - | Bounding Box X 좌표 |
| Bounding Box Y 좌표 | `bbox_y` | `decimal(8,6)` | Y | `-` | - | Bounding Box Y 좌표 |
| Bounding Box 너비 | `bbox_width` | `decimal(8,6)` | Y | `-` | - | Bounding Box 너비 |
| Bounding Box 높이 | `bbox_height` | `decimal(8,6)` | Y | `-` | - | Bounding Box 높이 |
| 면적 비율 | `area_ratio` | `decimal(8,6)` | Y | `-` | - | 면적 비율 |
| 탐지 순서 | `detection_order` | `int` | Y | `-` | - | 탐지 순서 |
| Model 버전 | `model_version` | `varchar(50)` | Y | `-` | - | Model 버전 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `idx_analysis_detected_objects_analysis_id`: INDEX (`analysis_id`)
- `idx_analysis_detected_objects_drawing_asset_id`: INDEX (`drawing_asset_id`)
- `PRIMARY`: PRIMARY KEY (`detected_object_id`)

**관계·삭제 정책**

- `fk_analysis_detected_objects_analysis_id`: `analysis_id` → `analyses`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_analysis_detected_objects_drawing_asset_id`: `drawing_asset_id` → `drawing_assets`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_analysis_detected_objects_confidence`: `((`confidence_score` is null) or ((`confidence_score` >= 0) and (`confidence_score` <= 1)))`

### 분석 관찰 결과 (`analysis_observation_results`)

**역할:** 분석 관찰 결과 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 관찰 결과 ID | `observation_result_id` | `bigint` | N | `-` | PK, auto_increment | 관찰 결과 ID |
| 분석 ID | `analysis_id` | `bigint` | N | `-` | INDEX, FK → analyses.id | 분석 ID |
| 결과 버전 | `result_version` | `int` | Y | `-` | - | 결과 버전 |
| 전체 요약 | `overall_summary` | `text` | Y | `-` | - | 전체 요약 |
| 전문가 내부 검토용 관찰 감정 | `observed_emotion` | `varchar(50)` | Y | `-` | - | 전문가 내부 검토용 관찰 감정 |
| 전문가 내부 검토용 감정 신뢰도 | `emotion_confidence` | `decimal(5,4)` | Y | `-` | - | 전문가 내부 검토용 감정 신뢰도 |
| 긍정 신호 | `positive_signals` | `text` | Y | `-` | - | 긍정 신호 |
| 관찰 필요 지점 | `attention_points` | `text` | Y | `-` | - | 관찰 필요 지점 |
| 근거 요약 | `evidence_summary` | `text` | Y | `-` | - | 근거 요약 |
| 보호자 안내 | `guardian_guidance` | `text` | Y | `-` | - | 보호자 안내 |
| 후속 질문 | `follow_up_question` | `text` | Y | `-` | - | 후속 질문 |
| 전문가 검토 필요 여부 | `is_expert_review_required` | `tinyint(1)` | Y | `-` | - | 전문가 검토 필요 여부 |
| 검토 상태 | `review_status` | `varchar(30)` | Y | `-` | - | 검토 상태 |
| 검토 일시 | `reviewed_at` | `datetime(6)` | Y | `-` | - | 검토 일시 |
| 주의 문구 | `disclaimer_text` | `text` | Y | `-` | - | 주의 문구 |
| 생성 Model 버전 | `generated_model_version` | `varchar(50)` | Y | `-` | - | 생성 Model 버전 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `idx_analysis_observation_results_analysis_id`: INDEX (`analysis_id`)
- `PRIMARY`: PRIMARY KEY (`observation_result_id`)

**관계·삭제 정책**

- `fk_analysis_observation_results_analysis_id`: `analysis_id` → `analyses`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_analysis_observation_results_emotion_confidence`: `((`emotion_confidence` is null) or ((`emotion_confidence` >= 0) and (`emotion_confidence` <= 1)))`

### 분석 제외 입력 (`analysis_unused_inputs`)

**역할:** 분석 제외 입력 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 분석 제외 입력 ID | `unused_input_id` | `bigint` | N | `-` | PK, auto_increment | 분석 제외 입력 ID |
| 분석 ID | `analysis_id` | `bigint` | N | `-` | INDEX, FK → analyses.id | 분석 ID |
| 입력 출처 유형 | `source_type` | `varchar(30)` | Y | `-` | - | 입력 출처 유형 |
| 입력 출처 ID | `source_id` | `bigint` | Y | `-` | - | 입력 출처 ID |
| 입력 이름 | `input_name` | `varchar(100)` | Y | `-` | - | 입력 이름 |
| 입력 순번 | `input_sequence` | `int` | Y | `-` | - | 입력 순번 |
| 입력값 요약 | `input_value_summary` | `text` | Y | `-` | - | 입력값 요약 |
| 제외 사유 코드 | `excluded_reason_code` | `varchar(50)` | Y | `-` | - | 제외 사유 코드 |
| 제외 사유 상세 | `excluded_reason_detail` | `text` | Y | `-` | - | 제외 사유 상세 |
| 검증 상태 | `validation_status` | `varchar(30)` | Y | `-` | - | 검증 상태 |
| 재시도 가능 여부 | `retryable` | `tinyint(1)` | Y | `-` | - | 재시도 가능 여부 |
| 발생 일시 | `occurred_at` | `datetime(6)` | Y | `-` | - | 발생 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `idx_analysis_unused_inputs_analysis_id`: INDEX (`analysis_id`)
- `PRIMARY`: PRIMARY KEY (`unused_input_id`)

**관계·삭제 정책**

- `fk_analysis_unused_inputs_analysis_id`: `analysis_id` → `analyses`(`id`), DELETE CASCADE, UPDATE NO ACTION

### 대화 분석 요약 (`analysis_conversation_summaries`)

**역할:** 대화 분석 요약 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 대화 분석 요약 ID | `conversation_summary_id` | `bigint` | N | `-` | PK, auto_increment | 대화 분석 요약 ID |
| 분석 ID | `analysis_id` | `bigint` | N | `-` | INDEX, FK → analyses.id | 분석 ID |
| 대화 세션 ID | `conversation_session_id` | `bigint` | Y | `-` | INDEX, FK → conversation_sessions.id | 대화 세션 ID |
| 요약 내용 | `summary_text` | `text` | Y | `-` | - | 요약 내용 |
| 주요 주제 | `main_topic` | `varchar(100)` | Y | `-` | - | 주요 주제 |
| 보조 주제 | `secondary_topic` | `varchar(100)` | Y | `-` | - | 보조 주제 |
| 표현 감정 | `expressed_emotion` | `varchar(50)` | Y | `-` | - | 표현 감정 |
| 감정 출처 | `emotion_source` | `varchar(30)` | Y | `-` | - | 감정 출처 |
| 감정 관련 필요 | `emotion_need` | `varchar(255)` | Y | `-` | - | 감정 관련 필요 |
| 질문 수 | `question_count` | `int` | Y | `-` | - | 질문 수 |
| 응답 수 | `response_count` | `int` | Y | `-` | - | 응답 수 |
| 건너뛴 질문 수 | `skipped_question_count` | `int` | Y | `-` | - | 건너뛴 질문 수 |
| 음성 인식 실패 수 | `unrecognized_speech_count` | `int` | Y | `-` | - | 음성 인식 실패 수 |
| 대표 발화 | `representative_utterance` | `text` | Y | `-` | - | 대표 발화 |
| 미응답 주제 | `unanswered_topic` | `text` | Y | `-` | - | 미응답 주제 |
| 요약 Model 버전 | `summary_model_version` | `varchar(50)` | Y | `-` | - | 요약 Model 버전 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `fk_analysis_conversation_summaries_session_id`: INDEX (`conversation_session_id`)
- `idx_analysis_conversation_summaries_analysis_id`: INDEX (`analysis_id`)
- `PRIMARY`: PRIMARY KEY (`conversation_summary_id`)

**관계·삭제 정책**

- `fk_analysis_conversation_summaries_analysis_id`: `analysis_id` → `analyses`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_analysis_conversation_summaries_session_id`: `conversation_session_id` → `conversation_sessions`(`id`), DELETE SET NULL, UPDATE NO ACTION

### 리포트 (`reports`)

**역할:** 리포트 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 ID |
| 그림 활동 세션 ID | `drawing_session_id` | `bigint` | N | `-` | INDEX, FK → drawing_sessions.id | 그림 활동 세션 ID |
| 분석 ID | `analysis_id` | `bigint` | N | `-` | INDEX, FK → analyses.id | 분석 ID |
| 리포트 버전 | `report_version` | `int` | N | `1` | - | 리포트 버전 |
| 리포트 상태 | `report_status` | `varchar(20)` | N | `GENERATING` | - | 리포트 상태 |
| 전문가 검토 권장 여부 | `is_expert_review_recommended` | `tinyint(1)` | N | `0` | - | 전문가 검토 권장 여부 |
| 한계 및 주의 문구 | `limitations_text` | `text` | N | `-` | - | 한계 및 주의 문구 |
| PDF 저장 Key | `pdf_storage_key` | `varchar(1000)` | Y | `-` | - | PDF 저장 Key |
| PDF URL | `pdf_url` | `varchar(1000)` | Y | `-` | - | PDF URL |
| PDF 생성 상태 | `pdf_status` | `varchar(20)` | N | `NONE` | - | PDF 생성 상태 |
| 숨김 일시 | `hidden_at` | `datetime(6)` | Y | `-` | - | 숨김 일시 |
| 리포트 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 리포트 생성 일시 |
| 리포트 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 리포트 수정 일시 |

**인덱스·유일성**

- `fk_reports_analysis_id`: INDEX (`analysis_id`)
- `idx_reports_drawing_session_id`: INDEX (`drawing_session_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_reports_session_version`: UNIQUE (`drawing_session_id`, `report_version`)

**관계·삭제 정책**

- `fk_reports_analysis_id`: `analysis_id` → `analyses`(`id`), DELETE RESTRICT, UPDATE NO ACTION
- `fk_reports_drawing_session_id`: `drawing_session_id` → `drawing_sessions`(`id`), DELETE RESTRICT, UPDATE NO ACTION

**CHECK 제약**

- `ck_reports_pdf_status`: `(`pdf_status` in (_utf8mb4\'NONE\',_utf8mb4\'GENERATING\',_utf8mb4\'READY\',_utf8mb4\'FAILED\'))`
- `ck_reports_status`: `(`report_status` in (_utf8mb4\'GENERATING\',_utf8mb4\'COMPLETED\',_utf8mb4\'FAILED\',_utf8mb4\'HIDDEN\'))`

### 리포트 활동 요약 (`report_activity_summaries`)

**역할:** 리포트 활동 요약 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 ID | `report_id` | `bigint` | N | `-` | PK, FK → reports.id | 리포트 ID |
| 그림 활동 시간(ms) | `drawing_duration_ms` | `bigint` | Y | `-` | - | 그림 활동 시간(ms) |
| 일시 정지 횟수 | `pause_count` | `int` | Y | `-` | - | 일시 정지 횟수 |
| 지우기 횟수 | `erase_count` | `int` | Y | `-` | - | 지우기 횟수 |
| 필압 데이터 존재 여부 | `pressure_available` | `tinyint(1)` | N | `0` | - | 필압 데이터 존재 여부 |
| 대화 질문 수 | `conversation_question_count` | `int` | Y | `-` | - | 대화 질문 수 |
| 대화 응답 수 | `conversation_answered_count` | `int` | Y | `-` | - | 대화 응답 수 |
| 건너뛴 질문 수 | `conversation_skipped_count` | `int` | Y | `-` | - | 건너뛴 질문 수 |
| 보호자용 대화 요약 | `conversation_summary` | `text` | Y | `-` | - | 보호자용 대화 요약 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`report_id`)

**관계·삭제 정책**

- `fk_report_activity_summaries_report_id`: `report_id` → `reports`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_activity_summaries_counts`: `(((`drawing_duration_ms` is null) or (`drawing_duration_ms` >= 0)) and ((`pause_count` is null) or (`pause_count` >= 0)) and ((`erase_count` is null) or (`erase_count` >= 0)) and ((`conversation_question_count` is null) or (`conversation_question_count` >= 0)) and ((`conversation_answered_count` is null) or (`conversation_answered_count` >= 0)) and ((`conversation_skipped_count` is null) or (`conversation_skipped_count` >= 0)))`

### 리포트 활동 주의사항 (`report_activity_notes`)

**역할:** 리포트 활동 주의사항 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 활동 주의사항 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 활동 주의사항 ID |
| 리포트 ID | `report_id` | `bigint` | N | `-` | INDEX, FK → reports.id | 리포트 ID |
| 객관적 활동 주의사항 | `note_text` | `text` | N | `-` | - | 객관적 활동 주의사항 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_report_activity_notes_report_order`: UNIQUE (`report_id`, `display_order`)

**관계·삭제 정책**

- `fk_report_activity_notes_report_id`: `report_id` → `reports`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_activity_notes_order`: `(`display_order` >= 0)`

### 리포트 관찰 특징 (`report_observed_features`)

**역할:** 리포트 관찰 특징 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 관찰 특징 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 관찰 특징 ID |
| 리포트 ID | `report_id` | `bigint` | N | `-` | INDEX, FK → reports.id | 리포트 ID |
| 관찰 특징 코드 | `feature_code` | `varchar(80)` | Y | `-` | - | 관찰 특징 코드 |
| 관찰 제목 | `title` | `varchar(200)` | Y | `-` | - | 관찰 제목 |
| 관찰 내용 | `description` | `text` | N | `-` | - | 관찰 내용 |
| 관찰 근거 요약 | `evidence_summary` | `text` | Y | `-` | - | 관찰 근거 요약 |
| 노출 범위 | `visibility_scope` | `varchar(20)` | N | `EXPERT_ONLY` | - | 노출 범위 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_report_observed_features_report_order`: UNIQUE (`report_id`, `display_order`)

**관계·삭제 정책**

- `fk_report_observed_features_report_id`: `report_id` → `reports`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_observed_features_order`: `(`display_order` >= 0)`
- `ck_report_observed_features_scope`: `(`visibility_scope` in (_utf8mb4\'EXPERT_ONLY\',_utf8mb4\'REVIEWED_GUARDIAN\'))`

### 리포트 주요 대화 (`report_key_conversations`)

**역할:** 리포트 주요 대화 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 주요 대화 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 주요 대화 ID |
| 리포트 ID | `report_id` | `bigint` | N | `-` | INDEX, FK → reports.id | 리포트 ID |
| 질문 메시지 ID | `question_message_id` | `bigint` | Y | `-` | INDEX, FK → conversation_messages.id | 질문 메시지 ID |
| 답변 메시지 ID | `answer_message_id` | `bigint` | Y | `-` | INDEX, FK → conversation_messages.id | 답변 메시지 ID |
| 질문 Snapshot | `question_text` | `text` | N | `-` | - | 질문 Snapshot |
| 답변 Snapshot | `answer_text` | `text` | Y | `-` | - | 답변 Snapshot |
| 답변 유형 Snapshot | `answer_type` | `varchar(30)` | Y | `-` | - | 답변 유형 Snapshot |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `fk_report_key_conversations_answer_id`: INDEX (`answer_message_id`)
- `fk_report_key_conversations_question_id`: INDEX (`question_message_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_report_key_conversations_report_order`: UNIQUE (`report_id`, `display_order`)

**관계·삭제 정책**

- `fk_report_key_conversations_answer_id`: `answer_message_id` → `conversation_messages`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_report_key_conversations_question_id`: `question_message_id` → `conversation_messages`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_report_key_conversations_report_id`: `report_id` → `reports`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_key_conversations_order`: `(`display_order` >= 0)`

### 리포트 근거 문헌 (`report_evidence_references`)

**역할:** 리포트 근거 문헌 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 근거 문헌 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 근거 문헌 ID |
| 리포트 ID | `report_id` | `bigint` | N | `-` | INDEX, FK → reports.id | 리포트 ID |
| 지식베이스 출처 ID | `source_id` | `varchar(100)` | N | `-` | - | 지식베이스 출처 ID |
| 문헌 제목 | `title` | `varchar(500)` | N | `-` | - | 문헌 제목 |
| 발행 연도 | `published_year` | `smallint` | Y | `-` | - | 발행 연도 |
| 참조 구간 | `section` | `varchar(100)` | Y | `-` | - | 참조 구간 |
| 근거 유형 | `evidence_type` | `varchar(50)` | N | `-` | - | 근거 유형 |
| 적용 가능 범위 | `applicability` | `text` | N | `-` | - | 적용 가능 범위 |
| 적용 한계 | `limitations` | `text` | N | `-` | - | 적용 한계 |
| 지식베이스 버전 | `knowledge_base_version` | `varchar(100)` | N | `-` | - | 지식베이스 버전 |
| 검색 문단 SHA-256 Hash | `retrieved_chunk_hash` | `char(64)` | N | `-` | - | 검색 문단 SHA-256 Hash |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_report_evidence_references_report_order`: UNIQUE (`report_id`, `display_order`)
- `uk_report_evidence_references_report_source`: UNIQUE (`report_id`, `source_id`, `retrieved_chunk_hash`)

**관계·삭제 정책**

- `fk_report_evidence_references_report_id`: `report_id` → `reports`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_evidence_references_order`: `(`display_order` >= 0)`
- `ck_report_evidence_references_year`: `((`published_year` is null) or (`published_year` between 1000 and 9999))`

### 리포트 근거 저자 (`report_evidence_authors`)

**역할:** 리포트 근거 저자 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 근거 저자 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 근거 저자 ID |
| 리포트 근거 문헌 ID | `evidence_reference_id` | `bigint` | N | `-` | INDEX, FK → report_evidence_references.id | 리포트 근거 문헌 ID |
| 저자명 | `author_name` | `varchar(200)` | N | `-` | - | 저자명 |
| 저자 순서 | `author_order` | `smallint` | N | `0` | - | 저자 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_report_evidence_authors_evidence_order`: UNIQUE (`evidence_reference_id`, `author_order`)

**관계·삭제 정책**

- `fk_report_evidence_authors_evidence_id`: `evidence_reference_id` → `report_evidence_references`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_evidence_authors_order`: `(`author_order` >= 0)`

### 리포트 후속 안내 (`report_follow_up_guides`)

**역할:** 리포트 후속 안내 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 후속 안내 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 후속 안내 ID |
| 리포트 ID | `report_id` | `bigint` | N | `-` | INDEX, FK → reports.id | 리포트 ID |
| 보호자 안내 문장 | `guidance` | `text` | N | `-` | - | 보호자 안내 문장 |
| 상세 설명 | `detail_text` | `text` | Y | `-` | - | 상세 설명 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_report_follow_up_guides_report_order`: UNIQUE (`report_id`, `display_order`)

**관계·삭제 정책**

- `fk_report_follow_up_guides_report_id`: `report_id` → `reports`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_follow_up_guides_order`: `(`display_order` >= 0)`

### 리포트 보호자 질문 (`report_guardian_questions`)

**역할:** 리포트 보호자 질문 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 리포트 보호자 질문 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 리포트 보호자 질문 ID |
| 리포트 ID | `report_id` | `bigint` | N | `-` | INDEX, FK → reports.id | 리포트 ID |
| 보호자 질문 문장 | `question_text` | `text` | N | `-` | - | 보호자 질문 문장 |
| 질문 목적 | `question_purpose` | `varchar(50)` | Y | `-` | - | 질문 목적 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_report_guardian_questions_report_order`: UNIQUE (`report_id`, `display_order`)

**관계·삭제 정책**

- `fk_report_guardian_questions_report_id`: `report_id` → `reports`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_report_guardian_questions_order`: `(`display_order` >= 0)`

## 10. 커뮤니티·신고

### 커뮤니티 게시글 (`community_posts`)

**역할:** 커뮤니티 게시글 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 게시글 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 게시글 ID |
| 작성자 사용자 ID | `author_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 작성자 사용자 ID |
| 게시글 유형 | `post_type` | `varchar(40)` | N | `-` | - | 게시글 유형 |
| 게시글 제목 | `title` | `varchar(200)` | N | `-` | - | 게시글 제목 |
| 게시글 내용 | `content` | `longtext` | N | `-` | - | 게시글 내용 |
| 익명 여부 | `is_anonymous` | `tinyint(1)` | N | `0` | - | 익명 여부 |
| 공개 여부 | `is_visible` | `tinyint(1)` | N | `1` | - | 공개 여부 |
| 게시글 상태 | `post_status` | `varchar(20)` | N | `ACTIVE` | - | 게시글 상태 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | `-` | - | 삭제 일시 |

**인덱스·유일성**

- `idx_community_posts_author_created_at`: INDEX (`author_user_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_community_posts_author_user_id`: `author_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION

**CHECK 제약**

- `ck_community_posts_status`: `(`post_status` in (_utf8mb4\'ACTIVE\',_utf8mb4\'HIDDEN\',_utf8mb4\'DELETED\'))`
- `ck_community_posts_type`: `(`post_type` in (_utf8mb4\'GUARDIAN_STORY\',_utf8mb4\'ACTIVITY_REVIEW\',_utf8mb4\'EXPERT_COLUMN\',_utf8mb4\'ART_RESOURCE\',_utf8mb4\'DRAWING_GUIDE\',_utf8mb4\'EXPERT_QNA\',_utf8mb4\'NOTICE\'))`

### 커뮤니티 게시글 Template 항목 (`community_post_template_fields`)

**역할:** 커뮤니티 게시글 Template 항목 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 커뮤니티 Template 항목 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 커뮤니티 Template 항목 ID |
| 게시글 ID | `community_post_id` | `bigint` | N | `-` | INDEX, FK → community_posts.id | 게시글 ID |
| Template 항목 코드 | `field_code` | `varchar(80)` | N | `-` | - | Template 항목 코드 |
| 값 유형 | `value_type` | `varchar(20)` | N | `STRING` | - | 값 유형 |
| Template 항목 값 | `value_text` | `text` | N | `-` | - | Template 항목 값 |
| 노출 순서 | `display_order` | `smallint` | N | `0` | - | 노출 순서 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_community_post_template_fields_post_code`: UNIQUE (`community_post_id`, `field_code`)
- `uk_community_post_template_fields_post_order`: UNIQUE (`community_post_id`, `display_order`)

**관계·삭제 정책**

- `fk_community_post_template_fields_post_id`: `community_post_id` → `community_posts`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_community_post_template_fields_order`: `(`display_order` >= 0)`
- `ck_community_post_template_fields_type`: `(`value_type` in (_utf8mb4\'STRING\',_utf8mb4\'NUMBER\',_utf8mb4\'BOOLEAN\',_utf8mb4\'DATE\'))`

### 댓글 (`comments`)

**역할:** 댓글 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 댓글 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 댓글 ID |
| 게시글 ID | `post_id` | `bigint` | N | `-` | INDEX, FK → community_posts.id | 게시글 ID |
| 작성자 사용자 ID | `author_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 작성자 사용자 ID |
| 댓글 내용 | `content` | `text` | N | `-` | - | 댓글 내용 |
| 익명 여부 | `is_anonymous` | `tinyint(1)` | N | `0` | - | 익명 여부 |
| 공개 여부 | `is_visible` | `tinyint(1)` | N | `1` | - | 공개 여부 |
| 댓글 상태 | `comment_status` | `varchar(20)` | N | `ACTIVE` | - | 댓글 상태 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |
| 삭제 일시 | `deleted_at` | `datetime(6)` | Y | `-` | - | 삭제 일시 |

**인덱스·유일성**

- `idx_comments_author_user_id`: INDEX (`author_user_id`)
- `idx_comments_post_created_at`: INDEX (`post_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_comments_author_user_id`: `author_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_comments_post_id`: `post_id` → `community_posts`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_comments_status`: `(`comment_status` in (_utf8mb4\'ACTIVE\',_utf8mb4\'HIDDEN\',_utf8mb4\'DELETED\'))`

### 게시글 좋아요 (`post_likes`)

**역할:** 게시글 좋아요 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 게시글 좋아요 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 게시글 좋아요 ID |
| 게시글 ID | `post_id` | `bigint` | N | `-` | INDEX, FK → community_posts.id | 게시글 ID |
| 사용자 ID | `user_id` | `bigint` | N | `-` | INDEX, FK → users.id | 사용자 ID |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `fk_post_likes_user_id`: INDEX (`user_id`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_post_likes_post_user`: UNIQUE (`post_id`, `user_id`)

**관계·삭제 정책**

- `fk_post_likes_post_id`: `post_id` → `community_posts`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_post_likes_user_id`: `user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION

### 신고 (`complaints`)

**역할:** 신고 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 신고 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 신고 ID |
| 신고자 사용자 ID | `reporter_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 신고자 사용자 ID |
| 신고 대상 유형 | `target_type` | `varchar(20)` | N | `-` | - | 신고 대상 유형 |
| 대상 리포트 ID | `target_report_id` | `bigint` | Y | `-` | INDEX, FK → reports.id | 대상 리포트 ID |
| 대상 게시글 ID | `target_post_id` | `bigint` | Y | `-` | INDEX, FK → community_posts.id | 대상 게시글 ID |
| 대상 댓글 ID | `target_comment_id` | `bigint` | Y | `-` | INDEX, FK → comments.id | 대상 댓글 ID |
| 신고 사유 코드 | `reason_code` | `varchar(50)` | N | `-` | - | 신고 사유 코드 |
| 신고 상세 | `detail_text` | `text` | Y | `-` | - | 신고 상세 |
| 신고 처리 상태 | `complaint_status` | `varchar(20)` | N | `PENDING` | INDEX | 신고 처리 상태 |
| 담당 관리자 사용자 ID | `assigned_admin_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 담당 관리자 사용자 ID |
| 처리 일시 | `resolved_at` | `datetime(6)` | Y | `-` | - | 처리 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `fk_complaints_assigned_admin_user_id`: INDEX (`assigned_admin_user_id`)
- `fk_complaints_target_comment_id`: INDEX (`target_comment_id`)
- `fk_complaints_target_post_id`: INDEX (`target_post_id`)
- `fk_complaints_target_report_id`: INDEX (`target_report_id`)
- `idx_complaints_reporter_created_at`: INDEX (`reporter_user_id`, `created_at`)
- `idx_complaints_status_created_at`: INDEX (`complaint_status`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_complaints_assigned_admin_user_id`: `assigned_admin_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_complaints_reporter_user_id`: `reporter_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_complaints_target_comment_id`: `target_comment_id` → `comments`(`id`), DELETE RESTRICT, UPDATE NO ACTION
- `fk_complaints_target_post_id`: `target_post_id` → `community_posts`(`id`), DELETE RESTRICT, UPDATE NO ACTION
- `fk_complaints_target_report_id`: `target_report_id` → `reports`(`id`), DELETE RESTRICT, UPDATE NO ACTION

**CHECK 제약**

- `ck_complaints_status`: `(`complaint_status` in (_utf8mb4\'PENDING\',_utf8mb4\'REVIEWING\',_utf8mb4\'RESOLVED\',_utf8mb4\'REJECTED\'))`
- `ck_complaints_target`: `(((`target_type` = _utf8mb4\'REPORT\') and (`target_report_id` is not null) and (`target_post_id` is null) and (`target_comment_id` is null)) or ((`target_type` = _utf8mb4\'POST\') and (`target_report_id` is null) and (`target_post_id` is not null) and (`target_comment_id` is null)) or ((`target_type` = _utf8mb4\'COMMENT\') and (`target_report_id` is null) and (`target_post_id` is null) and (`target_comment_id` is not null)))`

### 신고 처리 이력 (`complaint_actions`)

**역할:** 신고 처리 이력 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 신고 처리 이력 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 신고 처리 이력 ID |
| 신고 ID | `complaint_id` | `bigint` | N | `-` | INDEX, FK → complaints.id | 신고 ID |
| 처리 관리자 사용자 ID | `actor_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 처리 관리자 사용자 ID |
| 처리 유형 | `action_type` | `varchar(30)` | N | `-` | - | 처리 유형 |
| 처리 전 상태 | `previous_status` | `varchar(20)` | N | `-` | - | 처리 전 상태 |
| 처리 후 상태 | `next_status` | `varchar(20)` | N | `-` | - | 처리 후 상태 |
| 처리 메모 | `resolution_note` | `text` | Y | `-` | - | 처리 메모 |
| 신고자 알림 여부 | `notify_reporter` | `tinyint(1)` | N | `0` | - | 신고자 알림 여부 |
| 대상 작성자 알림 여부 | `notify_target_author` | `tinyint(1)` | N | `0` | - | 대상 작성자 알림 여부 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `fk_complaint_actions_actor_user_id`: INDEX (`actor_user_id`)
- `idx_complaint_actions_complaint_created_at`: INDEX (`complaint_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_complaint_actions_actor_user_id`: `actor_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_complaint_actions_complaint_id`: `complaint_id` → `complaints`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_complaint_actions_type`: `(`action_type` in (_utf8mb4\'NO_ACTION\',_utf8mb4\'HIDE_CONTENT\',_utf8mb4\'DELETE_CONTENT\',_utf8mb4\'WARN_USER\',_utf8mb4\'SUSPEND_USER\',_utf8mb4\'HIDE_REPORT\',_utf8mb4\'REQUEST_REANALYSIS\'))`

## 11. 알림·운영

### 알림 (`notifications`)

**역할:** 알림 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 알림 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 알림 ID |
| 수신자 사용자 ID | `recipient_user_id` | `bigint` | N | `-` | INDEX, FK → users.id | 수신자 사용자 ID |
| 알림 유형 | `notification_type` | `varchar(40)` | N | `-` | - | 알림 유형 |
| 알림 제목 | `title` | `varchar(200)` | N | `-` | - | 알림 제목 |
| 알림 내용 | `content` | `text` | N | `-` | - | 알림 내용 |
| 관련 게시글 ID | `related_post_id` | `bigint` | Y | `-` | INDEX, FK → community_posts.id | 관련 게시글 ID |
| 관련 리포트 ID | `related_report_id` | `bigint` | Y | `-` | INDEX, FK → reports.id | 관련 리포트 ID |
| 관련 그림 활동 세션 ID | `related_drawing_session_id` | `bigint` | Y | `-` | INDEX, FK → drawing_sessions.id | 관련 그림 활동 세션 ID |
| 전송 상태 | `delivery_status` | `varchar(20)` | N | `PENDING` | - | 전송 상태 |
| 읽은 일시 | `read_at` | `datetime(6)` | Y | `-` | - | 읽은 일시 |
| 전송 일시 | `sent_at` | `datetime(6)` | Y | `-` | - | 전송 일시 |
| 실패 일시 | `failed_at` | `datetime(6)` | Y | `-` | - | 실패 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `fk_notifications_related_drawing_session_id`: INDEX (`related_drawing_session_id`)
- `fk_notifications_related_post_id`: INDEX (`related_post_id`)
- `fk_notifications_related_report_id`: INDEX (`related_report_id`)
- `idx_notifications_recipient_created_at`: INDEX (`recipient_user_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_notifications_recipient_user_id`: `recipient_user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION
- `fk_notifications_related_drawing_session_id`: `related_drawing_session_id` → `drawing_sessions`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_notifications_related_post_id`: `related_post_id` → `community_posts`(`id`), DELETE SET NULL, UPDATE NO ACTION
- `fk_notifications_related_report_id`: `related_report_id` → `reports`(`id`), DELETE SET NULL, UPDATE NO ACTION

**CHECK 제약**

- `ck_notifications_delivery_status`: `(`delivery_status` in (_utf8mb4\'PENDING\',_utf8mb4\'SENT\',_utf8mb4\'FAILED\'))`
- `ck_notifications_type`: `(`notification_type` in (_utf8mb4\'ANALYSIS_COMPLETED\',_utf8mb4\'ANALYSIS_FAILED\',_utf8mb4\'REPORT_COMPLETED\',_utf8mb4\'NEW_EXPERT_POST\',_utf8mb4\'COMMENT_CREATED\',_utf8mb4\'CONSENT_UPDATED\',_utf8mb4\'RETENTION_NOTICE\',_utf8mb4\'ACTIVITY_REMINDER\',_utf8mb4\'RISK_REVIEW_GUIDE\'))`

### 알림 부가 속성 (`notification_attributes`)

**역할:** 알림 부가 속성 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 알림 부가 속성 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 알림 부가 속성 ID |
| 알림 ID | `notification_id` | `bigint` | N | `-` | INDEX, FK → notifications.id | 알림 ID |
| 부가 속성 코드 | `attribute_key` | `varchar(80)` | N | `-` | - | 부가 속성 코드 |
| 값 유형 | `value_type` | `varchar(20)` | N | `STRING` | - | 값 유형 |
| 부가 속성 값 | `value_text` | `varchar(1000)` | N | `-` | - | 부가 속성 값 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_notification_attributes_notification_key`: UNIQUE (`notification_id`, `attribute_key`)

**관계·삭제 정책**

- `fk_notification_attributes_notification_id`: `notification_id` → `notifications`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_notification_attributes_type`: `(`value_type` in (_utf8mb4\'STRING\',_utf8mb4\'NUMBER\',_utf8mb4\'BOOLEAN\',_utf8mb4\'DATETIME\'))`

### Push 기기 Token (`notification_device_tokens`)

**역할:** Push 기기 Token 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| Push 기기 Token ID | `id` | `bigint` | N | `-` | PK, auto_increment | Push 기기 Token ID |
| 사용자 ID | `user_id` | `bigint` | N | `-` | INDEX, FK → users.id | 사용자 ID |
| 암호화된 Push Provider 기기 Token | `token_ciphertext` | `varchar(1500)` | N | `-` | - | 암호화된 Push Provider 기기 Token |
| 기기 Token SHA-256 Hash | `token_hash` | `char(64)` | N | `-` | UNIQUE | 기기 Token SHA-256 Hash |
| 기기 Platform | `platform` | `varchar(20)` | N | `-` | - | 기기 Platform |
| Push Provider | `push_provider` | `varchar(20)` | N | `-` | - | Push Provider |
| 활성 여부 | `is_active` | `tinyint(1)` | N | `1` | - | 활성 여부 |
| 마지막 사용 일시 | `last_used_at` | `datetime(6)` | Y | `-` | - | 마지막 사용 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `idx_notification_device_tokens_user_active`: INDEX (`user_id`, `is_active`)
- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_notification_device_tokens_hash`: UNIQUE (`token_hash`)

**관계·삭제 정책**

- `fk_notification_device_tokens_user_id`: `user_id` → `users`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_notification_device_tokens_platform`: `(`platform` in (_utf8mb4\'ANDROID\',_utf8mb4\'IOS\',_utf8mb4\'WEB\'))`
- `ck_notification_device_tokens_provider`: `(`push_provider` in (_utf8mb4\'FCM\',_utf8mb4\'APNS\'))`

### 감사 로그 (`audit_logs`)

**역할:** 감사 로그 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 감사 로그 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 감사 로그 ID |
| 처리 사용자 ID | `actor_user_id` | `bigint` | Y | `-` | INDEX, FK → users.id | 처리 사용자 ID |
| 행위 유형 | `action_type` | `varchar(80)` | N | `-` | - | 행위 유형 |
| 대상 Resource 유형 | `resource_type` | `varchar(50)` | N | `-` | INDEX | 대상 Resource 유형 |
| 대상 Resource ID | `resource_id` | `bigint` | Y | `-` | - | 대상 Resource ID |
| IP 주소 | `ip_address` | `varchar(45)` | Y | `-` | - | IP 주소 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `idx_audit_logs_actor_user_id`: INDEX (`actor_user_id`, `created_at`)
- `idx_audit_logs_resource`: INDEX (`resource_type`, `resource_id`, `created_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**관계·삭제 정책**

- `fk_audit_logs_actor_user_id`: `actor_user_id` → `users`(`id`), DELETE SET NULL, UPDATE NO ACTION

### 감사 로그 변경 항목 (`audit_log_changes`)

**역할:** 감사 로그 변경 항목 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 감사 로그 변경 항목 ID | `id` | `bigint` | N | `-` | PK, auto_increment | 감사 로그 변경 항목 ID |
| 감사 로그 ID | `audit_log_id` | `bigint` | N | `-` | INDEX, FK → audit_logs.id | 감사 로그 ID |
| 변경 필드 경로 | `field_path` | `varchar(255)` | N | `-` | - | 변경 필드 경로 |
| 값 유형 | `value_type` | `varchar(20)` | N | `STRING` | - | 값 유형 |
| 대상 Snapshot 값 | `snapshot_value` | `text` | Y | `-` | - | 대상 Snapshot 값 |
| 변경 전 값 | `before_value` | `text` | Y | `-` | - | 변경 전 값 |
| 변경 후 값 | `after_value` | `text` | Y | `-` | - | 변경 후 값 |
| 민감값 마스킹 여부 | `is_masked` | `tinyint(1)` | N | `0` | - | 민감값 마스킹 여부 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |

**인덱스·유일성**

- `PRIMARY`: PRIMARY KEY (`id`)
- `uk_audit_log_changes_log_field`: UNIQUE (`audit_log_id`, `field_path`)

**관계·삭제 정책**

- `fk_audit_log_changes_audit_log_id`: `audit_log_id` → `audit_logs`(`id`), DELETE CASCADE, UPDATE NO ACTION

**CHECK 제약**

- `ck_audit_log_changes_type`: `(`value_type` in (_utf8mb4\'STRING\',_utf8mb4\'NUMBER\',_utf8mb4\'BOOLEAN\',_utf8mb4\'DATE\',_utf8mb4\'DATETIME\',_utf8mb4\'NULL\'))`

### Storage 삭제 작업 (`storage_deletion_jobs`)

**역할:** Storage 삭제 작업 데이터를 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/속성 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| Storage 삭제 작업 ID | `id` | `bigint` | N | `-` | PK, auto_increment | Storage 삭제 작업 ID |
| 삭제 대상 Storage Key | `storage_key` | `varchar(1000)` | N | `-` | - | 삭제 대상 Storage Key |
| 연결 Resource 유형 | `resource_type` | `varchar(50)` | N | `-` | INDEX | 연결 Resource 유형 |
| 연결 Resource ID | `resource_id` | `bigint` | Y | `-` | - | 연결 Resource ID |
| 삭제 상태 | `deletion_status` | `varchar(20)` | N | `PENDING` | INDEX | 삭제 상태 |
| 재시도 횟수 | `retry_count` | `smallint` | N | `0` | - | 재시도 횟수 |
| 마지막 오류 코드 | `error_code` | `varchar(80)` | Y | `-` | - | 마지막 오류 코드 |
| 삭제 요청 일시 | `requested_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 삭제 요청 일시 |
| 마지막 시도 일시 | `last_attempted_at` | `datetime(6)` | Y | `-` | - | 마지막 시도 일시 |
| 삭제 완료 일시 | `completed_at` | `datetime(6)` | Y | `-` | - | 삭제 완료 일시 |
| 생성 일시 | `created_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED | 생성 일시 |
| 수정 일시 | `updated_at` | `datetime(6)` | N | `CURRENT_TIMESTAMP(6)` | DEFAULT_GENERATED on update CURRENT_TIMESTAMP(6) | 수정 일시 |

**인덱스·유일성**

- `idx_storage_deletion_jobs_resource`: INDEX (`resource_type`, `resource_id`)
- `idx_storage_deletion_jobs_status_requested_at`: INDEX (`deletion_status`, `requested_at`)
- `PRIMARY`: PRIMARY KEY (`id`)

**CHECK 제약**

- `ck_storage_deletion_jobs_retry_count`: `(`retry_count` >= 0)`
- `ck_storage_deletion_jobs_status`: `(`deletion_status` in (_utf8mb4\'PENDING\',_utf8mb4\'PROCESSING\',_utf8mb4\'COMPLETED\',_utf8mb4\'FAILED\'))`

## 12. 제약조건 집계

| 항목 | 개수 |
| --- | ---: |
| 업무 테이블 | 62 |
| 외래키 | 86 |
| UNIQUE 인덱스(PK 제외) | 48 |
| CHECK 제약 | 90 |

## 13. 코드 및 API 정합성 주의사항

- 현재 구현된 Child, DrawingSession Entity는 제거된 JSON 컬럼을 직접 매핑하지 않아 즉시 수정 대상이 아니다.
- 이후 구현은 JSON 문자열이나 JsonNode 대신 본 명세의 관계 Entity·Repository를 사용한다.
- Stroke batch, event, point는 하나의 Transaction에서 저장하고 payload_checksum_sha256으로 중복 요청을 판별한다.
- Refresh Token용 JPA Entity/Repository를 만들지 않고 Redis 저장소 추상화를 사용한다.
- 첨부 API 공통 규약의 성공 응답 “envelope 없음”과 현재 코드의 공통 envelope는 충돌하므로 DB 작업과 분리해 팀 계약을 확정해야 한다.

## 14. 팀 통합이 필요한 코드값

| 항목 | 충돌 내용 | 이번 기준 |
| --- | --- | --- |
| 감정 코드 | HAPPY/SAD/ANGRY/SCARED/UNKNOWN vs JOY/SADNESS/ANGER/FEAR/UNSURE | 전체 API 명세 v1.0의 전자 사용 |
| 분석 상태 | PROCESSING/PARTIAL_SUCCESS/SUCCESS vs RUNNING/COMPLETED | 기존 V1 CHECK 유지, API 통합 후 별도 Migration |
| 그림 세션 상태·단계 | 문서별 상태 집합 차이 | 현재 Java와 V1 계약 유지 |
| 알림 설정 | 4개 설정 vs 확장 7개 이상 | 전체 API 명세 v1.0의 4개 설정 사용 |
| 성공·오류 응답 | envelope 사용 여부 충돌 | 이번 DB 범위에서 변경하지 않음 |

## 15. 적용 및 검증

- 신규 DB: `erd-cloud-schema-v1.2.sql`을 실행한다.
- 기존 개발 DB: V1·V2 checksum을 바꾸지 않고 Flyway V3를 실행한다.
- V3는 기존 비어 있지 않은 JSON 값이 발견되면 삭제 전에 실패한다. 데이터가 있는 환경은 형태별 변환 Migration을 먼저 작성해야 한다.
- 검증 기준: 업무 테이블 62개, JSON 컬럼 0개, refresh_tokens 0개, FK 86개, UNIQUE 48개, CHECK 90개.
