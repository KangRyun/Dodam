# MySQL Initial Schema Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local MySQL, H2 Test, Testcontainers MySQL Integration Test와 Flyway 기반 29개 테이블 초기 스키마를 구성하고 ERDCloud에서 한글 논리명과 영문 물리명을 함께 확인할 수 있게 한다.

**Architecture:** Flyway `V1__create_initial_schema.sql`을 실행 스키마와 ERDCloud Import의 단일 기준으로 사용한다. Profile별 DataSource 책임을 분리하고 H2는 빠른 Context 테스트, Testcontainers MySQL 8.4.10은 실제 Migration과 제약조건 검증에 사용한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Gradle 8.14.3, Spring Data JPA, MySQL 8.4.10 LTS, Flyway, H2, Testcontainers, JUnit 5, JdbcTemplate

## Global Constraints

- 기준 Branch는 `origin/develop`, 작업 Branch는 이슈 키 없는 `build/mysql-db-schema`이다.
- Jira `S15P11B209-132`는 Commit 메시지와 Merge Request 제목·본문에만 넣는다.
- 사용자가 별도로 요청하기 전에는 Commit, Push, Merge Request 생성, Merge, Rebase를 수행하지 않는다.
- 기존 Java 21, Spring Boot 3.5.16, Gradle 8.14.3, Spotless 8.8.0, Javadoc UTF-8 설정을 유지한다.
- Entity, Repository, Service, Controller, DTO, 공통 응답, 예외 처리, Swagger, CORS, Security, JWT와 외부 연동을 구현하지 않는다.
- Flyway만 MySQL 스키마 변경 기준으로 사용하고 Hibernate는 Local과 Integration Test에서 `validate`만 수행한다.
- H2용 별도 Migration을 만들지 않는다.
- 비밀번호, Token, 개인 DB 설정과 `.env`를 Commit하지 않는다.
- Docker와 MySQL CLI가 현재 PATH에 없으므로 Testcontainers와 Local MySQL 검증 실패를 숨기지 않고 원인을 보고한다.
- Docker Official Image에는 `mysql:8.4.10` Tag가 존재하므로 버전을 임의 변경하지 않는다.

---

### Task 1: Database 의존성과 Profile 구성

**Files:**
- Modify: `backend/build.gradle`
- Modify: `backend/src/main/resources/application.yml`
- Modify: `backend/src/main/resources/application-local.yml`
- Modify: `backend/src/main/resources/application-test.yml`
- Create: `backend/src/main/resources/application-integration-test.yml`
- Test: `backend/src/test/java/com/ssafy/b209/B209ApplicationTests.java`

**Interfaces:**
- Consumes: 기존 Spring Boot Application과 `test` Profile Context 테스트
- Produces: Local MySQL, H2 Test, Testcontainers Integration Test가 서로 섞이지 않는 설정

- [ ] **Step 1: 기존 Context 테스트를 실행해 기준 상태 확인**

```powershell
backend\gradlew.bat clean test --tests "*B209ApplicationTests"
```

Expected: 1 test, 0 failures.

- [ ] **Step 2: Database 의존성 추가**

`backend/build.gradle`의 기존 의존성을 유지하고 다음 항목을 추가한다.

```groovy
implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
implementation 'org.flywaydb:flyway-core'

runtimeOnly 'com.mysql:mysql-connector-j'
runtimeOnly 'org.flywaydb:flyway-mysql'

testRuntimeOnly 'com.h2database:h2'

testImplementation 'org.springframework.boot:spring-boot-testcontainers'
testImplementation 'org.testcontainers:junit-jupiter'
testImplementation 'org.testcontainers:mysql'
```

- [ ] **Step 3: 공통 JPA 설정 추가**

`backend/src/main/resources/application.yml`의 `spring` 아래에 다음을 추가한다.

```yaml
  jpa:
    open-in-view: false
```

- [ ] **Step 4: Local MySQL과 Flyway 설정 작성**

`backend/src/main/resources/application-local.yml`:

```yaml
spring:
  config:
    activate:
      on-profile: local

  datasource:
    url: jdbc:mysql://${DB_HOST:127.0.0.1}:${DB_PORT:3306}/${DB_NAME:dodam}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    username: ${DB_USERNAME:root}
    password: ${DB_PASSWORD:}
    driver-class-name: com.mysql.cj.jdbc.Driver

  jpa:
    show-sql: false
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        format_sql: true

  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
    validate-on-migrate: true
    out-of-order: false
    clean-disabled: true
```

