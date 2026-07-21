# Spring Boot Backend Initial Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `backend/`에 Java 21, Spring Boot 3.5.16, Gradle 8.14.x 기반의 최소 실행 가능 백엔드 프로젝트와 Javadoc·Spotless·Profile·개발 문서를 구성한다.

**Architecture:** 기존 모노레포 구조를 유지하고 백엔드는 독립 Gradle 프로젝트로 둔다. 이번 단계의 Java 코드는 Spring Boot 진입점과 Context 테스트만 만들며, 도메인과 외부 시스템 경계는 README에 예정 구조로만 기록한다.

**Tech Stack:** Java 21 LTS, Spring Boot 3.5.16, Gradle 8.14.3 Wrapper, Spring Web MVC, Jakarta Bean Validation, Lombok, JUnit 5, Mockito, Spotless 8.8.0, Google Java Format

## Global Constraints

- 작업 브랜치는 로컬 `develop`에서 분기한 `chore/S15P11B209-131-backend-initial-setup`이다.
- 사용자 요청 없이 Commit, Push, Merge Request 생성, Merge를 수행하지 않는다.
- API 명세의 서비스명과 도메인 용어를 사용하고 `/api/v1`은 Context Path로 설정하지 않는다.
- MySQL, JPA, Flyway, Security, Swagger, CORS, Redis, AWS SDK, Firebase, FastAPI Client와 실제 API를 추가하지 않는다.
- 의미 없는 빈 클래스·인터페이스·`package-info.java`·Java 디렉터리의 `.gitkeep`을 만들지 않는다.
- 공개 Java 클래스와 필요한 공개 메서드에는 실제 역할에 맞는 한국어 Javadoc만 작성한다.
- Javadoc은 UTF-8과 `failOnError = true`를 적용하고 DocLint 전체 비활성화나 `withJavadocJar()`를 사용하지 않는다.
- 로컬 PATH에는 Java와 Gradle이 없으므로 검증용 Java 21과 Gradle 8.14.3은 저장소 밖 임시 디렉터리에서 사용한다.

---

### Task 1: Gradle 빌드 골격과 Wrapper 구성

**Files:**
- Create: `backend/settings.gradle`
- Create: `backend/build.gradle`
- Create: `backend/gradlew`
- Create: `backend/gradlew.bat`
- Create: `backend/gradle/wrapper/gradle-wrapper.jar`
- Create: `backend/gradle/wrapper/gradle-wrapper.properties`

**Interfaces:**
- Consumes: 저장소 밖 임시 Java 21 Runtime과 Gradle 8.14.3 배포본
- Produces: `backend/gradlew.bat`와 `backend/gradlew`로 실행 가능한 Java 21 Gradle 프로젝트

- [ ] **Step 1: Java 21과 Gradle 8.14.3 검증 도구 준비**

Eclipse Temurin JDK 21 Windows x64 ZIP과 Gradle 8.14.3 binary ZIP을 임시 디렉터리에 내려받아 압축을 푼다. 저장소에는 이 도구를 복사하지 않는다.

- [ ] **Step 2: 프로젝트 이름 정의**

`backend/settings.gradle`:

```groovy
rootProject.name = 'b209'
```

- [ ] **Step 3: 빌드 설정 작성**

`backend/build.gradle`:

```groovy
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.5.16'
    id 'io.spring.dependency-management' version '1.1.7'
    id 'com.diffplug.spotless' version '8.8.0'
}

group = 'com.ssafy'
version = '0.0.1-SNAPSHOT'

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-validation'

    compileOnly 'org.projectlombok:lombok'
    annotationProcessor 'org.projectlombok:lombok'

    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testRuntimeOnly 'org.junit.platform:junit-platform-launcher'
}

tasks.named('test') {
    useJUnitPlatform()
}

tasks.withType(Javadoc).configureEach {
    options.encoding = 'UTF-8'
    options.charSet = 'UTF-8'
    options.docEncoding = 'UTF-8'
    failOnError = true
}

spotless {
    java {
        target 'src/**/*.java'
        googleJavaFormat()
        removeUnusedImports()
        trimTrailingWhitespace()
        endWithNewline()
    }

    format 'misc', {
        target '*.gradle', '*.md', '.gitignore', 'src/**/*.yml', 'src/**/*.yaml'
        trimTrailingWhitespace()
        endWithNewline()
    }
}
```

