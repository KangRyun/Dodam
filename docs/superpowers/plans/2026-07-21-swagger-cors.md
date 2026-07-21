# Swagger UI and CORS Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Springdoc OpenAPI 기반 Swagger UI와 `/api/v1/**` 전용 Spring MVC CORS 정책을 추가하고 기존 공통 응답 JSON 계약을 Schema로 문서화한다.

**Architecture:** `OpenApiConfig`가 OpenAPI 기본 정보와 `api-v1` Group을 구성하고, `CorsProperties`와 `CorsConfig`가 Profile별 Origin과 MVC CORS 정책을 분리한다. 공통 응답 객체에는 문서 Annotation만 추가하며 실제 Endpoint가 필요한 검증은 테스트 Source의 Controller로 수행한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Gradle 8.14.3, Spring Web MVC, Springdoc OpenAPI 2.8.17, JUnit 5, AssertJ, MockMvc, Jackson, Spotless

## Global Constraints

- 기준 브랜치는 `origin/develop`의 `77da34a`이며 작업 브랜치는 `feat/swagger-cors`다.
- Jira 이슈는 `S15P11B209-135`이며 Branch 이름에는 이슈 코드를 넣지 않는다.
- 사용자가 별도로 요청하기 전에는 Commit, Push와 Merge Request를 수행하지 않는다.
- Swagger Group과 CORS 적용 범위는 기존 README 계약인 `/api/v1/**`다.
- Local Origin은 `http://localhost:3000`, `http://127.0.0.1:3000`만 허용한다.
- 기본 및 `integration-test` Profile은 빈 Origin 목록을 사용하고 운영 Origin을 추측하지 않는다.
- Java, Spring Boot, Gradle Wrapper, Spotless, Javadoc, DB, Flyway와 기존 Profile 구조를 변경하지 않는다.
- 기존 성공·오류 응답의 Factory Method, JSON 필드명·순서·null 직렬화와 불변 조건을 변경하지 않는다.
- Spring Security, JWT, Security Scheme, 실제 도메인 API와 Production Sample Controller를 추가하지 않는다.
- `CorsFilter`, `CorsConfigurationSource`, `@CrossOrigin`, wildcard Origin과 wildcard Header를 사용하지 않는다.
- 새 public Java 타입에는 실제 책임을 설명하는 한국어 Javadoc을 작성한다.

---

## File Structure

- Modify: `backend/build.gradle` — Springdoc Web MVC UI starter 2.8.17 추가
- Create: `backend/src/main/java/com/ssafy/b209/global/config/OpenApiConfig.java` — OpenAPI Info와 `api-v1` Group 구성
- Create: `backend/src/main/java/com/ssafy/b209/global/config/CorsProperties.java` — Origin 목록 정규화·검증·불변 보관
- Create: `backend/src/main/java/com/ssafy/b209/global/config/CorsConfig.java` — `/api/v1/**` MVC CORS 정책 구성
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/ApiResponse.java` — 성공 응답 Schema 설명
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/ApiErrorResponse.java` — 오류 응답 Schema 설명
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/FieldErrorDetail.java` — Validation 필드 오류 Schema 설명
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/ValidationErrorData.java` — Validation 상세 Schema 설명
- Modify: `backend/src/main/resources/application.yml` — 기본 빈 Origin 목록
- Modify: `backend/src/main/resources/application-local.yml` — Local Origin 두 개
- Modify: `backend/src/main/resources/application-test.yml` — 테스트 Origin
- Modify: `backend/src/main/resources/application-integration-test.yml` — 통합 테스트 빈 Origin 목록
- Create: `backend/src/test/java/com/ssafy/b209/global/config/OpenApiConfigTest.java` — OpenAPI Bean 단위 테스트
- Create: `backend/src/test/java/com/ssafy/b209/global/config/CorsPropertiesTest.java` — Origin 정규화·검증 단위 테스트
- Create: `backend/src/test/java/com/ssafy/b209/global/config/CorsConfigTest.java` — MockMvc CORS 동작 테스트
- Create: `backend/src/test/java/com/ssafy/b209/global/config/SwaggerEndpointTest.java` — Swagger Endpoint, Group과 공통 Schema 통합 테스트
- Modify: `README.md` — Swagger 접속법과 CORS 운영 규칙

