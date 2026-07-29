package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.child.repository.ChildDeletionRepository;
import com.ssafy.b209.child.service.ChildDeletionService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.DeleteUserRequest;
import com.ssafy.b209.user.exception.UserErrorCode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserDeletionServiceTest {

  @Mock private UserRepository userRepository;
  @Mock private ChildDeletionService childDeletionService;
  @Mock private ChildDeletionRepository childDeletionRepository;

  private UserDeletionService service;

  @BeforeEach
  void setUp() {
    service = new UserDeletionService(userRepository, childDeletionService, childDeletionRepository);
  }

  @Test
  void immediatelyDeletesExistingUserAfterExplicitConfirmation() {
    when(userRepository.existsById(51L)).thenReturn(true);

    service.delete(51L, new DeleteUserRequest("DELETE"));

    verify(userRepository).deleteById(51L);
  }

  /**
   * S15P11B209-728 — 탈퇴가 아동 데이터를 함께 지우는지.
   *
   * <p>이 검증이 없던 동안 탈퇴는 {@code users} 행만 지웠고, 아동 프로필·그림·음성이 소유자 없이 남았다.
   */
  @Test
  void deletesChildrenOwnedSolelyByWithdrawingGuardian() {
    when(userRepository.existsById(51L)).thenReturn(true);

    service.delete(51L, new DeleteUserRequest("DELETE"));

    verify(childDeletionService).deleteAllSolelyOwnedBy(51L);
  }

  /**
   * ★ 순서가 이 기능의 핵심이다.
   *
   * <p>사용자를 먼저 지우면 {@code guardian_child_relations}가 CASCADE로 사라져 "이 보호자의 아동"을 더는 찾을 수 없다.
   * 그러면 오류 없이 <b>조용히 아무것도 지우지 못한다.</b> 순서를 뒤집는 리팩터링을 이 테스트가 막는다.
   */
  @Test
  void deletesChildDataBeforeRemovingUser() {
    when(userRepository.existsById(51L)).thenReturn(true);

    service.delete(51L, new DeleteUserRequest("DELETE"));

    InOrder order = inOrder(childDeletionService, userRepository);
    order.verify(childDeletionService).deleteAllSolelyOwnedBy(51L);
    order.verify(userRepository).deleteById(51L);
  }

  /**
   * {@code expert_profiles.users_id}가 {@code ON DELETE RESTRICT}라, 확인하지 않고 지우면 DB 제약 위반이 500으로
   * 새어 나간다. 원인을 알 수 있는 4xx로 바꾼다.
   */
  @Test
  void blocksWithdrawalWhenExpertProfileExists() {
    when(userRepository.existsById(51L)).thenReturn(true);
    when(childDeletionRepository.hasExpertProfile(51L)).thenReturn(true);

    assertThatThrownBy(() -> service.delete(51L, new DeleteUserRequest("DELETE")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(UserErrorCode.WITHDRAWAL_BLOCKED_BY_EXPERT_PROFILE));

    // 막혔으면 아무것도 지우지 않아야 한다 — 아동만 지워지고 계정이 남는 최악을 방지한다.
    verify(childDeletionService, never()).deleteAllSolelyOwnedBy(51L);
    verify(userRepository, never()).deleteById(51L);
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
    verify(childDeletionService, never()).deleteAllSolelyOwnedBy(51L);
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
    verify(childDeletionService, never()).deleteAllSolelyOwnedBy(51L);
  }
}
