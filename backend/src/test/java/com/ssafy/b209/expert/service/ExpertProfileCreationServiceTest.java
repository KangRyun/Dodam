package com.ssafy.b209.expert.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.dto.request.CreateExpertProfileRequest;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

class ExpertProfileCreationServiceTest {

  @Test
  void mapsConcurrentUserProfileUniqueViolationWithoutQueryingFailedTransactionAgain() {
    CurrentAuthenticatedUserResolver currentUserResolver =
        mock(CurrentAuthenticatedUserResolver.class);
    UserRepository userRepository = mock(UserRepository.class);
    ExpertProfileRepository expertProfileRepository = mock(ExpertProfileRepository.class);
    User user = mock(User.class);
    given(currentUserResolver.requireUserId()).willReturn(574L);
    given(userRepository.findById(574L)).willReturn(Optional.of(user));
    given(user.getRole()).willReturn(UserRole.EXPERT);
    given(user.getAccountStatus()).willReturn(AccountStatus.ACTIVE);
    given(user.isOnboardingCompleted()).willReturn(true);
    given(expertProfileRepository.existsByUserId(574L)).willReturn(false);
    given(expertProfileRepository.saveAndFlush(org.mockito.ArgumentMatchers.any()))
        .willThrow(
            new DataIntegrityViolationException(
                "Duplicate entry '574' for key 'uk_expert_profiles_user_id'"));
    ExpertProfileCreationService service =
        new ExpertProfileCreationService(
            currentUserResolver,
            userRepository,
            expertProfileRepository,
            Clock.fixed(Instant.parse("2026-07-30T00:00:00Z"), ZoneOffset.UTC));

    assertThatThrownBy(() -> service.create(validRequest()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getErrorCode())
                    .isEqualTo(ExpertErrorCode.EXPERT_PROFILE_ALREADY_EXISTS));
    verify(expertProfileRepository, times(1)).existsByUserId(574L);
  }

  private CreateExpertProfileRequest validRequest() {
    return new CreateExpertProfileRequest(
        "마음숲 상담사",
        "마음숲 아동상담센터",
        "상담사",
        6,
        List.of("CHILD_ART"),
        4,
        12,
        "아동의 표현을 존중하며 상담합니다.",
        true,
        "대전광역시");
  }
}
