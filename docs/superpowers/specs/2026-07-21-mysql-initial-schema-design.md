# MySQL 연결 및 초기 DB 스키마 설계

## 목표와 범위

Jira `S15P11B209-132`의 범위로 Spring Boot 백엔드에 Local MySQL, H2 Test, Testcontainers MySQL Integration Test 환경을 구성하고 Flyway `V1` 초기 스키마를 작성한다. SQL Preview의 29개 테이블을 기준으로 API 명세의 정합성 수정안, 필수 Unique, FK, Index와 삭제 정책을 보완한다.

이번 작업은 데이터베이스 기반 구성만 담당한다. Entity, Repository, Service, Controller, DTO, 공통 응답, 전역 예외 처리, Swagger, CORS, Security, JWT와 외부 시스템 연동은 구현하지 않는다.

## Git 작업 단위

- 기준 Branch: `origin/develop`
- 작업 Branch: `build/mysql-db-schema`
- Jira 이슈 키는 Branch 이름에 넣지 않는다.
- 권장 Commit과 Merge Request 제목: `build(database): S15P11B209-132 MySQL 연결 및 초기 DB 스키마 구성`
- Merge Request 본문의 관련 이슈에 `Jira: S15P11B209-132`를 기록한다.
- 사용자 요청 전에는 Commit, Push, Merge Request 생성 또는 Merge를 수행하지 않는다.

초기 스키마는 도메인 간 FK 의존성이 강한 하나의 Flyway `V1`이므로 여러 Branch로 나누지 않는다. 이후 Entity, Repository와 API 구현은 도메인별 Jira Branch에서 진행한다.

## 기준 문서와 우선순위

1. 사용자가 제공한 최신 SQL Preview
2. 아동 그림·대화 기반 정서 표현 서비스 API 전체 명세서 v1.0
3. 서비스 기획서
4. Jira `S15P11B209-132` 작업 프롬프트

SQL Preview는 테이블과 컬럼 범위의 기준으로 사용한다. Preview에 없는 FK, Unique, Index, Engine, Character Set과 Collation은 API 명세 및 Jira 요구사항으로 보완한다. API 명세에서 “추가 또는 확장 검토”로 분류한 저장 구조는 V1에 임의로 추가하지 않는다.

## 산출물

- `backend/build.gradle`: JPA, MySQL, Flyway, H2, Testcontainers 의존성
- `backend/src/main/resources/application.yml`: 공통 JPA 설정
- `backend/src/main/resources/application-local.yml`: Local MySQL과 Flyway
- `backend/src/main/resources/application-test.yml`: H2와 비활성화된 Flyway
- `backend/src/main/resources/application-integration-test.yml`: Testcontainers MySQL과 Flyway
- `backend/src/main/resources/db/migration/V1__create_initial_schema.sql`: Flyway 및 ERDCloud 공용 SQL
- `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`: 실제 MySQL 구조 검증
- `.env.example`: Local DB 환경 변수 예시 보완
- `README.md`: Database, Profile, Migration, ERDCloud Import와 테스트 안내
- `docs/database/initial-schema-design.md`: 논리명·물리명, 관계, 제약조건, 수정 내역

Flyway SQL 자체를 ERDCloud에 Import한다. 동일한 DDL을 별도 복제하지 않아 문서용 SQL과 실행 SQL이 달라지는 문제를 방지한다.

## Profile과 실행 흐름

### `local`

- MySQL `127.0.0.1:3306`, 기본 Database `dodam`
- 연결 정보는 `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` 사용
- Flyway 활성화, `ddl-auto=validate`, `open-in-view=false`
- Database 생성과 사용자 권한 관리는 Migration 범위에서 제외

### `test`

- H2 In-memory와 MySQL 호환 Mode
- Flyway 비활성화, `ddl-auto=create-drop`
- 빠른 Context와 DB 비종속 Service 테스트 용도
- MySQL JSON, Collation, FK, Unique, Index 최종 검증에는 사용하지 않음

### `integration-test`

- Testcontainers `mysql:8.4.10`
- `@ServiceConnection`으로 DataSource 연결 정보 주입
- Flyway 활성화, `ddl-auto=validate`
- MySQL 전용 스키마와 제약조건의 최종 검증 환경

## 스키마 영역과 테이블

### 사용자·동의

| 논리명 | 물리명 |
| --- | --- |
| 사용자 | `users` |
| 인증 계정 | `auth_accounts` |
| Refresh Token | `refresh_tokens` |
| 전문가 프로필 | `expert_profiles` |
| 전문가 팔로우 | `expert_follows` |
| 아동 | `children` |
| 보호자-아동 관계 | `guardian_child_relations` |
| 동의 약관 | `consent_terms` |
| 동의 이력 | `consent_records` |

### 그림·대화

