# ERD JSON Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 팀 ERDCloud Export를 기준으로 모든 JSON 컬럼과 `refresh_tokens`를 제거한 관계형 스키마, Flyway V3 전환 Migration, 전체 테이블 명세를 만든다.

**Architecture:** 구조가 고정된 JSON은 타입이 명확한 하위 테이블로 정규화하고, 감사·알림·커뮤니티의 가변 부가값만 도메인 한정 속성 테이블로 변환한다. 신규 환경은 v1.2 기준 DDL을 사용하고 기존 프로젝트 DB는 V1·V2 checksum을 유지한 채 V3 Migration으로 같은 최종 구조에 도달한다.

**Tech Stack:** MySQL 8.4, Flyway, Spring Boot 3.5.16, Java 21, JUnit 5, Testcontainers, Gradle

## Global Constraints

- Branch는 기존 `docs/erd-schema-refinement`를 사용하며 Jira 이슈 코드를 Branch명에 넣지 않는다.
- 사용자가 별도로 요청하기 전에는 Commit, Push, Merge Request를 생성하지 않는다.
- ERDCloud용 최종 SQL에는 `JSON` 타입과 `refresh_tokens` 테이블이 없어야 한다.
- Refresh Token은 Redis에서 TTL·RTR·폐기 정책으로 관리하며 이번 작업에서 Redis 코드를 구현하지 않는다.
- 기존 `V1__create_initial_schema.sql`과 `V2__add_drawing_session_creation_constraints.sql`은 수정하지 않는다.
- MySQL 식별 PK는 `BIGINT AUTO_INCREMENT`, 시간은 `DATETIME(6)`, 문자셋은 `utf8mb4`를 사용한다.
- 커뮤니티 테이블에는 child, drawing, conversation, analysis, report FK를 추가하지 않는다.
- 아동 발화 원문, 그림 원본, Token 원문을 감사·속성 테이블에 복사하지 않는다.
- SQL과 Markdown은 UTF-8로 작성한다.

## File Structure

- Create `backend/src/main/resources/db/migration/V3__normalize_json_columns.sql`: V1·V2 스키마를 JSON 없는 최종 관계형 구조로 전환한다.
- Modify `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`: Flyway V3, JSON 0개, Refresh Token 테이블 부재, 신규 관계와 제약을 MySQL에서 검증한다.
- Create `docs/database/erd-cloud-schema-v1.2.sql`: ERDCloud 신규 Import와 빈 MySQL DB 검증에 사용하는 완전한 기준 DDL이다.
- Create `docs/database/erd-cloud-schema-v1.2-spec.md`: SQL의 모든 테이블·컬럼·관계·제약과 변경 이유를 설명한다.
- Retain `docs/database/erd-cloud-schema-v1.1.sql` and `docs/database/erd-cloud-schema-v1.1-spec.md`: 이전 제안 비교 기록이며 수정하지 않는다.
- Retain `docs/plans/2026-07-22-erd-json-normalization-design.md`: 승인된 설계 결정 기록이다.

---

### Task 1: MySQL Schema Contract Test

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Consumes: Flyway가 `db/migration`의 V1→V2→V3를 순서대로 실행한 MySQL schema
- Produces: 최종 table 수, JSON 제거, Redis 결정, 대표 PK/FK/UNIQUE/CHECK를 검증하는 회귀 테스트

- [ ] **Step 1: 기존 Migration 테스트 기준을 V3 목표로 변경한다**

`appliesInitialMigration()`을 다음 목표로 변경한다.

```java
@Test
void appliesAllMigrationsWithoutJsonOrRefreshTokenTable() {
  assertThat(MYSQL_CONTAINER.isRunning()).isTrue();
  assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("3");
  assertThat(tableExists("flyway_schema_history")).isTrue();
  assertThat(tableCount()).isEqualTo(63);
  assertThat(tableExists("refresh_tokens")).isFalse();
  assertThat(jsonColumnCount()).isZero();
}
```

다음 helper를 추가한다.

```java
private int jsonColumnCount() {
  return jdbcTemplate.queryForObject(
      "SELECT COUNT(*) FROM information_schema.columns "
          + "WHERE table_schema = DATABASE() AND data_type = 'json'",
      Integer.class);
}
```

- [ ] **Step 2: 정규화 테이블과 핵심 관계 검증을 추가한다**

다음 테스트를 추가한다.

