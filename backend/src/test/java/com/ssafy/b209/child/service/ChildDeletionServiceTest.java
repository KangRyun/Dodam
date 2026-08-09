package com.ssafy.b209.child.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.child.dto.request.DeleteChildRequest;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildDeletionRepository;
import com.ssafy.b209.conversation.service.ConversationEventDeletionService;
import com.ssafy.b209.drawing.service.StrokeBatchDeletionService;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ChildDeletionServiceTest {

  private static final long GUARDIAN_ID = 10L;
  private static final long CHILD_ID = 3L;
  private static final Instant NOW = Instant.parse("2026-07-24T01:00:00Z");

  @Mock private ChildDeletionRepository childDeletionRepository;
  @Mock private StrokeBatchDeletionService strokeBatchDeletionService;
  @Mock private ConversationEventDeletionService conversationEventDeletionService;

  private ChildDeletionService childDeletionService;

  @BeforeEach
  void setUp() {
    childDeletionService =
        new ChildDeletionService(
            childDeletionRepository,
            strokeBatchDeletionService,
            conversationEventDeletionService,
            Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void marksTheOnlyGuardiansChildDeletedAndSchedulesStoredFiles() {
    given(childDeletionRepository.lockAccessibleChild(GUARDIAN_ID, CHILD_ID)).willReturn(true);
    given(childDeletionRepository.countGuardians(CHILD_ID)).willReturn(1);

    childDeletionService.delete(GUARDIAN_ID, CHILD_ID, new DeleteChildRequest("DELETE"));

    InOrder order = inOrder(childDeletionRepository);
    order
        .verify(childDeletionRepository)
        .markDeleted(CHILD_ID, NOW.atOffset(ZoneOffset.UTC).toLocalDateTime());
    order.verify(childDeletionRepository).scheduleStorageDeletions(CHILD_ID);
    // 삭제된 아동의 그리기 과정 데이터도 함께 지운다 (CLAUDE.md 9절).
    verify(strokeBatchDeletionService).deleteByChild(CHILD_ID);
    // 대화 행동 이벤트도 같은 이유로 함께 지운다 (S15P11B209-973). 이 호출이 빠지면 삭제된 아동의
    //   "언제 무엇을 했는가"가 보관 기간(TTL)까지 남는다.
    verify(conversationEventDeletionService).deleteByChild(CHILD_ID);
  }

  @Test
  void rejectsDeletionWhenAnotherGuardianIsConnected() {
    given(childDeletionRepository.lockAccessibleChild(GUARDIAN_ID, CHILD_ID)).willReturn(true);
    given(childDeletionRepository.countGuardians(CHILD_ID)).willReturn(2);

    assertError(
        () -> childDeletionService.delete(GUARDIAN_ID, CHILD_ID, new DeleteChildRequest("DELETE")),
        ChildErrorCode.CHILD_HAS_OTHER_GUARDIAN);

    verify(childDeletionRepository, never())
        .markDeleted(org.mockito.ArgumentMatchers.anyLong(), org.mockito.ArgumentMatchers.any());
  }

  @Test
  void deletesOnlyChildrenReturnedByTheSoleOwnershipLock() {
    given(childDeletionRepository.lockSolelyOwnedChildIds(GUARDIAN_ID))
        .willReturn(List.of(CHILD_ID));

    int deleted = childDeletionService.deleteAllSolelyOwnedBy(GUARDIAN_ID);

    assertThat(deleted).isEqualTo(1);
    verify(childDeletionRepository).lockSolelyOwnedChildIds(GUARDIAN_ID);
    verify(childDeletionRepository)
        .markDeleted(CHILD_ID, NOW.atOffset(ZoneOffset.UTC).toLocalDateTime());
    verify(childDeletionRepository).scheduleStorageDeletions(CHILD_ID);
    verify(strokeBatchDeletionService).deleteByChild(CHILD_ID);
    // 탈퇴 경로도 개별 삭제와 같은 범위를 지워야 한다 (S15P11B209-973).
    verify(conversationEventDeletionService).deleteByChild(CHILD_ID);
  }

  @Test
  void hidesMissingOrUnconnectedChildAndRejectsWrongConfirmation() {
    assertError(
        () -> childDeletionService.delete(GUARDIAN_ID, CHILD_ID, new DeleteChildRequest("delete")),
        ChildErrorCode.CHILD_DELETION_CONFIRMATION_MISMATCH);
    verify(childDeletionRepository, never()).lockAccessibleChild(GUARDIAN_ID, CHILD_ID);

    given(childDeletionRepository.lockAccessibleChild(GUARDIAN_ID, CHILD_ID)).willReturn(false);
    assertError(
        () -> childDeletionService.delete(GUARDIAN_ID, CHILD_ID, new DeleteChildRequest("DELETE")),
        ChildErrorCode.CHILD_NOT_FOUND);
  }

  @Test
  void treatsMissingBodyAndBlankConfirmationAsTheSameConfirmationError() {
    assertError(
        () -> childDeletionService.delete(GUARDIAN_ID, CHILD_ID, null),
        ChildErrorCode.CHILD_DELETION_CONFIRMATION_MISMATCH);
    assertError(
        () -> childDeletionService.delete(GUARDIAN_ID, CHILD_ID, new DeleteChildRequest("")),
        ChildErrorCode.CHILD_DELETION_CONFIRMATION_MISMATCH);
    assertError(
        () -> childDeletionService.delete(GUARDIAN_ID, CHILD_ID, new DeleteChildRequest(null)),
        ChildErrorCode.CHILD_DELETION_CONFIRMATION_MISMATCH);

    verify(childDeletionRepository, never()).lockAccessibleChild(GUARDIAN_ID, CHILD_ID);
  }

  private void assertError(Runnable invocation, ChildErrorCode expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
