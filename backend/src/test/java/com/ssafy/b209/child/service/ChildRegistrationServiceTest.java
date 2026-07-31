package com.ssafy.b209.child.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import com.ssafy.b209.child.dto.request.RegisterChildRequest;
import com.ssafy.b209.child.dto.response.ChildRegistrationResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildRegistrationRepository;
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
class ChildRegistrationServiceTest {

  private static final Long GUARDIAN_USER_ID = 10L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-23T12:00:00Z"), ZoneOffset.UTC);

  @Mock private ChildRegistrationRepository childRegistrationRepository;
  @Mock private ChildProfileImageLinkService profileImageLinkService;

  private ChildRegistrationService service;

  @BeforeEach
  void setUp() {
    service =
        new ChildRegistrationService(childRegistrationRepository, profileImageLinkService, CLOCK);
  }

  @Test
  void persistsTheChildRelationAndResponseModesThenReturnsTheProfile() {
    given(childRegistrationRepository.insertChild(any(), any(), any(), any(), any(), any()))
        .willReturn(3L);

    ChildRegistrationResponse response =
        service.register(
            GUARDIAN_USER_ID,
            request(LocalDate.of(2019, 3, 15), List.of(ResponseMode.VOICE, ResponseMode.EMOJI)));

    verify(childRegistrationRepository)
        .insertChild(
            "별이",
            LocalDate.of(2019, 3, 15),
            "LOWER_ELEMENTARY",
            "BASE",
            null,
            LocalDateTime.of(2026, 7, 23, 12, 0, 0));
    verify(childRegistrationRepository).insertGuardianRelation(GUARDIAN_USER_ID, 3L, "MOTHER");
    verify(childRegistrationRepository).insertResponseModes(3L, List.of("VOICE", "EMOJI"));

    assertThat(response.childId()).isEqualTo(3L);
    assertThat(response.age()).isEqualTo(7);
    assertThat(response.relationshipType()).isEqualTo(GuardianRelationshipType.MOTHER);
    assertThat(response.responseModes()).containsExactly(ResponseMode.VOICE, ResponseMode.EMOJI);
    assertThat(response.tutorialStatus()).isEqualTo(ChildTutorialStatus.NOT_STARTED);
    assertThat(response.profileStatus()).isEqualTo(ChildProfileStatus.ACTIVE);
    assertThat(response.createdAt()).isEqualTo(Instant.parse("2026-07-23T12:00:00Z"));
  }

  @Test
  void removesDuplicateResponseModesWhileKeepingTheFirstOrder() {
    given(childRegistrationRepository.insertChild(any(), any(), any(), any(), any(), any()))
        .willReturn(7L);

    ChildRegistrationResponse response =
        service.register(
            GUARDIAN_USER_ID,
            request(
                LocalDate.of(2018, 1, 1),
                List.of(ResponseMode.VOICE, ResponseMode.EMOJI, ResponseMode.VOICE)));

    verify(childRegistrationRepository).insertResponseModes(7L, List.of("VOICE", "EMOJI"));
    assertThat(response.responseModes()).containsExactly(ResponseMode.VOICE, ResponseMode.EMOJI);
  }

  @Test
  void rejectsAChildYoungerThanTheAllowedAgeWithoutPersisting() {
    assertThatThrownBy(
            () ->
                service.register(
                    GUARDIAN_USER_ID,
                    request(LocalDate.of(2023, 1, 1), List.of(ResponseMode.VOICE))))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_AGE_OUT_OF_RANGE));
    verifyNoInteractions(childRegistrationRepository);
  }

  @Test
  void rejectsAChildOlderThanTheAllowedAgeWithoutPersisting() {
    assertThatThrownBy(
            () ->
                service.register(
                    GUARDIAN_USER_ID,
                    request(LocalDate.of(2010, 1, 1), List.of(ResponseMode.VOICE))))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_AGE_OUT_OF_RANGE));
    verifyNoInteractions(childRegistrationRepository);
  }

  @Test
  void attachesUploadedProfileImageInTheSameRegistrationTransaction() {
    given(childRegistrationRepository.insertChild(any(), any(), any(), any(), any(), any()))
        .willReturn(3L);
    given(profileImageLinkService.attach(GUARDIAN_USER_ID, 3L, "profile-file-id"))
        .willReturn("/api/v1/child-profile-images/profile-file-id/file");
    RegisterChildRequest request =
        new RegisterChildRequest(
            "별이",
            LocalDate.of(2019, 3, 15),
            GuardianRelationshipType.MOTHER,
            "BASE",
            QuestionDifficulty.LOWER_ELEMENTARY,
            List.of(ResponseMode.VOICE),
            "profile-file-id");

    ChildRegistrationResponse response = service.register(GUARDIAN_USER_ID, request);

    verify(childRegistrationRepository)
        .updateProfileImageUrl(
            3L,
            "/api/v1/child-profile-images/profile-file-id/file",
            LocalDateTime.of(2026, 7, 23, 12, 0));
    assertThat(response.profileImageUrl())
        .isEqualTo("/api/v1/child-profile-images/profile-file-id/file");
  }

  private RegisterChildRequest request(LocalDate birthDate, List<ResponseMode> responseModes) {
    return new RegisterChildRequest(
        "별이",
        birthDate,
        GuardianRelationshipType.MOTHER,
        "BASE",
        QuestionDifficulty.LOWER_ELEMENTARY,
        responseModes,
        null);
  }
}