- [ ] **Step 4: Wrapper 생성**

임시 Gradle 8.14.3의 `gradle.bat`을 Java 21로 실행한다.

```powershell
gradle.bat wrapper --gradle-version 8.14.3 --distribution-type bin
```

Expected: `backend/gradlew`, `backend/gradlew.bat`, `backend/gradle/wrapper/gradle-wrapper.jar`, `backend/gradle/wrapper/gradle-wrapper.properties` 생성.

- [ ] **Step 5: Wrapper 버전 확인**

```powershell
backend\gradlew.bat --version
```

Expected: `Gradle 8.14.3`, JVM 21 표시.

### Task 2: Spring Boot 진입점과 Profile Context 테스트

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/B209ApplicationTests.java`
- Create: `backend/src/main/java/com/ssafy/b209/B209Application.java`
- Create: `backend/src/main/resources/application.yml`
- Create: `backend/src/main/resources/application-local.yml`
- Create: `backend/src/main/resources/application-test.yml`

**Interfaces:**
- Consumes: Spring Boot Test와 `B209Application`
- Produces: `com.ssafy.b209.B209Application.main(String[])`과 `test` Profile Context 검증

- [ ] **Step 1: 실패하는 Context 테스트 작성**

`backend/src/test/java/com/ssafy/b209/B209ApplicationTests.java`:

```java
package com.ssafy.b209;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class B209ApplicationTests {

    @Test
    void contextLoads() {}
}
```

- [ ] **Step 2: 테스트가 Application 부재로 실패하는지 확인**

```powershell
backend\gradlew.bat clean test
```

Expected: Spring Boot Configuration을 찾지 못해 FAIL.

- [ ] **Step 3: 최소 Application 구현**

`backend/src/main/java/com/ssafy/b209/B209Application.java`:

```java
package com.ssafy.b209;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 아동 그림·대화 기반 정서 표현 서비스의 Spring Boot 진입점이다.
 *
 * <p>Application Context를 초기화하고 내장 웹 서버를 실행한다. 도메인 기능과 외부 시스템 연동은 각 기능의 후속
 * 구현에서 구성한다.
 */
@SpringBootApplication
public class B209Application {

    /**
     * Spring Boot 애플리케이션을 실행한다.
     *
     * @param args 애플리케이션 실행 시 전달되는 명령행 인자
     */
    public static void main(String[] args) {
        SpringApplication.run(B209Application.class, args);
    }
}
```

- [ ] **Step 4: 최소 Profile YAML 작성**

`backend/src/main/resources/application.yml`:

```yaml
spring:
  application:
    name: b209
  profiles:
    default: local

server:
  port: 8080
```

`backend/src/main/resources/application-local.yml`:

```yaml
spring:
  config:
    activate:
      on-profile: local
```

`backend/src/main/resources/application-test.yml`:

```yaml
spring:
  config:
    activate:
      on-profile: test
```

- [ ] **Step 5: Context 테스트 통과 확인**

```powershell
backend\gradlew.bat clean test
```

Expected: 1 test, 0 failures, BUILD SUCCESSFUL.

### Task 3: Git 제외 규칙과 개발 문서 갱신

**Files:**
- Modify: `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Consumes: 실제 `backend/` 프로젝트 구조와 Gradle Task
- Produces: 팀원이 복제 후 실행·검증·Javadoc 확인에 사용할 명령과 향후 아키텍처 경계