- [ ] **Step 5: H2 Test 설정 작성**

`backend/src/main/resources/application-test.yml`:

```yaml
spring:
  config:
    activate:
      on-profile: test

  datasource:
    url: jdbc:h2:mem:dodam-test;MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1
    username: sa
    password:
    driver-class-name: org.h2.Driver

  jpa:
    database-platform: org.hibernate.dialect.H2Dialect
    show-sql: false
    hibernate:
      ddl-auto: create-drop

  flyway:
    enabled: false
```

- [ ] **Step 6: Integration Test 설정 작성**

`backend/src/main/resources/application-integration-test.yml`:

```yaml
spring:
  config:
    activate:
      on-profile: integration-test

  jpa:
    show-sql: false
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        format_sql: true

  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
    validate-on-migrate: true
    out-of-order: false
    clean-disabled: true
```

- [ ] **Step 7: H2 Context 테스트 통과 확인**

```powershell
backend\gradlew.bat clean test --tests "*B209ApplicationTests"
```

Expected: H2 DataSource로 Context가 시작되고 1 test, 0 failures.

### Task 2: 실패하는 MySQL Migration 통합 테스트 작성

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Consumes: `mysql:8.4.10`, `integration-test` Profile, Spring `JdbcTemplate`, `Flyway`
- Produces: Migration 버전과 대표 Table·PK·FK·Unique·Index 검증

- [ ] **Step 1: Testcontainers 통합 테스트 작성**

```java
package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Testcontainers MySQL 8.4.10에서 Flyway 초기 Migration과 핵심 데이터베이스 구조를 검증한다.
 *
 * <p>H2 기반 Context 테스트와 달리 MySQL 전용 타입, FK, Unique와 Index가 실제 서버에 생성되는지 확인한다. 실행하려면
 * Docker 환경이 필요하다.
 */
@Testcontainers
@SpringBootTest
@ActiveProfiles("integration-test")
class DatabaseMigrationIntegrationTest {

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam")
          .withUsername("test")
          .withPassword("test");

  @Autowired JdbcTemplate jdbcTemplate;

  @Autowired Flyway flyway;

  @Test
  void appliesInitialMigration() {
    assertThat(MYSQL_CONTAINER.isRunning()).isTrue();
    assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("1");
    assertThat(tableExists("flyway_schema_history")).isTrue();
    assertThat(tableCount()).isEqualTo(30);
  }

  @Test
  void createsRepresentativePrimaryAndForeignKeys() {
    assertThat(primaryKeyExists("users")).isTrue();
    assertThat(primaryKeyExists("drawing_sessions")).isTrue();
    assertThat(primaryKeyExists("analyses")).isTrue();
    assertThat(foreignKeyExists("drawing_sessions", "fk_drawing_sessions_child_id")).isTrue();
    assertThat(foreignKeyExists("analyses", "fk_analyses_drawing_session_id")).isTrue();
    assertThat(foreignKeyExists("conversation_messages", "fk_conversation_messages_session_id"))
        .isTrue();
    assertThat(foreignKeyExists("comments", "fk_comments_post_id")).isTrue();
  }

  @Test
  void createsRepresentativeUniqueConstraintsAndIndexes() {
    assertThat(indexExists("auth_accounts", "uk_auth_accounts_provider_subject", true)).isTrue();
    assertThat(indexExists("stroke_batches", "uk_stroke_batches_session_sequence", true)).isTrue();
    assertThat(indexExists("analyses", "uk_analyses_idempotency_key", true)).isTrue();
    assertThat(indexExists("conversation_messages", "uk_conversation_messages_session_sequence", true))
        .isTrue();
    assertThat(indexExists("post_likes", "uk_post_likes_post_user", true)).isTrue();
    assertThat(indexExists("drawing_sessions", "idx_drawing_sessions_child_id", false)).isTrue();
    assertThat(indexExists("analyses", "idx_analyses_drawing_session_id", false)).isTrue();
    assertThat(indexExists("notifications", "idx_notifications_recipient_created_at", false)).isTrue();
  }

  private int tableCount() {
    return jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()",
        Integer.class);
  }

  private boolean tableExists(String tableName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?",
            tableName)
        > 0;
  }

  private boolean primaryKeyExists(String tableName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.table_constraints "
                + "WHERE constraint_schema = DATABASE() AND table_name = ? "
                + "AND constraint_type = 'PRIMARY KEY'",
            tableName)
        > 0;
  }

  private boolean foreignKeyExists(String tableName, String constraintName) {
    return count(
            "SELECT COUNT(*) FROM information_schema.table_constraints "
                + "WHERE constraint_schema = DATABASE() AND table_name = ? "
                + "AND constraint_name = ? AND constraint_type = 'FOREIGN KEY'",
            tableName,
            constraintName)
        > 0;
  }

  private boolean indexExists(String tableName, String indexName, boolean unique) {
    return count(
            "SELECT COUNT(*) FROM information_schema.statistics "
                + "WHERE table_schema = DATABASE() AND table_name = ? "
                + "AND index_name = ? AND non_unique = ?",
            tableName,
            indexName,
            unique ? 0 : 1)
        > 0;
  }

  private int count(String sql, Object... args) {
    return jdbcTemplate.queryForObject(sql, Integer.class, args);
  }
}
```

