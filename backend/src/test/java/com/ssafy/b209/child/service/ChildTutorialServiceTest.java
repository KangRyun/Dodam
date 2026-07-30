package com.ssafy.b209.child.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.dto.request.UpdateChildTutorialProgressRequest;
import com.ssafy.b209.child.dto.response.ChildTutorialProgressResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildUpdateRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ChildTutorialServiceTest {

  private static final long GUARDIAN_USER_ID = 10L;
  private static final long CHILD_ID = 3L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-30T02:03:04Z"), ZoneOffset.UTC);

  @Mock private ChildUpdateRepository childUpdateRepository;
  @Mock private ChildQueryService childQueryService;

  private ChildTutorialService service;

  @BeforeEach
  void setUp() {
    service = new ChildTutorialService(childUpdateRepository, childQueryService, CLOCK);
  }

  @Test
  void startsTheTutorialAndStoresTheLastStep() {
    given(childUpdateRepository.lockAccessibleChild(GUARDIAN_USER_ID, CHILD_ID)).willReturn(true);
    given(childUpdateRepository.findTutorialStatus(CHILD_ID))
        .willReturn(ChildTutorialStatus.NOT_STARTED);
    ChildTutorialProgressResponse expected =
        new ChildTutorialProgressResponse(
            CHILD_ID,
            ChildTutorialStatus.IN_PROGRESS,
            "WELCOME",
            null,
            Instant.parse("2026-07-30T02:03:04Z"));
    given(childQueryService.getTutorialProgress(GUARDIAN_USER_ID, CHILD_ID)).willReturn(expected);

    ChildTutorialProgressResponse actual =
        service.updateProgress(
            GUARDIAN_USER_ID,
            CHILD_ID,
            new UpdateChildTutorialProgressRequest(ChildTutorialStatus.IN_PROGRESS, "WELCOME"));

    assertThat(actual).isEqualTo(expected);
    verify(childUpdateRepository)
        .updateTutorialProgress(
            CHILD_ID,
            ChildTutorialStatus.IN_PROGRESS,
            "WELCOME",
            null,
            LocalDateTime.of(2026, 7, 30, 2, 3, 4));
  }

  @Test
  void completesAnInProgressTutorialAndRecordsTheCompletionTime() {
    given(childUpdateRepository.lockAccessibleChild(GUARDIAN_USER_ID, CHILD_ID)).willReturn(true);
    given(childUpdateRepository.findTutorialStatus(CHILD_ID))
        .willReturn(ChildTutorialStatus.IN_PROGRESS);
    given(childQueryService.getTutorialProgress(GUARDIAN_USER_ID, CHILD_ID))
        .willReturn(
            new ChildTutorialProgressResponse(
                CHILD_ID,
                ChildTutorialStatus.COMPLETED,
                "FINISH",
                Instant.parse("2026-07-30T02:03:04Z"),
                Instant.parse("2026-07-30T02:03:04Z")));

    ChildTutorialProgressResponse response =
        service.updateProgress(
            GUARDIAN_USER_ID,
            CHILD_ID,
            new UpdateChildTutorialProgressRequest(ChildTutorialStatus.COMPLETED, "FINISH"));

    assertThat(response.completedAt()).isEqualTo(Instant.parse("2026-07-30T02:03:04Z"));
    verify(childUpdateRepository)
        .updateTutorialProgress(
            CHILD_ID,
            ChildTutorialStatus.COMPLETED,
            "FINISH",
            LocalDateTime.of(2026, 7, 30, 2, 3, 4),
            LocalDateTime.of(2026, 7, 30, 2, 3, 4));
  }

  @Test
  void skipsAnInProgressTutorialAndRecordsTheCompletionTime() {
    given(childUpdateRepository.lockAccessibleChild(GUARDIAN_USER_ID, CHILD_ID)).willReturn(true);
    given(childUpdateRepository.findTutorialStatus(CHILD_ID))
        .willReturn(ChildTutorialStatus.IN_PROGRESS);
    given(childQueryService.getTutorialProgress(GUARDIAN_USER_ID, CHILD_ID))
        .willReturn(
            new ChildTutorialProgressResponse(
                CHILD_ID,
                ChildTutorialStatus.SKIPPED,
                "DRAWING_GUIDE",
                Instant.parse("2026-07-30T02:03:04Z"),
                Instant.parse("2026-07-30T02:03:04Z")));

    service.updateProgress(
        GUARDIAN_USER_ID,
        CHILD_ID,
        new UpdateChildTutorialProgressRequest(ChildTutorialStatus.SKIPPED, null));

    verify(childUpdateRepository)
        .updateTutorialProgress(
            CHILD_ID,
            ChildTutorialStatus.SKIPPED,
            null,
            LocalDateTime.of(2026, 7, 30, 2, 3, 4),
            LocalDateTime.of(2026, 7, 30, 2, 3, 4));
  }

  @Test
  void returnsAnAlreadyCompletedTutorialWithoutChangingItsCompletionTime() {
    given(childUpdateRepository.lockAccessibleChild(GUARDIAN_USER_ID, CHILD_ID)).willReturn(true);
    given(childUpdateRepository.findTutorialStatus(CHILD_ID))
        .willReturn(ChildTutorialStatus.COMPLETED);
    ChildTutorialProgressResponse expected =
        new ChildTutorialProgressResponse(
            CHILD_ID,
            ChildTutorialStatus.COMPLETED,
            "FINISH",
            Instant.parse("2026-07-29T01:00:00Z"),
            Instant.parse("2026-07-29T01:00:00Z"));
    given(childQueryService.getTutorialProgress(GUARDIAN_USER_ID, CHILD_ID)).willReturn(expected);

    ChildTutorialProgressResponse response =
        service.updateProgress(
            GUARDIAN_USER_ID,
            CHILD_ID,
            new UpdateChildTutorialProgressRequest(ChildTutorialStatus.COMPLETED, "FINISH"));

    assertThat(response).isEqualTo(expected);
    verify(childUpdateRepository, never())
        .updateTutorialProgress(
            org.mockito.ArgumentMatchers.anyLong(),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any());
  }

  @Test
  void rejectsReturningACompletedTutorialToInProgress() {
    given(childUpdateRepository.lockAccessibleChild(GUARDIAN_USER_ID, CHILD_ID)).willReturn(true);
    given(childUpdateRepository.findTutorialStatus(CHILD_ID))
        .willReturn(ChildTutorialStatus.COMPLETED);

    assertThatThrownBy(
            () ->
                service.updateProgress(
                    GUARDIAN_USER_ID,
                    CHILD_ID,
                    new UpdateChildTutorialProgressRequest(
                        ChildTutorialStatus.IN_PROGRESS, "WELCOME")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_TUTORIAL_STATUS_CONFLICT));

    verify(childUpdateRepository, never())
        .updateTutorialProgress(
            org.mockito.ArgumentMatchers.anyLong(),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any());
  }

  @Test
  void hidesAnInaccessibleChildWithTheCommonNotFoundError() {
    given(childUpdateRepository.lockAccessibleChild(GUARDIAN_USER_ID, CHILD_ID)).willReturn(false);

    assertThatThrownBy(
            () ->
                service.updateProgress(
                    GUARDIAN_USER_ID,
                    CHILD_ID,
                    new UpdateChildTutorialProgressRequest(
                        ChildTutorialStatus.IN_PROGRESS, "WELCOME")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(ChildErrorCode.CHILD_NOT_FOUND));

    verify(childUpdateRepository, never()).findTutorialStatus(CHILD_ID);
  }
}