```java
@Test
void createsNormalizedChildTablesAndRelationships() {
  assertThat(tableExists("stroke_events")).isTrue();
  assertThat(tableExists("stroke_event_points")).isTrue();
  assertThat(tableExists("conversation_message_options")).isTrue();
  assertThat(tableExists("conversation_message_selected_options")).isTrue();
  assertThat(tableExists("report_evidence_references")).isTrue();
  assertThat(tableExists("audit_log_changes")).isTrue();
  assertThat(foreignKeyExists("stroke_events", "fk_stroke_events_batch_id")).isTrue();
  assertThat(foreignKeyExists("stroke_event_points", "fk_stroke_event_points_event_id")).isTrue();
  assertThat(
          foreignKeyExists(
              "conversation_message_selected_options",
              "fk_conversation_message_selected_options_option_id"))
      .isTrue();
  assertThat(
          foreignKeyExists(
              "report_evidence_authors", "fk_report_evidence_authors_evidence_id"))
      .isTrue();
}

@Test
void createsNormalizedUniqueConstraintsAndCorrectedColumns() {
  assertThat(indexExists("child_response_modes", "uk_child_response_modes_child_mode", true))
      .isTrue();
  assertThat(indexExists("drawing_session_emotions", "uk_drawing_session_emotions_session_emotion", true))
      .isTrue();
  assertThat(indexExists("expert_follows", "uk_expert_follows_guardian_expert", true)).isTrue();
  assertThat(columnExists("conversation_sessions", "drawing_session_id")).isTrue();
  assertThat(columnExists("conversation_sessions", "conversation_id")).isFalse();
  assertThat(columnExists("analysis_behavior_features", "tool_change_count")).isTrue();
  assertThat(columnExists("analysis_behavior_features", "tool_chnage_count")).isFalse();
}
```

- [ ] **Step 3: Test가 V3 부재로 실패하는지 확인한다**

Run on Windows:

```powershell
cd backend
gradlew.bat test --tests com.ssafy.b209.database.DatabaseMigrationIntegrationTest
```

Expected: FAIL because current Flyway version is `2`, normalized tables do not exist, and JSON columns remain.

---

### Task 2: Flyway V3 Relational Normalization

**Files:**
- Create: `backend/src/main/resources/db/migration/V3__normalize_json_columns.sql`

**Interfaces:**
- Consumes: current V1 schema plus V2 `drawing_sessions.idempotency_key`
- Produces: 62 business tables, zero JSON columns, no `refresh_tokens`, corrected physical names and constraints

- [ ] **Step 1: 신규 정규화 테이블 25개를 생성한다**

다음 테이블을 parent table보다 뒤에서 참조하도록 FK 이름까지 고정해 생성한다.

```text
user_notification_settings
child_response_modes
expert_profile_specialties
expert_credentials
expert_credential_files
stroke_events
stroke_event_points
consent_record_evidences
audit_log_changes
notification_attributes
ai_question_template_risk_responses
ai_question_template_options
conversation_message_options
conversation_message_selected_options
conversation_message_targets
drawing_session_emotions
report_activity_summaries
report_activity_notes
report_observed_features
report_key_conversations
report_evidence_references
report_evidence_authors
report_follow_up_guides
report_guardian_questions
community_post_template_fields
```

각 PK는 `BIGINT AUTO_INCREMENT`, FK는 설계 문서의 생명주기에 따라 `CASCADE` 또는 `RESTRICT`를 사용한다. 순서가 있는 상세 테이블은 parent FK와 `display_order` 또는 sequence를 복합 UNIQUE로 묶는다.

- [ ] **Step 2: API 누락 기능용 9개 테이블을 생성한다**

다음 테이블을 기존 v1.1 제안의 검증된 정의에서 가져오되 `notification_device_tokens` 명칭을 사용한다.

```text
email_verifications
data_export_jobs
conversation_message_audio_variants
complaints
complaint_actions
notification_device_tokens
activity_templates
activity_template_attachments
storage_deletion_jobs
```

`complaints`는 `target_report_id`, `target_post_id`, `target_comment_id` 중 정확히 하나만 존재하는 CHECK를 둔다. `activity_templates`는 커뮤니티와 FK로 연결하지 않으며 `activity_template_attachments`가 파일별 `storage_key`와 순서를 관리한다. `storage_deletion_jobs.storage_key`는 실제 삭제 대상의 영속 Key다.

- [ ] **Step 3: 기존 컬럼을 보강하고 잘못된 물리명을 수정한다**

다음 ALTER를 포함한다.

```text
expert_profiles: users_id → user_id
drawing_assets: last_event_sequence, object_code 추가
stroke_batches: payload_checksum_sha256와 metric delta 4개 추가
conversation_messages: audio_checksum_sha256, stt_confidence, needs_guardian_confirmation 추가
reports: pdf_status 추가
```

