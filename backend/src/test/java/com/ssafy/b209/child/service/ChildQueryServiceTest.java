package com.ssafy.b209.child.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoMoreInteractions;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildDetailProjection;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ChildQueryServiceTest {

  private static final Long GUARDIAN_USER_ID = 10L;
  private static final Long CHILD_ID = 3L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-22T12:00:00Z"), ZoneOffset.UTC);

  @Mock private ChildRepository childRepository;

  private ChildQueryService service;

  @BeforeEach
  void setUp() {
    service = new ChildQueryService(childRepository, CLOCK);
  }

  @Test
  void returnsTheConnectedActiveChildProfile() {
    ChildDetailProjection projection = projection(LocalDate.of(2019, 7, 23));
    given(childRepository.findDetailByGuardianUserIdAndChildId(GUARDIAN_USER_ID, CHILD_ID))
        .willReturn(Optional.of(projection));
    given(childRepository.findResponseModesByChildId(CHILD_ID))
        .willReturn(List.of("VOICE", "EMOJI", "COLOR"));

    ChildDetailResponse response = service.getChild(GUARDIAN_USER_ID, CHILD_ID);

    assertThat(response.childId()).isEqualTo(CHILD_ID);
    assertThat(response.nickname()).isEqualTo("별이");
    assertThat(response.birthDate()).isEqualTo(LocalDate.of(2019, 7, 23));
    assertThat(response.age()).isEqualTo(6);
    assertThat(response.profileImageUrl()).isEqualTo("https://cdn.example/child/3");
    assertThat(response.preferredCharacter()).isEqualTo("MONGLE");
    assertThat(response.questionDifficulty()).isEqualTo(QuestionDifficulty.LOWER_ELEMENTARY);
    assertThat(response.responseModes()).containsExactly("VOICE", "EMOJI", "COLOR");
    assertThat(response.tutorialStatus()).isEqualTo(ChildTutorialStatus.IN_PROGRESS);
    assertThat(response.profileStatus()).isEqualTo(ChildProfileStatus.ACTIVE);
    assertThat(response.relationshipType()).isEqualTo("MOTHER");
    assertThat(response.createdAt()).isEqualTo(Instant.parse("2026-07-20T01:02:03Z"));
    assertThat(response.updatedAt()).isEqualTo(Instant.parse("2026-07-21T04:05:06Z"));
  }

  @Test
  void usesFullAgeOnTheChildBirthday() {
    ChildDetailProjection projection = projection(LocalDate.of(2019, 7, 22));
    given(childRepository.findDetailByGuardianUserIdAndChildId(GUARDIAN_USER_ID, CHILD_ID))
        .willReturn(Optional.of(projection));
    given(childRepository.findResponseModesByChildId(CHILD_ID)).willReturn(List.of());

    ChildDetailResponse response = service.getChild(GUARDIAN_USER_ID, CHILD_ID);

    assertThat(response.age()).isEqualTo(7);
  }

  @Test
  void reportsTheSameNotFoundErrorWhenTheAuthorizedQueryReturnsNothing() {
    given(childRepository.findDetailByGuardianUserIdAndChildId(GUARDIAN_USER_ID, CHILD_ID))
        .willReturn(Optional.empty());

    assertThatThrownBy(() -> service.getChild(GUARDIAN_USER_ID, CHILD_ID))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(ChildErrorCode.CHILD_NOT_FOUND));
    verifyNoMoreInteractions(childRepository);
  }

  private ChildDetailProjection projection(LocalDate birthDate) {
    ChildDetailProjection projection = mock(ChildDetailProjection.class);
    given(projection.getChildId()).willReturn(CHILD_ID);
    given(projection.getNickname()).willReturn("별이");
    given(projection.getBirthDate()).willReturn(birthDate);
    given(projection.getProfileImageUrl()).willReturn("https://cdn.example/child/3");
    given(projection.getPreferredCharacter()).willReturn("MONGLE");
    given(projection.getQuestionDifficulty()).willReturn("LOWER_ELEMENTARY");
    given(projection.getTutorialStatus()).willReturn("IN_PROGRESS");
    given(projection.getProfileStatus()).willReturn("ACTIVE");
    given(projection.getRelationshipType()).willReturn("MOTHER");
    given(projection.getCreatedAt()).willReturn(LocalDateTime.of(2026, 7, 20, 1, 2, 3));
    given(projection.getUpdatedAt()).willReturn(LocalDateTime.of(2026, 7, 21, 4, 5, 6));
    return projection;
  }
}