| 논리명 | 물리명 |
| --- | --- |
| 그림 활동 유형 | `drawing_types` |
| 그림 활동 세션 | `drawing_sessions` |
| 스트로크 배치 | `stroke_batches` |
| 그림 파일 | `drawing_assets` |
| AI 질문 템플릿 | `ai_question_templates` |
| 대화 세션 | `conversation_sessions` |
| 대화 메시지 | `conversation_messages` |

### 분석·리포트

| 논리명 | 물리명 |
| --- | --- |
| 분석 | `analyses` |
| 시각 특징 | `analysis_visual_features` |
| 행동 특징 | `analysis_behavior_features` |
| 탐지 객체 | `analysis_detected_objects` |
| 관찰 결과 | `analysis_observation_results` |
| 분석 제외 입력 | `analysis_unused_inputs` |
| 대화 분석 요약 | `analysis_conversation_summaries` |
| 리포트 | `reports` |

### 커뮤니티·운영

| 논리명 | 물리명 |
| --- | --- |
| 커뮤니티 게시글 | `community_posts` |
| 댓글 | `comments` |
| 게시글 좋아요 | `post_likes` |
| 알림 | `notifications` |
| 감사 로그 | `audit_logs` |

## 논리명과 물리명 표현

- 테이블 물리명은 영문 소문자 `snake_case`로 작성한다.
- 테이블 논리명은 `CREATE TABLE ... COMMENT='분석'`처럼 한글 Table Comment로 작성한다.
- 컬럼 물리명은 영문 소문자 `snake_case`로 작성한다.
- 컬럼 논리명은 `id BIGINT ... COMMENT '분석 ID'`처럼 한글 Column Comment로 작성한다.
- 제약조건 물리명은 `pk_`, `fk_`, `uk_`, `idx_`, `ck_` 접두사를 사용한다. 단, MySQL은 사용자 지정 Primary Key 이름을 메타데이터에서 `PRIMARY`로 노출하므로 통합 테스트는 PK 이름이 아니라 테이블별 Primary Key 존재 여부를 검증한다.
- `Key` 같은 예약어·의미 불명 이름은 사용하지 않는다.

이 규칙으로 ERDCloud에서 이미지와 같이 한글 논리명, 영문 물리명, 타입을 함께 확인할 수 있도록 한다.

## SQL Preview 수정 사항

| Preview | 적용 설계 | 이유 |
| --- | --- | --- |
| `conversation_sessions.conversation_id` | `drawing_session_id` | 실제 참조 대상이 그림 활동 세션임 |
| `analysis_detected_objects.drawing_image_id` | `drawing_asset_id` | `drawing_images`가 없고 분석 입력은 그림 파일임 |
| `analysis_behavior_features.tool_chnage_count` | `tool_change_count` | 오탈자 수정 |
| `analysis_conversation_summaries.conversation_sumaary_id` | `conversation_summary_id` | 오탈자 수정 |
| `expert_follows.Key`와 `(id, Key)` PK | `Key` 삭제, PK `id` | 의미 없는 컬럼과 복합 PK 제거 |
| PK에 자동 증가 없음 | `BIGINT AUTO_INCREMENT` | 식별자 생성 규칙 통일 |
| Engine/Charset/Collation 없음 | InnoDB, `utf8mb4`, `utf8mb4_0900_ai_ci` | MySQL 8.4 기준 통일 |
| FK/Unique/Index 없음 | 명시적 제약조건 추가 | 관계 무결성과 조회 성능 보장 |
| 일부 `DATETIME` 정밀도·기본값 불일치 | `DATETIME(6)`과 일관된 생성 시각 기본값 | 시간 정밀도 통일 |
| `updated_at` 자동 갱신 없음 | `ON UPDATE CURRENT_TIMESTAMP(6)` | 수정 시각 일관성 유지 |

`conversation_messages.bounding_box`는 API 명세의 중복 경고에 따라 제거하고 `target_object_json` 안의 `boundingBox`를 단일 기준으로 사용한다. `analysis_observation_results.observed_emotion`과 `emotion_confidence`는 전문가 내부 자료에만 사용한다는 공개 범위 제약을 설계 문서에 명시하되, Preview 컬럼 자체는 유지한다.

## 주요 Unique

- `auth_accounts(provider, provider_subject)`
- Local 인증 이메일은 `provider='LOCAL'`일 때만 `login_email`을 반환하는 `local_login_email` 생성 컬럼을 두고 Unique를 적용한다. 다른 Provider는 생성값이 `NULL`이므로 동일 이메일을 공유할 수 있다.
- `stroke_batches(drawing_session_id, batch_sequence)`
- `guardian_child_relations(guardian_user_id, child_id)`
- `analyses(idempotency_key)`
- `conversation_messages(conversation_session_id, message_sequence)`
- `post_likes(post_id, user_id)`
- `expert_follows(guardian_user_id, expert_profile_id)`
- `reports(drawing_session_id, report_version)`
- `expert_profiles(users_id)`
- `drawing_types(code)`
- `consent_terms(term_code, version)`