`drawing_sessions.idempotency_key`는 이미 V2가 생성했으므로 V3에서 다시 추가하지 않는다. Export의 `conversation_id`, `drawing_image_id`, `tool_chnage_count`, `conversation_sumaary_id`, 별도 `bounding_box` 문제와 `users.deleted_at` 누락은 현재 V1에서 이미 수정되어 있으므로 V3에서 존재하지 않는 컬럼을 다시 변경하지 않는다. 해당 수정은 v1.2 기준 SQL에 그대로 보존한다.

- [ ] **Step 4: 빈 개발 DB 전환 안전성을 검증하고 JSON 컬럼을 제거한다**

Migration 시작 부분에서 기존 JSON 데이터 존재 여부를 검증하는 MySQL stored procedure를 임시 생성한다. 현재 V1의 23개 JSON 컬럼 중 하나라도 non-NULL이고 빈 JSON이 아니면 `SIGNAL SQLSTATE '45000'`으로 중단한다. 검증 후 procedure를 삭제한다.

초기 개발 데이터가 비어 있다는 전제에서 다음 24개 JSON 컬럼을 제거한다.

```text
expert_profiles.specialties_json
expert_profiles.credentials_json
users.notification_settings_json
stroke_batches.payload_json
audit_logs.resource_snapshot_json
audit_logs.before_json
audit_logs.after_json
reports.activity_summary_json
reports.observed_features_json
reports.key_conversations_json
reports.evidence_json
reports.follow_up_json
reports.guardian_questions_json
consent_records.evidence_json
notifications.data_json
ai_question_templates.risk_response_json
ai_question_templates.options_json
conversation_messages.options_json
conversation_messages.selected_response_json
conversation_messages.target_object_json
drawing_sessions.selected_emotions_json
community_posts.template_data_json
children.response_modes_json
```

이 검증은 데이터 유실을 막기 위한 fail-fast 장치다. 실제 JSON 데이터가 있는 환경은 별도 데이터 변환 Migration을 먼저 적용해야 한다.

- [ ] **Step 5: `refresh_tokens`를 제거하고 기존 테이블 제약을 보강한다**

`DROP TABLE refresh_tokens`를 실행한다. 이후 corrected FK, UNIQUE, CHECK, INDEX를 추가한다. 특히 다음 제약 이름을 정확히 사용한다.

```text
uk_expert_profiles_user_id
uk_expert_follows_guardian_expert
uk_conversation_sessions_drawing_session_id
uk_reports_session_version
fk_analysis_detected_objects_drawing_asset_id
fk_conversation_sessions_drawing_session_id
```

- [ ] **Step 6: V3 Migration 통합 테스트를 실행한다**

Run:

```powershell
cd backend
gradlew.bat test --tests com.ssafy.b209.database.DatabaseMigrationIntegrationTest
```

Expected: PASS, Flyway current version `3`, table count `63`, JSON column count `0`, `refresh_tokens` absent.

---

### Task 3: ERDCloud v1.2 Canonical SQL

**Files:**
- Create: `docs/database/erd-cloud-schema-v1.2.sql`

**Interfaces:**
- Consumes: approved design and final structure produced by V1+V2+V3
- Produces: a single clean SQL file that creates the same 62 business tables in an empty MySQL database

- [ ] **Step 1: 기준 SQL Header와 생성 순서를 작성한다**

다음 Header를 사용한다.

```sql
-- 도담 아동 그림·대화 서비스 ERDCloud 통합 스키마 v1.2
-- Target: MySQL 8.0+
-- Encoding: UTF-8 / utf8mb4
SET NAMES utf8mb4;
SET time_zone = '+00:00';
```

부모 테이블을 먼저 생성하고 FK를 각 `CREATE TABLE` 안에 선언한다. `refresh_tokens`와 JSON 컬럼은 포함하지 않는다.

- [ ] **Step 2: 62개 전체 테이블 DDL을 작성한다**

V1+V2+V3의 최종 결과와 동일한 컬럼, DEFAULT, PK, FK, UNIQUE, CHECK, INDEX, COMMENT를 사용한다. Migration 전환용 임시 procedure와 DROP 문은 기준 SQL에 포함하지 않는다.

- [ ] **Step 3: 기준 SQL 정적 검사를 실행한다**

Run:

