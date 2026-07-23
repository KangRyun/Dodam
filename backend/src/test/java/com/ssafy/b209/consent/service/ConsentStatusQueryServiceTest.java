package com.ssafy.b209.consent.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.domain.ConsentTerm;
import com.ssafy.b209.consent.dto.response.ConsentStatusResponse;
import com.ssafy.b209.consent.exception.ConsentErrorCode;
import com.ssafy.b209.consent.repository.ConsentAuthorizationRepository;
import com.ssafy.b209.consent.repository.ConsentStatusRepository;
import com.ssafy.b209.consent.repository.ConsentTermRepository;
import com.ssafy.b209.consent.repository.LatestConsentAction;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class ConsentStatusQueryServiceTest {

  private static final Long USER_ID = 41L;
  private static final Long CHILD_ID = 5L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-23T12:00:00Z"), ZoneOffset.UTC);
  private static final LocalDateTime PAST = LocalDateTime.of(2020, 1, 1, 0, 0);

  @Mock private ConsentTermRepository termRepository;
  @Mock private ConsentStatusRepository statusRepository;
  @Mock private ConsentAuthorizationRepository authorizationRepository;

  private ConsentStatusQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new ConsentStatusQueryService(
            termRepository, statusRepository, authorizationRepository, CLOCK);
  }

  @Test
  void marksRequiredTermSatisfiedWhenLatestActionIsAgree() {
    given(termRepository.findAllByActiveTrue())
        .willReturn(List.of(userTerm(1L, "SERVICE_TOS", true)));
    given(statusRepository.findLatestUserScopeActions(USER_ID))
        .willReturn(
            List.of(
                new LatestConsentAction(
                    1L, ConsentAction.AGREE, LocalDateTime.of(2026, 7, 21, 2, 30))));

    ConsentStatusResponse response = service.getConsentStatus(USER_ID, null);

    assertThat(response.childId()).isNull();
    assertThat(response.requiredConsentsSatisfied()).isTrue();
    assertThat(response.items()).hasSize(1);
    assertThat(response.items().getFirst().termId()).isEqualTo(1L);
    assertThat(response.items().getFirst().termCode()).isEqualTo("SERVICE_TOS");
    assertThat(response.items().getFirst().agreed()).isTrue();
    assertThat(response.items().getFirst().recordedAt())
        .isEqualTo(LocalDateTime.of(2026, 7, 21, 2, 30).toInstant(ZoneOffset.UTC));
  }

  @Test
  void marksRequiredTermUnsatisfiedWhenNoRecordExists() {
    given(termRepository.findAllByActiveTrue())
        .willReturn(List.of(userTerm(1L, "SERVICE_TOS", true)));
    given(statusRepository.findLatestUserScopeActions(USER_ID)).willReturn(List.of());

    ConsentStatusResponse response = service.getConsentStatus(USER_ID, null);

    assertThat(response.requiredConsentsSatisfied()).isFalse();
    assertThat(response.items().getFirst().agreed()).isFalse();
    assertThat(response.items().getFirst().recordedAt()).isNull();
  }

  @Test
  void rejectsChildStatusWhenActorIsNotTheGuardian() {
    given(authorizationRepository.hasGuardianChildRelation(USER_ID, CHILD_ID)).willReturn(false);

    assertThatThrownBy(() -> service.getConsentStatus(USER_ID, CHILD_ID))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConsentErrorCode.CONSENT_ACTOR_NOT_GUARDIAN));
    verifyNoInteractions(termRepository, statusRepository);
  }

  private ConsentTerm userTerm(Long id, String code, boolean required) {
    ConsentTerm term =
        ConsentTerm.define(
            code,
            ConsentTargetScope.USER,
            required,
            "v1",
            code + " 제목",
            "https://example.com/" + code,
            PAST,
            true,
            PAST);
    ReflectionTestUtils.setField(term, "id", id);
    return term;
  }
}
