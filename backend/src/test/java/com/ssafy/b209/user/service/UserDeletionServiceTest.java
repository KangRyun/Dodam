package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.DeleteUserRequest;
import com.ssafy.b209.user.exception.UserErrorCode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserDeletionServiceTest {

  @Mock private UserRepository userRepository;

  private UserDeletionService service;

  @BeforeEach
  void setUp() {
    service = new UserDeletionService(userRepository);
  }

  @Test
  void immediatelyDeletesExistingUserAfterExplicitConfirmation() {
    when(userRepository.existsById(51L)).thenReturn(true);

    service.delete(51L, new DeleteUserRequest("DELETE"));

    verify(userRepository).deleteById(51L);
  }

  @Test
  void rejectsMismatchedConfirmationWithoutLookingUpUser() {
    assertThatThrownBy(() -> service.delete(51L, new DeleteUserRequest("delete")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(UserErrorCode.WITHDRAWAL_CONFIRMATION_MISMATCH));

    verify(userRepository, never()).existsById(51L);
    verify(userRepository, never()).deleteById(51L);
  }

  @Test
  void reportsMissingUserWithoutDeleting() {
    when(userRepository.existsById(51L)).thenReturn(false);

    assertThatThrownBy(() -> service.delete(51L, new DeleteUserRequest("DELETE")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(UserErrorCode.USER_NOT_FOUND));

    verify(userRepository, never()).deleteById(51L);
  }
}