---

### Task 1: Springdoc 의존성과 OpenAPI 기본 구성

**Files:**
- Modify: `backend/build.gradle`
- Create: `backend/src/test/java/com/ssafy/b209/global/config/OpenApiConfigTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/config/OpenApiConfig.java`

**Interfaces:**
- Produces: `OpenAPI openAPI()`, `GroupedOpenApi apiV1Group()` Spring Bean
- Group contract: name `api-v1`, paths `/api/v1/**`

- [ ] **Step 1: Springdoc starter를 추가하고 의존성 해석을 확인한다**

```groovy
implementation 'org.springdoc:springdoc-openapi-starter-webmvc-ui:2.8.17'
```

Run:

```powershell
gradlew.bat dependencyInsight --dependency springdoc-openapi --configuration runtimeClasspath
```

Expected: `springdoc-openapi-starter-webmvc-ui:2.8.17`과 동일 계열의 전이 의존성만 해석되고 Springfox는 없다.

- [ ] **Step 2: OpenAPI Bean 계약을 나타내는 실패 테스트를 작성한다**

`OpenApiConfigTest`에서 `ApplicationContextRunner`에 `OpenApiConfig`를 등록하고 다음을 검증한다.

```java
assertThat(openApi.getInfo().getTitle())
    .isEqualTo("아동 그림·대화 기반 정서 지원 서비스 API");
assertThat(openApi.getInfo().getDescription()).isEqualTo("백엔드 REST API 명세");
assertThat(openApi.getInfo().getVersion()).isEqualTo("v1");
assertThat(openApi.getServers()).isNullOrEmpty();
assertThat(openApi.getComponents()).isNull();

assertThat(groupedOpenApi.getGroup()).isEqualTo("api-v1");
assertThat(groupedOpenApi.getPathsToMatch()).containsExactly("/api/v1/**");
```

- [ ] **Step 3: OpenAPI 설정 테스트가 예상한 이유로 실패하는지 확인한다**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.config.OpenApiConfigTest"
```

Expected: `OpenApiConfig`가 아직 없어 compile 단계에서 실패한다.

- [ ] **Step 4: 최소 OpenAPI 설정을 구현한다**

```java
@Configuration
public class OpenApiConfig {

  @Bean
  public OpenAPI openAPI() {
    return new OpenAPI()
        .info(
            new Info()
                .title("아동 그림·대화 기반 정서 지원 서비스 API")
                .description("백엔드 REST API 명세")
                .version("v1"));
  }

  @Bean
  public GroupedOpenApi apiV1Group() {
    return GroupedOpenApi.builder().group("api-v1").pathsToMatch("/api/v1/**").build();
  }
}
```

클래스에는 OpenAPI 기본 정보와 Group 구성 책임, Endpoint 문서는 Controller가 담당한다는 점, Security Scheme을 포함하지 않는다는 점을 한국어 Javadoc으로 작성한다. 단순 Bean Method에는 형식적인 Javadoc을 추가하지 않는다.

- [ ] **Step 5: OpenAPI 설정 테스트를 통과시킨다**

Run: Task 1 Step 3과 동일

Expected: PASS.

---

### Task 2: CORS Origin 설정 객체

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/global/config/CorsPropertiesTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/config/CorsProperties.java`

**Interfaces:**
- Produces: `CorsProperties(List<String> allowedOrigins)`
- Produces: `List<String> allowedOrigins()` — 불변이며 정규화된 Origin 목록

- [ ] **Step 1: 정규화와 불변성 실패 테스트를 작성한다**