- [ ] **Step 1: `.gitignore` 보완**

기존 모노레포 규칙을 유지하면서 다음 항목을 추가한다.

```gitignore
backend/.gradle/
backend/build/
backend/out/
backend/bin/
application-secret.yml
application-*-secret.yml
```

Wrapper JAR 예외 규칙 `!backend/gradle/wrapper/gradle-wrapper.jar`와 공유 YAML 파일은 유지한다.

- [ ] **Step 2: README를 실제 프로젝트 상태로 갱신**

다음 내용을 명시적으로 작성한다.

- 서비스 소개와 사용자 유형
- 현재 모노레포 및 `backend/` 실제 구조
- 향후 `global`, API 명세 기반 `domain`, `infrastructure` 예정 구조
- Java 21, Spring Boot 3.5.16, Gradle 8.14.3, Spotless 8.8.0 기술 스택
- 실행, Profile, 테스트, Spotless 검사·적용 명령
- Javadoc 생성 명령과 `backend/build/docs/javadoc/index.html` 확인 경로
- `/api/v1` Controller Mapping 원칙
- FastAPI `/internal/v1/**`, S3, Firebase의 외부 시스템 경계
- 환경 변수, Secret, 개인정보·아동 데이터 로그 금지 원칙
- MySQL/JPA부터 시작하는 후속 작업 순서와 Actuator 제외 사실

- [ ] **Step 3: 포맷 적용 후 검사**

```powershell
backend\gradlew.bat spotlessApply
backend\gradlew.bat spotlessCheck
```

Expected: 두 Task 모두 BUILD SUCCESSFUL, README 코드 블록과 YAML 문법 유지.

### Task 4: Javadoc·실행·Git 범위 최종 검증

**Files:**
- Verify: `backend/build/docs/javadoc/index.html`
- Verify: 전체 작업 트리

**Interfaces:**
- Consumes: Tasks 1~3의 전체 결과
- Produces: Commit 가능한 검증 완료 상태와 최종 결과 보고 근거

- [ ] **Step 1: 전체 테스트 재실행**

```powershell
backend\gradlew.bat clean test
```

Expected: BUILD SUCCESSFUL, 1 test, 0 failures.

- [ ] **Step 2: Spotless 재검사**

```powershell
backend\gradlew.bat spotlessCheck
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Javadoc 생성 및 산출물 검사**

```powershell
backend\gradlew.bat javadoc
Test-Path backend\build\docs\javadoc\index.html
```

Expected: 경고 없이 BUILD SUCCESSFUL, `True`. 생성된 HTML에서 `B209Application`의 한국어 설명이 UTF-8로 보이는지 확인한다.

- [ ] **Step 4: 애플리케이션 시작 확인 후 종료**

```powershell
backend\gradlew.bat bootRun
```

Expected: Java 21과 Spring Boot 3.5.16으로 `local` Profile이 활성화되고 Tomcat이 8080에서 시작한다. 시작 로그 확인 후 프로세스를 정상 종료한다.

- [ ] **Step 5: 범위와 비밀정보 검사**

```powershell
git status --short
git diff --check
git diff -- . ':!docs/superpowers/**'
git ls-files --others --exclude-standard
```

Expected: 이번 작업 파일만 표시되고 `.env`, Secret, IDE 설정, `backend/build/`, 빈 패키지, 금지 의존성이 포함되지 않는다.

- [ ] **Step 6: Commit 없이 결과 정리**

현재 브랜치, 기준 브랜치, 변경 파일, 검증 결과, Javadoc 작성 대상과 생성 경로, 권장 Commit Message `chore(backend): S15P11B209-131 Spring Boot 프로젝트 초기 환경 구성`, 권장 Push 명령, Merge Request 초안을 보고한다. 사용자 요청이 없으므로 Stage, Commit, Push, Merge Request 생성은 수행하지 않는다.