```powershell
$schema = 'docs/database/erd-cloud-schema-v1.2.sql'
if (Select-String -Path $schema -Pattern '\bJSON\b|CREATE TABLE\s+`?refresh_tokens') { throw 'JSON or refresh_tokens found' }
$tableCount = (Select-String -Path $schema -Pattern '^CREATE TABLE').Count
if ($tableCount -ne 62) { throw "Expected 62 tables, found $tableCount" }
```

Expected: no output and exit code `0`.

- [ ] **Step 4: 빈 MySQL 8.4에서 기준 SQL을 실행한다**

Docker가 사용 가능하면 임시 MySQL 8.4 container에 SQL을 적용하고 `information_schema`를 조회한다. 기존 프로젝트 container나 volume은 삭제하지 않는다.

Expected:

```text
business_table_count = 62
json_column_count = 0
refresh_token_table_count = 0
```

---

### Task 4: Complete Table Specification

**Files:**
- Create: `docs/database/erd-cloud-schema-v1.2-spec.md`

**Interfaces:**
- Consumes: `erd-cloud-schema-v1.2.sql`, approved design, API/ERD gap documents
- Produces: SQL의 모든 table과 constraint를 사람이 검토할 수 있는 한국어 명세

- [ ] **Step 1: 문서 기준과 변경 요약을 작성한다**

문서에 목적, 적용 DB, ERDCloud Import 방법, Redis Refresh Token 결정, JSON 분리 원칙, 삭제 정책을 먼저 설명한다.

- [ ] **Step 2: 62개 테이블의 명세를 작성한다**

각 테이블마다 다음 형식을 반복한다.

```markdown
### 사용자 알림 설정 (`user_notification_settings`)

**역할:** 사용자별 알림 수신 여부를 고정된 Boolean 컬럼으로 관리한다.

| 논리명 | 물리명 | 타입 | NULL | 기본값 | Key/제약 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| 사용자 ID | `user_id` | BIGINT | N | - | PK, FK → `users.id` | 사용자와 1:1 관계 |

**관계·삭제 정책:** `users` 삭제 시 함께 삭제한다.
```

테이블 이름만 나열하지 않고 SQL의 모든 컬럼을 한 번씩 설명한다. JSON에서 분리된 테이블은 원본 컬럼명과 분리 이유를 함께 적는다.

- [ ] **Step 3: 코드값과 미확정 사항을 분리한다**

전체 API 명세에서 확정된 enum만 기준값으로 기록하고, 문서 간 충돌하는 다음 항목은 “팀 통합 필요” 표에 둔다.

```text
EmotionType: HAPPY 계열 vs JOY 계열
DrawingSessionStatus / DrawingStage
AnalysisStatus: PROCESSING·SUCCESS 계열 vs RUNNING·COMPLETED 계열
API 성공·오류 envelope
notification setting key 집합
```

- [ ] **Step 4: SQL과 명세의 table 집합을 대조한다**

SQL의 `CREATE TABLE` 이름과 Markdown의 물리 테이블 이름을 추출해 누락·잉여가 없음을 확인한다. Expected: both sets contain exactly 62 names.

---

### Task 5: Full Verification and Handoff

**Files:**
- Modify only if verification exposes a defect in Tasks 1–4.

**Interfaces:**
- Consumes: V3 Migration, v1.2 canonical SQL, v1.2 specification, schema integration test
- Produces: 검증 결과와 잔여 위험 목록

- [ ] **Step 1: 변경 파일 정적 검사를 실행한다**

Run:

```powershell
git diff --check
rg -n '\bJSON\b|refresh_tokens' docs/database/erd-cloud-schema-v1.2.sql
rg -n 'TODO|TBD|Xdoclint:none' docs/plans/2026-07-22-erd-json-normalization-design.md docs/database/erd-cloud-schema-v1.2-spec.md
```

Expected: `git diff --check` passes; canonical SQL searches return no matches; no TODO/TBD/DocLint suppression appears.

- [ ] **Step 2: Backend 전체 검증을 실행한다**

Run on Windows:

```powershell
cd backend
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

Expected: all commands exit `0`; Javadoc exists at `backend/build/docs/javadoc/index.html`.

- [ ] **Step 3: MySQL 결과를 재확인한다**

Testcontainers 결과에서 다음을 확인한다.

```text
Flyway version = 3
tables including flyway_schema_history = 63
JSON columns = 0
refresh_tokens table = absent
representative PK/FK/UNIQUE constraints = present
```

- [ ] **Step 4: 작업 범위와 잔여 결정을 보고한다**

다음을 최종 보고에 포함한다.

```text
생성·수정 파일
JSON 24개 컬럼별 신규 저장 구조
refresh_tokens 제거와 Redis 후속 작업
Export SQL 오타·FK·중복 구조 수정 내역
전체 table 수와 FK/UNIQUE/CHECK 수
Gradle·MySQL 검증 결과
API 문서 간 enum/envelope 충돌
Commit/Push/MR 미수행 여부
```