`flyway_schema_history`를 포함한 Table 수는 30개로 검증한다.

- [ ] **Step 2: Migration 부재 또는 Docker 부재로 실패하는지 확인**

```powershell
backend\gradlew.bat test --tests "*DatabaseMigrationIntegrationTest"
```

Expected with Docker: Migration Table 부재로 FAIL. Expected in current environment: Docker Runtime을 찾지 못해 FAIL하며 테스트를 비활성화하지 않는다.

### Task 3: Flyway V1과 ERDCloud 논리·물리 스키마 작성

**Files:**
- Create: `backend/src/main/resources/db/migration/V1__create_initial_schema.sql`
- Create: `docs/database/initial-schema-design.md`

**Interfaces:**
- Consumes: SQL Preview 29개 테이블과 `docs/superpowers/specs/2026-07-21-mysql-initial-schema-design.md`
- Produces: MySQL 8.4.10 실행 가능 DDL, ERDCloud Import SQL, 논리·물리명 문서

- [ ] **Step 1: 29개 Table을 FK 의존 순서로 작성**

다음 순서를 정확히 사용한다.

```text
users
children
drawing_types
consent_terms
auth_accounts
refresh_tokens
expert_profiles
expert_follows
guardian_child_relations
consent_records
drawing_sessions
stroke_batches
drawing_assets
ai_question_templates
conversation_sessions
conversation_messages
analyses
analysis_visual_features
analysis_behavior_features
analysis_detected_objects
analysis_observation_results
analysis_unused_inputs
analysis_conversation_summaries
reports
community_posts
comments
post_likes
notifications
audit_logs
```

각 Table은 다음 MySQL 8.4 형식을 사용한다.

```sql
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT COMMENT '사용자 ID',
    role VARCHAR(20) NOT NULL COMMENT '사용자 역할',
    nickname VARCHAR(50) NULL COMMENT '닉네임',
    account_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '계정 상태',
    profile_image_url VARCHAR(1000) NULL COMMENT '프로필 이미지 URL',
    notification_settings_json JSON NULL COMMENT '알림 설정',
    is_completed BOOLEAN NOT NULL DEFAULT FALSE COMMENT '온보딩 완료 여부',
    last_login_at DATETIME(6) NULL COMMENT '마지막 로그인 일시',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '생성 일시',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '수정 일시',
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT ck_users_role CHECK (role IN ('GUARDIAN', 'EXPERT', 'ADMIN')),
    CONSTRAINT ck_users_account_status
        CHECK (account_status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'WITHDRAWN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='사용자';
```

나머지 Table은 SQL Preview의 모든 컬럼을 누락 없이 옮기고 다음 명칭 수정과 공통 규칙을 적용한다.

```text
conversation_sessions.conversation_id -> drawing_session_id
analysis_detected_objects.drawing_image_id -> drawing_asset_id
analysis_behavior_features.tool_chnage_count -> tool_change_count
analysis_conversation_summaries.conversation_sumaary_id -> conversation_summary_id
expert_follows.Key -> 삭제
conversation_messages.bounding_box -> 삭제하고 target_object_json으로 통합
```

