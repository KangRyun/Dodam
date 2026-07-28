# Onboarding Email Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OAuth 온보딩 연락 이메일을 일관되게 정규화해 저장하고, 동일 연락 이메일을 가진 별도 OAuth 사용자를 허용한다.

**Architecture:** API 요청 DTO의 compact constructor에서 이메일을 정규화하여 Bean Validation과 Service가 동일한 값을 사용한다. 사용자 식별은 기존 `(provider, provider_subject)` 계약을 유지하고 `users.email`에는 고유 제약이나 중복 조회를 추가하지 않는다.

**Tech Stack:** Java 21, Spring Boot, Jakarta Bean Validation, Spring Data JPA, JUnit 5, AssertJ

## Global Constraints

- 브랜치·커밋·MR에 `S15P11B209-531`을 포함한다.
- 자체 로그인 또는 이메일 기반 계정 병합을 추가하지 않는다.
- `users.email`은 연락 이메일이며 중복을 허용한다.
- Java 공개 타입의 Javadoc은 실제 동작과 일치하는 한국어로 유지한다.

---

### Task 1: 온보딩 이메일 정규화

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/user/dto/request/OnboardingRequest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/user/service/UserOnboardingServiceTest.java`

**Interfaces:**
- Consumes: `OnboardingRequest(String email)`
- Produces: 앞뒤 공백을 제거하고 소문자로 변환된 `OnboardingRequest.email()`

- [ ] **Step 1: 정규화된 이메일 저장을 기대하는 실패 테스트 작성**

```java
OnboardingRequest request =
    new OnboardingRequest(
        UserRole.GUARDIAN,
        "보호자",
        "  Guardian@Example.COM  ",
        null,
        consents);

UserResponse response =
    service.completeOnboarding(USER_ID, request, null, null);

assertThat(response.email()).isEqualTo("guardian@example.com");
```

- [ ] **Step 2: 실패 확인**

Run: `gradlew.bat test --tests "com.ssafy.b209.user.service.UserOnboardingServiceTest"`

Expected: 입력 이메일이 공백과 대문자를 유지해 assertion 실패

- [ ] **Step 3: 최소 구현**

```java
public OnboardingRequest {
  if (email != null) {
    email = email.trim().toLowerCase(Locale.ROOT);
  }
  if (consents != null) {
    consents = List.copyOf(consents);
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `gradlew.bat test --tests "com.ssafy.b209.user.service.UserOnboardingServiceTest"`

Expected: PASS

### Task 2: 연락 이메일 중복 허용 계약 고정

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/auth/repository/UserRepositoryTest.java`

**Interfaces:**
- Consumes: `UserRepository.saveAndFlush(User)`
- Produces: 동일한 `users.email`을 가진 서로 다른 사용자 행

- [ ] **Step 1: 동일 이메일 사용자 2명 저장 테스트 작성**

```java
User first = User.pending(now);
first.completeOnboarding(UserRole.GUARDIAN, "첫 번째", "shared@example.com", now);
User second = User.pending(now);
second.completeOnboarding(UserRole.EXPERT, "두 번째", "shared@example.com", now);

userRepository.saveAndFlush(first);
userRepository.saveAndFlush(second);

assertThat(userRepository.findAll()).hasSize(2);
```

- [ ] **Step 2: 현재 Schema에서 테스트 통과 확인**

Run: `gradlew.bat test --tests "com.ssafy.b209.auth.repository.UserRepositoryTest"`

Expected: PASS. 이 테스트는 `users.email`에 고유 제약을 추가하는 회귀를 방지한다.

### Task 3: API 계약 문서와 전체 검증

**Files:**
- Modify: `docs/api/API_명세서_최종.md`

**Interfaces:**
- Produces: USER-02의 필수 이메일, 정규화, 중복 허용 계약

- [ ] **Step 1: USER-02 요청 필드에 이메일 추가**

```text
email:string(이메일 형식, 최대 255자, 앞뒤 공백 제거·소문자 정규화)
```

- [ ] **Step 2: 온보딩 규칙에 연락 이메일 중복 허용 명시**

```text
users.email은 연락 이메일이며 계정 식별에 사용하지 않으므로 중복을 허용한다.
```

- [ ] **Step 3: 전체 검증**

Run:

```text
gradlew.bat spotlessCheck
gradlew.bat test
gradlew.bat javadoc
```

Expected: 모든 명령 exit code 0, `build/docs/javadoc/index.html` 생성

- [ ] **Step 4: 커밋**

```text
git commit -m "feat(user): [S15P11B209-531] 온보딩 이메일 정규화"
```