```java
var source = new ArrayList<>(List.of(
    " http://localhost:3000 ",
    "",
    "http://localhost:3000",
    "http://127.0.0.1:3000"));

var properties = new CorsProperties(source);
source.clear();

assertThat(properties.allowedOrigins())
    .containsExactly("http://localhost:3000", "http://127.0.0.1:3000");
assertThatThrownBy(() -> properties.allowedOrigins().add("https://example.com"))
    .isInstanceOf(UnsupportedOperationException.class);
assertThat(new CorsProperties(null).allowedOrigins()).isEmpty();
```

- [ ] **Step 2: 잘못된 Origin 실패 테스트를 작성한다**

다음을 각각 `IllegalArgumentException`으로 검증한다.

```text
*
http://localhost:3000/
http://localhost:3000/api
localhost:3000
ftp://localhost:3000
http://user@localhost:3000
http://localhost:3000?mode=test
http://localhost:3000#fragment
```

- [ ] **Step 3: 테스트가 `CorsProperties` 부재로 실패하는지 확인한다**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.config.CorsPropertiesTest"
```

Expected: compile failure because `CorsProperties` does not exist.

- [ ] **Step 4: Origin 정규화와 검증을 최소 구현한다**

```java
@ConfigurationProperties(prefix = "app.cors")
public record CorsProperties(List<String> allowedOrigins) {

  public CorsProperties {
    allowedOrigins = normalize(allowedOrigins);
  }

  private static List<String> normalize(List<String> origins) {
    if (origins == null) {
      return List.of();
    }
    return origins.stream()
        .filter(Objects::nonNull)
        .map(String::trim)
        .filter(origin -> !origin.isEmpty())
        .peek(CorsProperties::validateOrigin)
        .distinct()
        .toList();
  }