모든 식별 PK는 `BIGINT NOT NULL AUTO_INCREMENT`, 모든 생성·수정 시각은 `DATETIME(6)`, 모든 Table은 InnoDB와 `utf8mb4_0900_ai_ci`를 사용한다. Table Comment에는 한글 논리명, Column Comment에는 한글 논리 필드명을 작성한다.

- [ ] **Step 2: Unique를 정확히 추가**

```text
uk_auth_accounts_provider_subject(provider, provider_subject)
uk_auth_accounts_local_login_email(local_login_email)
uk_stroke_batches_session_sequence(drawing_session_id, batch_sequence)
uk_guardian_child_relations_guardian_child(guardian_user_id, child_id)
uk_analyses_idempotency_key(idempotency_key)
uk_conversation_messages_session_sequence(conversation_session_id, message_sequence)
uk_post_likes_post_user(post_id, user_id)
uk_expert_follows_guardian_expert(guardian_user_id, expert_profile_id)
uk_reports_session_version(drawing_session_id, report_version)
uk_expert_profiles_users_id(users_id)
uk_drawing_types_code(code)
uk_consent_terms_code_version(term_code, version)
```

`auth_accounts.local_login_email`은 다음 생성 컬럼을 사용한다.

```sql
local_login_email VARCHAR(255)
    GENERATED ALWAYS AS (
        CASE WHEN provider = 'LOCAL' THEN login_email ELSE NULL END
    ) STORED COMMENT 'Local 인증 이메일 중복 검사용 생성값'
```

- [ ] **Step 3: FK와 삭제 정책 추가**

완전 종속 데이터는 CASCADE, 핵심 기록은 RESTRICT, Nullable 선택 참조는 SET NULL을 사용한다. FK 이름과 방향은 설계 문서의 “FK와 삭제 정책”을 그대로 적용하고 다음 대표 이름을 테스트와 일치시킨다.

```text
fk_drawing_sessions_child_id
fk_analyses_drawing_session_id
fk_conversation_messages_session_id
fk_comments_post_id
```

- [ ] **Step 4: 조회 Index 추가**

최소 다음 Index를 생성한다.

```text
idx_drawing_sessions_child_id(child_id, created_at)
idx_analyses_drawing_session_id(drawing_session_id, requested_at)
idx_notifications_recipient_created_at(recipient_user_id, created_at)
idx_reports_drawing_session_id(drawing_session_id, created_at)
idx_conversation_sessions_drawing_session_id(drawing_session_id)
idx_conversation_messages_parent_message_id(parent_message_id)
idx_comments_author_user_id(author_user_id)
idx_community_posts_author_created_at(author_user_id, created_at)
idx_audit_logs_resource(resource_type, resource_id, created_at)
```

- [ ] **Step 5: 논리·물리 설계 문서 작성**

`docs/database/initial-schema-design.md`에 다음을 실제 값으로 작성한다.

- 29개 Table의 한글 논리명과 영문 물리명
- Preview 수정 전후 6개 항목
- PK, FK, Unique, Index 이름과 대상 컬럼
- CASCADE, RESTRICT, SET NULL 적용 관계와 이유
- JSON Column 목록
- 상태값 Check Constraint
- ERDCloud에 `V1__create_initial_schema.sql`을 Import하는 절차
- 제외한 확장 Table 목록과 후속 Migration 원칙

- [ ] **Step 6: SQL 정적 검사**

```powershell
rg -n 'CREATE DATABASE|DROP DATABASE|DROP TABLE|TRUNCATE TABLE|CREATE USER|ALTER USER|GRANT' backend/src/main/resources/db/migration
rg -n 'tool_chnage|conversation_sumaary|conversation_id|drawing_image_id|`Key`' backend/src/main/resources/db/migration
```

Expected: 두 명령 모두 출력 없음.

### Task 4: Migration 통합 테스트 GREEN 확인

**Files:**
- Verify: `backend/src/main/resources/db/migration/V1__create_initial_schema.sql`
- Verify: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Consumes: Task 2의 실패 테스트와 Task 3의 Migration
- Produces: MySQL 8.4.10에서 검증된 초기 스키마

- [ ] **Step 1: Testcontainers 테스트 실행**

```powershell
backend\gradlew.bat test --tests "*DatabaseMigrationIntegrationTest"
```

Expected with Docker: 3 tests, 0 failures. Current environment에서 Docker가 없으면 실제 오류를 기록하고 다음 단계의 정적 검증은 계속한다.