## FK와 삭제 정책

### `ON DELETE CASCADE`

부모가 하드 삭제될 때 독립적 의미가 없는 완전 종속 데이터에 적용한다.

- 사용자 → 인증 계정, Refresh Token, 보호자-아동 관계, 전문가 팔로우
- 그림 활동 세션 → 스트로크 배치, 그림 파일, 대화 세션, 분석
- 대화 세션 → 대화 메시지
- 분석 → 시각 특징, 행동 특징, 탐지 객체, 관찰 결과, 제외 입력, 대화 분석 요약
- 게시글 → 댓글, 좋아요

### `ON DELETE RESTRICT`

기록 보존 또는 명시적 정리 순서가 필요한 핵심 데이터에 적용한다.

- 사용자 → 전문가 프로필
- 아동 → 그림 활동 세션
- 그림 활동 유형 → 그림 활동 세션
- 그림 활동 세션·분석 → 리포트
- 동의 약관 → 동의 이력

서비스의 일반 삭제는 `deleted_at` 또는 상태값을 사용한다. RESTRICT는 실수로 핵심 기록을 하드 삭제하는 것을 방지한다.

### `ON DELETE SET NULL`

선택적 참조가 사라져도 본문 기록을 보존해야 하는 Nullable FK에 적용한다.

- 게시글·댓글 작성자
- 알림 관련 게시글·리포트·그림 활동
- 감사 로그 처리 사용자
- 동의 처리 사용자와 대상 아동
- 질문 템플릿 생성·수정 사용자와 그림 활동 유형
- 대화 메시지 상위 메시지와 질문 템플릿
- 분석 재시도 원본
- 대화 분석 요약의 대화 세션

모든 `SET NULL` 대상 컬럼은 Nullable로 정의한다.

## 상태값과 Check Constraint

API 명세에서 값이 확정된 `role`, 계정 상태, 그림 활동 상태, 대화 상태, 분석 상태, 리포트 상태 등은 이름이 지정된 `CHECK` Constraint로 제한한다. 문서 간 값이 확정되지 않은 상태 컬럼은 길이 제한과 `NOT NULL`만 적용하고 `docs/database/initial-schema-design.md`에 미적용 이유를 기록한다. 임의 Enum 값을 만들어 넣지 않는다.

## 제외하는 확장 구조

다음 구조는 API 명세에서 추가 검토 대상으로 분류되어 SQL Preview에도 없으므로 V1에서 제외한다.

- `expert_credentials`
- `notification_device_tokens`
- `complaints`, `complaint_actions`
- 별도 `activity_templates`
- `consultation_requests`, `consultation_report_shares`, `expert_reviews`
- `analysis_evidence_sources`
- `expert_review_items`

이 기능은 확정된 별도 Jira 이슈에서 새 Flyway Migration으로 추가한다.

## 통합 테스트 설계

`DatabaseMigrationIntegrationTest`는 `mysql:8.4.10` Container와 `integration-test` Profile을 사용한다. 테스트는 다음을 검증한다.

1. Container와 Spring DataSource 연결
2. Flyway `V1` 성공 및 `flyway_schema_history` 존재
3. 29개 핵심 테이블 존재
4. 대표 PK: `users`, `drawing_sessions`, `analyses`
5. 대표 FK: 아동-그림 활동, 그림 활동-분석, 대화 세션-메시지, 게시글-댓글
6. 대표 Unique: 인증 제공자 식별자, 스트로크 순번, 분석 멱등성 키, 메시지 순번, 좋아요 조합
7. 대표 Index: 아동별 활동, 세션별 분석, 사용자별 알림
8. Flyway 적용 버전 `1`

모든 컬럼을 테스트에 반복해 나열하지 않고, Migration 오류를 발견할 수 있는 구조적 표본을 검증한다. Docker 또는 `mysql:8.4.10` Image를 사용할 수 없으면 테스트를 비활성화하거나 삭제하지 않고 정확한 원인을 보고한다.

## 오류 처리와 검증

- Local `dodam` Database 존재 여부는 `SHOW DATABASES`로 확인한다.
- Database가 없으면 Migration에서 생성하지 않고 README의 `CREATE DATABASE` 예시만 제공한다.
- Local 비밀번호와 Git 자격정보는 출력하거나 저장하지 않는다.
- H2 Context 테스트, Testcontainers 통합 테스트, Spotless, Javadoc을 실행한다.
- Local MySQL이 준비된 경우 `bootRun`으로 Flyway와 Hibernate Validation을 확인하고 종료한다.
- Local MySQL이나 Docker가 준비되지 않은 경우 성공으로 간주하지 않고 미검증 항목과 원인을 보고한다.
