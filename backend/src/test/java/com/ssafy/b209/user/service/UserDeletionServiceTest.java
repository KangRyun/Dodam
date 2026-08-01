package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.AuthAccountRepository;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.RefreshTokenSessionStore;
import com.ssafy.b209.child.repository.ChildDeletionRepository;
import com.ssafy.b209.child.service.ChildDeletionService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.DeleteUserRequest;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserDeletionServiceTest {

  private static final Instant NOW = Instant.parse("2026-07-31T01:02:03Z");

  @Mock private UserRepository userRepository;
  @Mock private AuthAccountRepository authAccountRepository;
  @Mock private ChildDeletionService childDeletionService;
  @Mock private ChildDeletionRepository childDeletionRepository;
  @Mock private RefreshTokenSessionStore refreshTokenSessionStore;

  private UserDeletionService service;

  @BeforeEach
  void setUp() {
    service =
        new UserDeletionService(
            userRepository,
            authAccountRepository,
            childDeletionService,
            childDeletionRepository,
            refreshTokenSessionStore,
            Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void deletesAuthAccountsSoTheSameSocialAccountCanRejoin() {
    // 인증 계정을 지우지 않으면 재로그인 provisioning 이 남은 행으로 DELETED 사용자를
    // 물어와 같은 소셜 계정의 재가입이 영영 막힌다(768 — 529 재로그인 계약 회귀).
    User user = activeUser();
    when(userRepository.findById(51L)).thenReturn(Optional.of(user));

    service.delete(51L, new DeleteUserRequest("DELETE"));

    verify(authAccountRepository).deleteAllByUserId(51L);
  }

  @Test
  void marksExistingUserDeletedWithoutHardDeletingTheRow() {
    User user = activeUser();
    when(userRepository.findById(51L)).thenReturn(Optional.of(user));

    service.delete(51L, new DeleteUserRequest("DELETE"));

    assertThat(user.getAccountStatus()).isEqualTo(AccountStatus.DELETED);
    verify(userRepository, never()).deleteById(51L);
  }

  @Test
  void deletesSolelyOwnedChildrenBeforeReleasingGuardianRelations() {
    when(userRepository.findById(51L)).thenReturn(Optional.of(activeUser()));

    service.delete(51L, new DeleteUserRequest("DELETE"));

    InOrder order = inOrder(childDeletionService, childDeletionRepository);
    order.verify(childDeletionService).deleteAllSolelyOwnedBy(51L);
    order.verify(childDeletionRepository).deleteGuardianRelations(51L);
  }

  @Test
  void revokesAllRefreshSessionsAfterTheAccountIsMarkedDeleted() {
    User user = activeUser();
    when(userRepository.findById(51L)).thenReturn(Optional.of(user));

    service.delete(51L, new DeleteUserRequest("DELETE"));

    assertThat(user.getAccountStatus()).isEqualTo(AccountStatus.DELETED);
    verify(refreshTokenSessionStore).revokeAll(51L);
  }

  @Test
  void rejectsMismatchedConfirmationWithoutLookingUpUser() {
    assertThatThrownBy(() -> service.delete(51L, new DeleteUserRequest("delete")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(UserErrorCode.WITHDRAWAL_CONFIRMATION_MISMATCH));

    verify(userRepository, never()).findById(51L);
    verify(childDeletionService, never()).deleteAllSolelyOwnedBy(51L);
    verify(refreshTokenSessionStore, never()).revokeAll(51L);
  }

  @Test
  void reportsMissingUserWithoutChangingChildrenOrSessions() {
    when(userRepository.findById(51L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.delete(51L, new DeleteUserRequest("DELETE")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(UserErrorCode.USER_NOT_FOUND));

    verify(childDeletionService, never()).deleteAllSolelyOwnedBy(51L);
    verify(childDeletionRepository, never()).deleteGuardianRelations(51L);
    verify(refreshTokenSessionStore, never()).revokeAll(51L);
    verify(userRepository, never()).deleteById(51L);
  }

  @Test
  void hidesAlreadyDeletedUserWithoutRepeatingCleanup() {
    User deletedUser = activeUser();
    deletedUser.markDeleted(NOW.atOffset(ZoneOffset.UTC).toLocalDateTime());
    when(userRepository.findById(51L)).thenReturn(Optional.of(deletedUser));

    assertThatThrownBy(() -> service.delete(51L, new DeleteUserRequest("DELETE")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(UserErrorCode.USER_NOT_FOUND));

    verify(childDeletionService, never()).deleteAllSolelyOwnedBy(51L);
    verify(refreshTokenSessionStore, never()).revokeAll(51L);
  }

  private static User activeUser() {
    User user = User.pending(NOW.atOffset(ZoneOffset.UTC).toLocalDateTime());
    user.completeOnboarding(
        UserRole.GUARDIAN,
        "별이맘",
        "guardian@example.com",
        NOW.atOffset(ZoneOffset.UTC).toLocalDateTime());
    return user;
  }
}