- [ ] **Step 2: H2 Context 회귀 테스트 실행**

```powershell
backend\gradlew.bat test --tests "*B209ApplicationTests"
```

Expected: 1 test, 0 failures.

### Task 5: 환경 변수와 Database 문서화

**Files:**
- Modify: `.env.example`
- Modify: `README.md`

**Interfaces:**
- Consumes: Tasks 1~4의 실제 설정과 명령
- Produces: Local DB 준비, Profile, Migration, ERDCloud와 테스트 실행 안내

- [ ] **Step 1: `.env.example` DB 기본값 정리**

```dotenv
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=dodam
DB_USERNAME=root
DB_PASSWORD=
```

기존 다른 환경 변수는 삭제하지 않는다.

- [ ] **Step 2: README Database 절 추가**

다음 실제 정보를 추가하고 기존 README 내용을 유지한다.

```text
MySQL: 8.4.10 LTS
H2: test Profile 전용
Testcontainers MySQL: integration-test Profile 전용
Migration: Flyway
Character Set: utf8mb4
Collation: utf8mb4_0900_ai_ci
Storage Engine: InnoDB
```

Local Database 생성 예시는 다음만 사용한다.

```sql
CREATE DATABASE dodam
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
```

Spring Boot는 `.env`를 자동으로 읽지 않으며 IntelliJ Run Configuration 또는 운영체제 환경 변수로 전달한다고 기록한다. 공용·운영 환경에서는 `root` 대신 `dodam_app` 전용 계정을 권장한다.

- [ ] **Step 3: Migration과 ERDCloud 규칙 문서화**

- 위치: `backend/src/main/resources/db/migration`
- 파일명: `V{버전}__{설명}.sql`
- 적용된 Migration 수정 금지
- 변경 시 새 Migration 추가
- `ddl-auto=validate`, Flyway Clean 비활성화
- ERDCloud에는 `V1__create_initial_schema.sql` Import

- [ ] **Step 4: 실행 명령 문서화**

```powershell
backend\gradlew.bat clean test
backend\gradlew.bat test --tests "*DatabaseMigrationIntegrationTest"
backend\gradlew.bat bootRun --args="--spring.profiles.active=local"
```

Docker가 Testcontainers 실행에 필요하고 Local MySQL Database는 Flyway가 생성하지 않는다고 명시한다.

### Task 6: 전체 검증과 결과 정리

**Files:**
- Verify: 전체 작업 트리

**Interfaces:**
- Consumes: Tasks 1~5의 전체 결과
- Produces: Commit 가능한 검증 결과와 Jira/MR 정보

- [ ] **Step 1: 전체 테스트 실행**

```powershell
backend\gradlew.bat clean test
```

Expected with Docker: H2와 Integration Test 모두 성공. Docker 부재 시 Integration Test 실패를 숨기지 않고 H2 단독 결과와 구분한다.

- [ ] **Step 2: Spotless 검사**

```powershell
backend\gradlew.bat spotlessCheck
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Javadoc 생성**

```powershell
backend\gradlew.bat javadoc
Test-Path backend\build\docs\javadoc\index.html
```

Expected: 경고 없이 BUILD SUCCESSFUL, `True`.

- [ ] **Step 4: Local MySQL 확인**

3306 Port와 MySQL Client 사용 가능 여부를 확인한다. 준비된 경우 `SHOW DATABASES`와 Local `bootRun`을 실행한다. 현재처럼 MySQL Client나 `dodam` Database를 확인할 수 없으면 미검증으로 보고하고 성공으로 표시하지 않는다.

- [ ] **Step 5: Git과 비밀정보 검사**

```powershell
git status --short
git diff --check
git diff
git ls-files --others --exclude-standard
```

Migration에 금지 SQL, 실제 DB 비밀번호, `.env`, 빌드 산출물, Entity·Repository·API 코드가 포함되지 않았는지 확인한다.

- [ ] **Step 6: Commit 없이 결과 보고**

권장 Commit은 `build(database): S15P11B209-132 MySQL 연결 및 초기 DB 스키마 구성`, MR Source는 `build/mysql-db-schema`, Target은 `develop`으로 보고한다. 사용자 요청 전에는 Stage, Commit, Push, MR 생성 또는 Merge를 수행하지 않는다.
