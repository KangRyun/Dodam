# MVP Mock Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `local` Profile에서 명시적으로 활성화할 때만 보호자·아동·그림 활동 개발용 Mock 데이터를 멱등하게 구성한다.

**Architecture:** `@Profile("local")`과 `@ConditionalOnProperty`로 격리된 Configuration이 애플리케이션 시작 후 SQL 리소스를 실행한다. Seed는 음수 고정 ID로 일반 Auto Increment 데이터와 식별 공간을 분리하고, MySQL Testcontainers에서 두 번 실행해 멱등성과 외래 키 정합성을 검증한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring JDBC, MySQL 8.4, Flyway, JUnit 5, AssertJ, Testcontainers

## Global Constraints

- 기존 Flyway `V1`~`V7` Migration을 수정하지 않는다.
- `local` Profile과 `APP_MOCK_DATA_ENABLED=true`가 함께 적용된 경우에만 Seed를 실행한다.
- OAuth/JWT 인증 우회와 실제 Provider Token을 추가하지 않는다.
- 물리 저장 파일이 필요한 자산·완료 활동·분석·대화·리포트는 Seed하지 않는다.
- 기존 데이터는 삭제하거나 변경하지 않는다.
- `.idea/modules.xml`의 기존 사용자 변경은 Commit에서 제외한다.

---

## File Structure

- Create `backend/src/main/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataConfiguration.java`: Profile과 설정 조건을 적용하고 SQL 실행 `ApplicationRunner`를 제공한다.
- Create `backend/src/main/resources/db/mock/mvp-mock-data.sql`: 재실행 가능한 MVP Seed DML을 보관한다.
- Create `backend/src/test/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataConfigurationTest.java`: Profile과 Property 조건을 검증한다.
- Create `backend/src/test/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataIntegrationTest.java`: 실제 MySQL Schema에서 Seed 멱등성과 관계를 검증한다.
- Modify `backend/src/main/resources/application-local.yml`: 환경 변수 기반 활성화 속성을 선언한다.
- Modify `README.md`: 활성화 방법, 데이터 범위와 인증 제한을 문서화한다.

### Task 1: Local 전용 초기화 조건

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataConfigurationTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataConfiguration.java`
- Modify: `backend/src/main/resources/application-local.yml`

**Interfaces:**
- Consumes: `DataSource`, `classpath:db/mock/mvp-mock-data.sql`
- Produces: `ApplicationRunner mvpMockDataInitializer(DataSource dataSource)`

- [ ] **Step 1: 조건 검증 테스트 작성**

`ApplicationContextRunner`에 Mock `DataSource`를 등록하고 다음 세 경우를 검증한다.

```java
@Test
void enablesInitializerOnlyForLocalProfileWithExplicitFlag() {
  contextRunner
      .withPropertyValues("spring.profiles.active=local", "app.mock-data.enabled=true")
      .run(context -> assertThat(context).hasBean("mvpMockDataInitializer"));
}

@Test
void disablesInitializerWhenFlagIsFalse() {
  contextRunner
      .withPropertyValues("spring.profiles.active=local", "app.mock-data.enabled=false")
      .run(context -> assertThat(context).doesNotHaveBean("mvpMockDataInitializer"));
}

