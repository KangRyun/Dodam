# S15P11B209-304 OAuth Account Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 검증된 Kakao·Google·Naver 신원을 최초 서비스 사용자 계정으로 멱등 등록한다.

**Architecture:** Provider Adapter와 DB Provisioning을 분리한다. 304번은 Provider HTTP 통신을 하지 않고 검증 완료 신원 값만 받아 `users`와 `auth_accounts`를 하나의 트랜잭션으로 관리한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, MySQL 8.4.10, JUnit 5, Mockito

## Global Constraints

- V6 소셜 전용 스키마를 기준으로 하며 Flyway migration을 추가하지 않는다.
- 공개 HTTP endpoint, OAuth Client, JWT, Refresh Token을 구현하지 않는다.
- 이메일과 Subject를 로그로 남기지 않는다.
- Entity를 API로 노출하거나 public setter와 Lombok `@Data`를 사용하지 않는다.
- 구현과 테스트 후에도 사용자 요청 전에는 다음 이슈 커밋을 수행하지 않는다.

---

### Task 1: OAuth 사용자 Domain과 Repository

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/auth/domain/AuthProvider.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/domain/AccountStatus.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/domain/User.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/domain/AuthAccount.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/repository/UserRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/repository/AuthAccountRepository.java`
- Test: `backend/src/test/java/com/ssafy/b209/auth/repository/AuthAccountRepositoryTest.java`

**Interfaces:**
- Produces: `User.pending(LocalDateTime)`, `AuthAccount.social(User, AuthProvider, String, String, LocalDateTime)`, `findByProviderAndProviderSubject`

- [ ] Write Repository tests proving composite Subject uniqueness and cross-Provider reuse.
- [ ] Run focused tests and confirm missing auth types cause RED.
- [ ] Implement JPA mappings matching V6, including nullable `users.role` and `provider_email`.
- [ ] Run focused tests and confirm GREEN.

### Task 2: 검증된 신원 계약과 Provisioning Service

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/VerifiedOAuthIdentity.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/ProvisionedOAuthAccount.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/service/OAuthAccountProvisioningService.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/exception/AuthErrorCode.java`
- Test: `backend/src/test/java/com/ssafy/b209/auth/service/OAuthAccountProvisioningServiceTest.java`

**Interfaces:**
- Consumes: Task 1의 Domain과 Repository
- Produces: `provision(VerifiedOAuthIdentity)`

- [ ] Write tests for all three Providers, missing email, existing identity, and UNIQUE race.
- [ ] Run focused tests and confirm missing Service types cause RED.
- [ ] Implement transactional find-or-create and safe conflict mapping.
- [ ] Run focused tests and confirm GREEN.

### Task 3: 전체 검증

**Files:**
- Modify only if implementation differs: `docs/superpowers/specs/2026-07-22-oauth-account-provisioning-design.md`

**Interfaces:**
- Produces: S15P11B209-306 Provider Adapter가 사용할 검증된 Provisioning 경계

- [ ] Run `gradlew.bat clean test` and confirm no failures.
- [ ] Run `gradlew.bat spotlessCheck`.
- [ ] Run `gradlew.bat javadoc` and confirm `build/docs/javadoc/index.html` exists.
- [ ] Inspect `git diff --check`, scope, and sensitive Logging before handoff.
