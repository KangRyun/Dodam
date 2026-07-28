package com.ssafy.b209.auth.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@ActiveProfiles("test")
class UserRepositoryTest {

  @Autowired private UserRepository userRepository;

  @Test
  void allowsDifferentOAuthUsersToShareAContactEmail() {
    LocalDateTime now = LocalDateTime.of(2026, 7, 28, 9, 0);
    User first = User.pending(now);
    first.completeOnboarding(UserRole.GUARDIAN, "first-user", "shared@example.com", now);
    User second = User.pending(now);
    second.completeOnboarding(UserRole.EXPERT, "second-user", "shared@example.com", now);

    userRepository.saveAndFlush(first);
    userRepository.saveAndFlush(second);

    assertThat(userRepository.findAll())
        .extracting(User::getEmail)
        .containsExactlyInAnyOrder("shared@example.com", "shared@example.com");
  }
}