@Test
void disablesInitializerOutsideLocalProfile() {
  contextRunner
      .withPropertyValues("spring.profiles.active=test", "app.mock-data.enabled=true")
      .run(context -> assertThat(context).doesNotHaveBean("mvpMockDataInitializer"));
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run:

```powershell
gradlew.bat test --tests "*MvpMockDataConfigurationTest"
```

Expected: `MvpMockDataConfiguration`이 없어 컴파일 또는 Context 생성이 실패한다.

- [ ] **Step 3: 최소 Configuration 구현**

```java
@Configuration(proxyBeanMethods = false)
@Profile("local")
@ConditionalOnProperty(prefix = "app.mock-data", name = "enabled", havingValue = "true")
public class MvpMockDataConfiguration {

  /**
   * Flyway 적용이 끝난 로컬 DB에 MVP 개발 데이터를 주입하는 Runner를 제공한다.
   *
   * @param dataSource 로컬 MySQL 연결을 제공하는 DataSource
   * @return 애플리케이션 시작 시 Seed SQL을 한 번 실행하는 Runner
   */
  @Bean
  ApplicationRunner mvpMockDataInitializer(DataSource dataSource) {
    return arguments -> {
      ResourceDatabasePopulator populator =
          new ResourceDatabasePopulator(new ClassPathResource("db/mock/mvp-mock-data.sql"));
      populator.execute(dataSource);
    };
  }
}
```

`application-local.yml`에는 기본 비활성 설정을 추가한다.

```yaml
app:
  mock-data:
    enabled: ${APP_MOCK_DATA_ENABLED:false}
```

- [ ] **Step 4: 단위 테스트 통과 확인**

Run:

```powershell
gradlew.bat test --tests "*MvpMockDataConfigurationTest"
```

Expected: 3 tests passed.

- [ ] **Step 5: Task 1 변경 명시적 Stage**

```powershell
git add -- backend/src/main/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataConfiguration.java backend/src/test/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataConfigurationTest.java backend/src/main/resources/application-local.yml
```

Task 사이에는 별도 Commit을 만들지 않고, 이슈 구현 완료 후 하나의 기능 Commit으로 정리한다.

### Task 2: 멱등 Seed SQL과 MySQL 검증

**Files:**
- Create: `backend/src/main/resources/db/mock/mvp-mock-data.sql`
- Create: `backend/src/test/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataIntegrationTest.java`

**Interfaces:**
- Consumes: `MvpMockDataConfiguration.mvpMockDataInitializer(DataSource)`
- Produces: 사용자 `-136001`, 인증 계정 `-136001`, 아동 `-136001`, 보호자 관계 `-136001`, 그림 유형 `-136001`, 진행 중 활동 `-136001`

- [ ] **Step 1: MySQL 통합 테스트 작성**

Testcontainers MySQL에 Flyway Migration을 적용한 Spring Context를 사용한다. Bean 메서드로 얻은 Runner를 두 번 실행한 뒤 다음을 검증한다.

```java
runner.run(new DefaultApplicationArguments(new String[0]));
runner.run(new DefaultApplicationArguments(new String[0]));

assertThat(count("users", -136001L)).isEqualTo(1);
assertThat(count("auth_accounts", -136001L)).isEqualTo(1);
assertThat(count("children", -136001L)).isEqualTo(1);
assertThat(count("guardian_child_relations", -136001L)).isEqualTo(1);
assertThat(count("drawing_types", -136001L)).isEqualTo(1);
assertThat(count("drawing_sessions", -136001L)).isEqualTo(1);
assertThat(
        jdbcTemplate.queryForMap(
            "SELECT child_id, drawing_type_id, started_by_user_id, session_status, current_stage "
                + "FROM drawing_sessions WHERE id = -136001"))
    .containsEntry("child_id", -136001L)
    .containsEntry("drawing_type_id", -136001L)
    .containsEntry("started_by_user_id", -136001L)
    .containsEntry("session_status", "IN_PROGRESS")
    .containsEntry("current_stage", "DRAWING");
```

- [ ] **Step 2: SQL 부재로 실패 확인**

Run:

```powershell
gradlew.bat test --tests "*MvpMockDataIntegrationTest"
```

Expected: `db/mock/mvp-mock-data.sql`을 찾지 못해 실패한다.

- [ ] **Step 3: Seed SQL 작성**

각 Table은 음수 고정 ID를 사용하고 기존 Row를 변경하지 않는 no-op upsert로 작성한다.

```sql
INSERT INTO users (id, role, nickname, account_status, is_completed)
VALUES (-136001, 'GUARDIAN', '도담 보호자', 'ACTIVE', TRUE)
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO auth_accounts
    (id, user_id, provider, provider_subject, provider_email, provider_email_verified_at)
VALUES
    (-136001, -136001, 'KAKAO', 'mock-s15p11b209-136-guardian',
     'guardian@example.invalid', CURRENT_TIMESTAMP(6))
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO children
    (id, nickname, birth_date, question_difficulty, tutorial_status, profile_status)
VALUES
    (-136001, '도담이', '2020-01-15', 'PRESCHOOL', 'COMPLETED', 'ACTIVE')
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO guardian_child_relations
    (id, guardian_user_id, child_id, relationship_type)
VALUES (-136001, -136001, -136001, 'MOTHER')
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO drawing_types
    (id, code, name, activity_category, selectable_by,
     recommended_age_min, recommended_age_max, guide_text, is_active, display_order)
VALUES
    (-136001, 'MVP_FREE_DRAWING', '자유롭게 그리기', 'GENERAL', 'BOTH',
     3, 12, '좋아하는 것을 자유롭게 그려 보세요.', TRUE, 1)
ON DUPLICATE KEY UPDATE id = id;

INSERT INTO drawing_sessions
    (id, child_id, drawing_type_id, started_by_user_id, input_method, title,
     session_status, current_stage, idempotency_key)
VALUES
    (-136001, -136001, -136001, -136001, 'CANVAS', '진행 중인 자유 그림',
     'IN_PROGRESS', 'DRAWING', 'mock-s15p11b209-136-session')
ON DUPLICATE KEY UPDATE id = id;
```

- [ ] **Step 4: 통합 테스트 통과 확인**

Run:

```powershell
gradlew.bat test --tests "*MvpMockDataIntegrationTest"
```

Expected: 1 test passed. Docker 미가동 시 Testcontainers 실패 원문을 보존하고 미실행 사유로 보고한다.

- [ ] **Step 5: Task 2 변경 명시적 Stage**

```powershell
git add -- backend/src/main/resources/db/mock/mvp-mock-data.sql backend/src/test/java/com/ssafy/b209/infrastructure/mockdata/MvpMockDataIntegrationTest.java
```

### Task 3: 사용 방법 문서화

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: `APP_MOCK_DATA_ENABLED`
- Produces: local 실행 방법과 인증·데이터 범위 제한 안내

- [ ] **Step 1: README에 Local Mock 데이터 절 추가**

Local Profile 설명에 다음 내용을 기록한다.

```markdown
### MVP Mock 데이터

`local` Profile에서 `APP_MOCK_DATA_ENABLED=true`를 명시하면 보호자, 소셜 인증 계정,
아동, 보호자·아동 관계, 그림 유형과 진행 중 그림 활동 개발용 데이터가 주입됩니다.
동일 데이터는 재실행해도 중복 생성되지 않습니다.

Mock 데이터는 OAuth 또는 JWT 인증을 우회하지 않으며 실제 Provider Token을 포함하지
않습니다. 운영 환경에서는 이 설정을 활성화하지 않습니다.
```

- [ ] **Step 2: 문서 형식 검사**

Run:

```powershell
gradlew.bat spotlessCheck
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: README 명시적 Stage**

```powershell
git add -- README.md
```

### Task 4: 전체 검증과 기능 Commit

**Files:**
- Verify: 전체 변경 파일
- Preserve: `.idea/modules.xml`

**Interfaces:**
- Consumes: Task 1~3 산출물
- Produces: 검증 완료된 S15P11B209-136 기능 Commit

- [ ] **Step 1: 변경 범위와 금지 파일 확인**

Run:

```powershell
git status --short
git diff --cached --check
git diff --cached --name-only
```

Expected: 이슈 파일만 Stage되고 `.idea/modules.xml`은 Stage되지 않는다.

- [ ] **Step 2: 전체 테스트 실행**

Run:

```powershell
gradlew.bat clean test
```

Expected: `BUILD SUCCESSFUL`, 기존 테스트 삭제·비활성화 없음.

- [ ] **Step 3: Spotless와 Javadoc 실행**

Run:

```powershell
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

Expected: 두 명령 모두 `BUILD SUCCESSFUL`, `backend/build/docs/javadoc/index.html` 생성.

- [ ] **Step 4: 기능 Commit 생성**

```powershell
git commit -m "feat(mock): S15P11B209-136 MVP 테스트 데이터 구성"
```

- [ ] **Step 5: Push·MR·Merge 전 최종 확인**

Run:

```powershell
git status --short
git log -2 --oneline
```

Expected: `.idea/modules.xml`만 남고 설계 및 기능 Commit이 현재 Issue Branch에 존재한다.
