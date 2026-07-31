package com.ssafy.b209.child.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;

import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import com.ssafy.b209.child.dto.request.UpdateChildRequest;
import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildUpdateRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ChildUpdateServiceTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-24T03:00:00Z"), ZoneOffset.UTC);

  @Mock private ChildUpdateRepository childUpdateRepository;
  @Mock private ChildQueryService childQueryService;
  @Mock private ChildProfileImageLinkService profileImageLinkService;

  private ChildUpdateService service;

  @BeforeEach
  void setUp() {
    service =
        new ChildUpdateService(
            childUpdateRepository, childQueryService, profileImageLinkService, CLOCK);
  }

  @Test
  void updatesOnlyProvidedProfileFieldsAndReturnsTheLatestDetail() {
    UpdateChildRequest request =
        new UpdateChildRequest(
            "새별이",
            null,
            GuardianRelationshipType.FATHER,
            null,
            QuestionDifficulty.UPPER_ELEMENTARY,
            List.of(ResponseMode.EMOJI, ResponseMode.VOICE, ResponseMode.EMOJI),
            null);
    ChildDetailResponse expected = org.mockito.Mockito.mock(ChildDetailResponse.class);
    given(childUpdateRepository.lockAccessibleChild(10L, 3L)).willReturn(true);
    given(childQueryService.getChild(10L, 3L)).willReturn(expected);

    service.update(10L, 3L, request);

    verify(childUpdateRepository)
        .updateProfile(
            3L,
            "새별이",
            null,
            null,
            QuestionDifficulty.UPPER_ELEMENTARY,
            LocalDateTime.of(2026, 7, 24, 3, 0));
    verify(childUpdateRepository).updateRelationship(10L, 3L, GuardianRelationshipType.FATHER);
    verify(childUpdateRepository)
        .replaceResponseModes(3L, List.of(ResponseMode.EMOJI, ResponseMode.VOICE));
    verify(childQueryService).getChild(10L, 3L);
  }

  @Test
  void rejectsAnUnconnectedOrDeletedChildWithoutUpdatingIt() {
    given(childUpdateRepository.lockAccessibleChild(10L, 99L)).willReturn(false);

    assertThatThrownBy(
            () ->
                service.update(
                    10L, 99L, new UpdateChildRequest("새별이", null, null, null, null, null, null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_NOT_FOUND));

    verifyNoMoreInteractions(childUpdateRepository);
  }

  @Test
  void rejectsAnUpdatedBirthDateOutsideTheAllowedAgeRange() {
    given(childUpdateRepository.lockAccessibleChild(10L, 3L)).willReturn(true);

    assertThatThrownBy(
            () ->
                service.update(
                    10L,
                    3L,
                    new UpdateChildRequest(
                        null, LocalDate.of(2024, 1, 1), null, null, null, null, null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_AGE_OUT_OF_RANGE));

    verifyNoMoreInteractions(childUpdateRepository);
  }

  @Test
  void explicitNullProfileImageRemovesItWhileOmittedFieldKeepsIt() {
    given(childUpdateRepository.lockAccessibleChild(10L, 3L)).willReturn(true);
    given(childQueryService.getChild(10L, 3L))
        .willReturn(org.mockito.Mockito.mock(ChildDetailResponse.class));
    UpdateChildRequest request = new UpdateChildRequest();
    request.setProfileImageFileId(null);

    service.update(10L, 3L, request);

    verify(profileImageLinkService).replace(10L, 3L, null);
    verify(childUpdateRepository)
        .updateProfileImageUrl(3L, null, LocalDateTime.of(2026, 7, 24, 3, 0));
  }
}
