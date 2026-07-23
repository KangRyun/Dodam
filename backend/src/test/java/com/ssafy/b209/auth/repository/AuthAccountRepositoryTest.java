package com.ssafy.b209.auth.repository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.auth.domain.AuthAccount;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.domain.User;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@ActiveProfiles("test")
class AuthAccountRepositoryTest {

  @Autowired private UserRepository userRepository;
  @Autowired private AuthAccountRepository authAccountRepository;

  @Test
  void allowsTheSameSubjectForDifferentProviders() {
    LocalDateTime now = LocalDateTime.of(2026, 7, 22, 12, 0);
    User kakaoUser = userRepository.save(User.pending(now));
    User googleUser = userRepository.save(User.pending(now));

    authAccountRepository.saveAndFlush(
        AuthAccount.social(kakaoUser, AuthProvider.KAKAO, "same-subject", null, null, now));
    authAccountRepository.saveAndFlush(
        AuthAccount.social(googleUser, AuthProvider.GOOGLE, "same-subject", null, null, now));

    assertThat(
            authAccountRepository.findByProviderAndProviderSubject(
                AuthProvider.KAKAO, "same-subject"))
        .isPresent();
    assertThat(
            authAccountRepository.findByProviderAndProviderSubject(
                AuthProvider.GOOGLE, "same-subject"))
        .isPresent();
  }

  @Test
  void rejectsDuplicateProviderAndSubject() {
    LocalDateTime now = LocalDateTime.of(2026, 7, 22, 12, 0);
    User firstUser = userRepository.save(User.pending(now));
    User secondUser = userRepository.save(User.pending(now));
    authAccountRepository.saveAndFlush(
        AuthAccount.social(firstUser, AuthProvider.NAVER, "naver-user", null, null, now));

    assertThatThrownBy(
            () ->
                authAccountRepository.saveAndFlush(
                    AuthAccount.social(
                        secondUser, AuthProvider.NAVER, "naver-user", null, null, now)))
        .isInstanceOf(DataIntegrityViolationException.class);
  }
}