  private static void validateOrigin(String origin) {
    URI uri;
    try {
      uri = URI.create(origin);
    } catch (IllegalArgumentException ignored) {
      throw new IllegalArgumentException("Invalid CORS origin");
    }

    boolean validScheme = "http".equals(uri.getScheme()) || "https".equals(uri.getScheme());
    int port = uri.getPort();
    String rawAuthority = uri.getRawAuthority();
    boolean validPort = rawAuthority != null && port <= 65535 && !rawAuthority.endsWith(":");
    boolean originOnly =
        uri.getHost() != null
            && uri.getUserInfo() == null
            && (uri.getRawPath() == null || uri.getRawPath().isEmpty())
            && uri.getRawQuery() == null
            && uri.getRawFragment() == null;
    if (!validScheme || !validPort || !originOnly || "*".equals(origin)) {
      throw new IllegalArgumentException("Invalid CORS origin");
    }
  }
}
```

클래스 Javadoc에는 환경별 Origin 보관 책임, 빈 목록의 Cross-Origin 비허용 의미와 방어적 불변 처리를 설명한다. 예외 메시지에는 설정값 원문을 포함하지 않는다.

- [ ] **Step 5: 단위 테스트를 통과시키고 불필요한 구현을 제거한다**

Run: Task 2 Step 3과 동일

Expected: PASS.

---

### Task 3: Profile별 설정과 Spring MVC CORS 정책

**Files:**
- Modify: `backend/src/main/resources/application.yml`
- Modify: `backend/src/main/resources/application-local.yml`
- Modify: `backend/src/main/resources/application-test.yml`
- Modify: `backend/src/main/resources/application-integration-test.yml`
- Create: `backend/src/test/java/com/ssafy/b209/global/config/CorsConfigTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/global/config/CorsConfig.java`

**Interfaces:**
- Consumes: `CorsProperties.allowedOrigins()`
- Produces: `/api/v1/**` Spring MVC CORS mapping

- [ ] **Step 1: Profile별 Origin을 설정한다**

기본 및 integration-test:

```yaml
app:
  cors:
    allowed-origins: []
```

local:

```yaml
app:
  cors:
    allowed-origins:
      - http://localhost:3000
      - http://127.0.0.1:3000
```

test:

```yaml
app:
  cors:
    allowed-origins:
      - http://localhost:3000
```

- [ ] **Step 2: 실제 요청과 Preflight 실패 테스트를 작성한다**

`@WebMvcTest`와 테스트 전용 `/api/v1/test/cors` Controller를 사용하고 `CorsConfig`를 Import한다. 다음 요청을 검증한다.

```java
mockMvc.perform(get("/api/v1/test/cors").header(ORIGIN, "http://localhost:3000"))
    .andExpect(status().isOk())
    .andExpect(header().string(ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"));

mockMvc.perform(options("/api/v1/test/cors")
        .header(ORIGIN, "http://localhost:3000")
        .header(ACCESS_CONTROL_REQUEST_METHOD, "GET")
        .header(ACCESS_CONTROL_REQUEST_HEADERS, "Content-Type"))
    .andExpect(status().isOk())
    .andExpect(header().string(ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"))
    .andExpect(header().string(ACCESS_CONTROL_MAX_AGE, "3600"))
    .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_CREDENTIALS));
```

- [ ] **Step 3: 거부와 범위 제한 실패 테스트를 작성한다**

- 비허용 Origin `https://not-allowed.example`의 Preflight는 403이며 Allow-Origin이 없다.
- `TRACE`는 Allow-Methods에 포함되지 않는다.
- `/outside/test/cors`에는 허용 Origin 요청이어도 Allow-Origin이 없다.
- 허용 응답은 wildcard가 아니다.

- [ ] **Step 4: CORS 테스트가 설정 클래스 부재로 실패하는지 확인한다**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.config.CorsConfigTest"
```

Expected: `CorsConfig`가 없어 CORS Header assertion이 실패하거나 compile 단계에서 실패한다.

- [ ] **Step 5: Spring MVC CORS 설정을 구현한다**

```java
@Configuration
@EnableConfigurationProperties(CorsProperties.class)
public class CorsConfig implements WebMvcConfigurer {

  private final CorsProperties corsProperties;

  public CorsConfig(CorsProperties corsProperties) {
    this.corsProperties = corsProperties;
  }

  @Override
  public void addCorsMappings(CorsRegistry registry) {
    registry
        .addMapping("/api/v1/**")
        .allowedOrigins(corsProperties.allowedOrigins().toArray(String[]::new))
        .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
        .allowedHeaders("Content-Type", "Accept", "Authorization")
        .allowCredentials(false)
        .maxAge(3600);
  }
}
```

클래스 Javadoc에는 등록된 Origin의 `/api/v1/**` Cross-Origin 허용 책임, Origin 공급 주체와 CORS가 인증·인가를 대체하지 않는다는 점을 작성한다.

- [ ] **Step 6: CORS 테스트를 통과시킨다**

Run: Task 3 Step 4와 동일

Expected: PASS.

---

### Task 4: 공통 응답 OpenAPI Schema Annotation

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/ApiResponse.java`
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/ApiErrorResponse.java`
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/FieldErrorDetail.java`
- Modify: `backend/src/main/java/com/ssafy/b209/global/response/ValidationErrorData.java`
- Create: `backend/src/test/java/com/ssafy/b209/global/config/SwaggerEndpointTest.java`

**Interfaces:**
- Consumes: 기존 공통 응답 타입의 현재 public API
- Produces: Springdoc이 해석할 클래스·property Schema metadata

- [ ] **Step 1: 테스트 전용 OpenAPI Endpoint와 Schema 실패 테스트를 작성한다**

`src/test/java`의 nested 또는 package-private `@RestController`가 다음 타입을 반환하게 한다.

```text
GET /api/v1/test/success -> ApiResponse<TestData>
GET /api/v1/test/error -> ApiErrorResponse<Void>
GET /api/v1/test/validation-error -> ApiErrorResponse<ValidationErrorData>
GET /outside/test -> String
```

`/v3/api-docs/api-v1`의 `components.schemas`를 순회해 다음 property 집합을 가진 Schema가 존재하는지 검증한다.

```text
ApiResponse: success, code, message, data
ApiErrorResponse: success, code, message, data
FieldErrorDetail: field, message
ValidationErrorData: fieldErrors, globalErrors
```

모든 Schema에 다음 내부 property가 없는지 검증한다.

```text
httpStatus, errorCode, successCode, stackTrace, cause, localizedMessage,
suppressed, exception, trace, path, timestamp
```

- [ ] **Step 2: Annotation 설명 검증이 실패하는지 확인한다**

`ModelConverters` 또는 생성된 OpenAPI JSON에서 `success`, `code`, `message`, `data`의 description 존재를 검증한다.

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.config.SwaggerEndpointTest*schema*"
```

Expected: 기존 클래스에 `@Schema` 설명이 없어 실패한다.

- [ ] **Step 3: JSON 계약을 바꾸지 않는 최소 Annotation을 추가한다**

클래스와 기존 accessor 또는 record component에 다음 의미의 Annotation을 추가한다.

```java
@Schema(description = "공통 성공 응답")
@Schema(description = "요청 성공 여부", example = "true")
@Schema(description = "애플리케이션 성공 코드", example = "COMMON_200")
@Schema(description = "성공 메시지", example = "요청이 성공했습니다.")
@Schema(description = "응답 데이터")
```

오류 응답은 실제 `COMMON_400_001`과 메시지를 사용하며 Validation 예시에는 `rejectedValue`나 개인정보를 포함하지 않는다. `data`의 구체 타입을 고정하지 않는다.

- [ ] **Step 4: Schema와 기존 JSON 회귀 테스트를 함께 통과시킨다**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.config.SwaggerEndpointTest*schema*" --tests "com.ssafy.b209.global.response.*"
```

Expected: 새 Schema 테스트와 기존 성공·오류 JSON 테스트가 모두 PASS.

---

### Task 5: Swagger UI와 OpenAPI Endpoint 통합 검증

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/global/config/SwaggerEndpointTest.java`

**Interfaces:**
- Consumes: Springdoc Auto Configuration, `OpenApiConfig`, 테스트 전용 Controller
- Produces: Swagger UI와 OpenAPI JSON Endpoint 회귀 보장

- [ ] **Step 1: Endpoint 실패 테스트를 작성한다**

```java
mockMvc.perform(get("/swagger-ui.html"))
    .andExpect(status().is3xxRedirection())
    .andExpect(redirectedUrl("/swagger-ui/index.html"));

mockMvc.perform(get("/swagger-ui/index.html"))
    .andExpect(status().isOk())
    .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML));

mockMvc.perform(get("/v3/api-docs"))
    .andExpect(status().isOk())
    .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
    .andExpect(jsonPath("$.openapi").isNotEmpty())
    .andExpect(jsonPath("$.info.title").value("아동 그림·대화 기반 정서 지원 서비스 API"))
    .andExpect(jsonPath("$.paths").exists());

mockMvc.perform(get("/v3/api-docs/api-v1"))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.paths['/api/v1/test/success']").exists())
    .andExpect(jsonPath("$.paths['/outside/test']").doesNotExist())
    .andExpect(jsonPath("$.paths['/swagger-ui.html']").doesNotExist());
```

- [ ] **Step 2: Springdoc 설정 누락 시 실패하는지 확인한다**

Task 1 구현 전이라면 Endpoint 또는 Group assertion 실패를 확인한다. Task 1 이후라면 이 단계는 새 assertion을 하나씩 추가하면서 실패 원인이 아직 구현되지 않은 테스트 Controller 또는 Schema metadata임을 확인한다.

- [ ] **Step 3: 테스트 Context를 최소 범위로 완성한다**

`@SpringBootTest`, `@AutoConfigureMockMvc`, `@ActiveProfiles("test")`와 `@Import`를 사용해 Production Sample Endpoint 없이 Springdoc Auto Configuration과 테스트 Controller만 포함한다. DB 접근은 수행하지 않는다.

- [ ] **Step 4: Swagger 통합 테스트를 통과시킨다**

Run:

```powershell
gradlew.bat test --tests "com.ssafy.b209.global.config.SwaggerEndpointTest"
```

Expected: PASS.

---

### Task 6: README와 전체 검증

**Files:**
- Modify: `README.md`

**Interfaces:**
- Documents: Swagger Endpoint, 사용 순서, 공통 Schema, `/api/v1/**` CORS 정책과 운영 규칙

- [ ] **Step 1: README에 Swagger 접속법을 추가한다**

다음 기본 URL과 Backend Port가 설정으로 변경될 수 있음을 기록한다.

```text
http://localhost:8080/swagger-ui.html
http://localhost:8080/swagger-ui/index.html
http://localhost:8080/v3/api-docs
http://localhost:8080/v3/api-docs/api-v1
```

Backend 실행, Swagger UI 접속, API/Schema 확인, Try it out, Execute, HTTP Status와 Body 확인 순서를 설명한다. 현재 Production Controller가 없어 API 목록이 비어 있을 수 있음을 명시한다.

- [ ] **Step 2: README에 CORS 정책과 운영 규칙을 추가한다**

```text
적용 범위: /api/v1/**
local Origin: http://localhost:3000, http://127.0.0.1:3000
Method: GET, POST, PUT, PATCH, DELETE, OPTIONS
Header: Content-Type, Accept, Authorization
Credentials: false
Max Age: 3600초
```

Origin의 Scheme·Host·Port 정확한 일치, wildcard 금지, 운영 Profile 분리, Cookie 인증과 Spring Security 도입 시 재검토, CORS가 인증·인가나 CSRF 방어가 아니라는 점을 기록한다.

- [ ] **Step 3: 포맷을 적용하고 전체 테스트를 실행한다**

```powershell
gradlew.bat spotlessApply
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
gradlew.bat dependencyInsight --dependency springdoc-openapi --configuration runtimeClasspath
```

Expected: 모든 명령 성공, Springdoc 2.8.17 해석, Springfox 없음, Javadoc 오류와 경고 없음.

- [ ] **Step 4: Javadoc과 테스트 결과를 확인한다**

```powershell
Test-Path build/docs/javadoc/index.html
```

JUnit XML을 합산해 tests, failures, errors, skipped를 보고한다. 기존 45개 테스트와 새 Swagger/CORS 테스트를 구분해 기록한다.

- [ ] **Step 5: 가능하면 실제 애플리케이션 Endpoint를 확인한다**

`local` Profile의 MySQL 의존성을 피할 수 있는 검증 환경에서 애플리케이션을 실행하고 다음을 HTTP로 확인한다.

```text
GET /swagger-ui.html
GET /swagger-ui/index.html
GET /v3/api-docs
GET /v3/api-docs/api-v1
```

실행하지 못하면 MockMvc 성공과 실제 Browser/HTTP 미검증을 구분해 최종 보고한다.

- [ ] **Step 6: 변경 범위와 보안을 감사한다**

```powershell
git diff --check
git status --short --branch
git diff --name-only
```

다음을 검색해 없음을 확인한다.

```text
Spring Security, JWT, Security Scheme, @CrossOrigin, CorsFilter,
allowedOriginPatterns("*"), allowedOrigins("*"), 실제 Token·비밀번호·개인정보,
Production Controller, DB/Flyway 변경, package-info.java, TODO
```

- [ ] **Step 7: Git 후속 작업은 사용자 선택을 기다린다**

권장 단일 Commit Message:

```text
feat(config): S15P11B209-135 Swagger UI 및 CORS 설정
```

Commit, Push와 Merge Request는 사용자가 명시적으로 요청한 경우에만 수행하며 Source branch 삭제 옵션은 사용하지 않는다.
